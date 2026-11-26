// api は短縮 URL を発行し、短縮コードへのアクセスを元の URL へリダイレクトする。
package main

import (
	"bytes"
	"embed"
	"flag"
	"io"
	"io/fs"
	"log"
	"net"
	"net/http"
	"time"

	"golang.org/x/time/rate"
	"google.golang.org/protobuf/encoding/protojson"

	clicksv1 "github.com/ymotongpoo/bazel-k8s-sample/proto/clicks/v1"
	shortenerv1 "github.com/ymotongpoo/bazel-k8s-sample/proto/shortener/v1"
	"github.com/ymotongpoo/bazel-k8s-sample/services/api/shortener"
)

// ui は //web:dist のフロントエンド。Bazel が services/api/ui にコピーしたものを埋め込む。
//
//go:embed ui
var ui embed.FS

func main() {
	addr := flag.String("addr", ":8080", "listen address")
	limit := flag.Float64("rate", 10, "shorten requests allowed per second")
	burst := flag.Int("burst", 20, "maximum burst of shorten requests")
	worker := flag.String("worker", "", "base URL of the click worker; clicks are not recorded if empty")
	flag.Parse()

	store := shortener.NewStore()
	// 発行の要求だけを、サーバー全体でまとめて制限する。
	limiter := rate.NewLimiter(rate.Limit(*limit), *burst)
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		io.WriteString(w, "ok\n")
	})
	mux.HandleFunc("POST /shorten", func(w http.ResponseWriter, r *http.Request) {
		if !limiter.Allow() {
			http.Error(w, "too many requests", http.StatusTooManyRequests)
			return
		}
		body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 4096))
		if err != nil {
			http.Error(w, "cannot read request", http.StatusBadRequest)
			return
		}
		var req shortenerv1.ShortenRequest
		if err := protojson.Unmarshal(body, &req); err != nil {
			http.Error(w, "invalid request", http.StatusBadRequest)
			return
		}
		if req.GetUrl() == "" {
			http.Error(w, "url is required", http.StatusBadRequest)
			return
		}
		resp, err := protojson.Marshal(&shortenerv1.ShortenResponse{Code: store.Shorten(req.GetUrl())})
		if err != nil {
			http.Error(w, "cannot encode response", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write(resp)
	})
	static, err := fs.Sub(ui, "ui")
	if err != nil {
		log.Fatal(err)
	}
	mux.Handle("GET /ui/", http.StripPrefix("/ui/", http.FileServerFS(static)))
	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
		http.ServeFileFS(w, r, static, "index.html")
	})
	mux.HandleFunc("GET /{code}", func(w http.ResponseWriter, r *http.Request) {
		url, err := store.Resolve(r.PathValue("code"))
		if err != nil {
			http.NotFound(w, r)
			return
		}
		if *worker != "" {
			go recordClick(*worker, r.PathValue("code"))
		}
		http.Redirect(w, r, url, http.StatusFound)
	})

	// ポートに 0 を指定すると OS が空いているポートを選ぶので、実際に待ち受けたアドレスを出力する。
	ln, err := net.Listen("tcp", *addr)
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("listening on %s", ln.Addr())
	log.Fatal(http.Serve(ln, mux))
}

// recordClick はワーカーにアクセスを1回知らせる。失敗してもリダイレクトには影響させない。
func recordClick(worker, code string) {
	body, err := protojson.Marshal(&clicksv1.ClickEvent{Code: code})
	if err != nil {
		log.Printf("cannot encode click: %v", err)
		return
	}
	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Post(worker+"/clicks", "application/json", bytes.NewReader(body))
	if err != nil {
		log.Printf("cannot record click: %v", err)
		return
	}
	resp.Body.Close()
}
