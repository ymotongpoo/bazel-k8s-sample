// api は短縮 URL を発行し、短縮コードへのアクセスを元の URL へリダイレクトする。
package main

import (
	"embed"
	"flag"
	"io"
	"io/fs"
	"log"
	"net"
	"net/http"

	"golang.org/x/time/rate"
	"google.golang.org/protobuf/encoding/protojson"

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
	flag.Parse()

	store := shortener.NewStore()
	// 発行の要求だけを、サーバー全体でまとめて制限する。
	limiter := rate.NewLimiter(rate.Limit(*limit), *burst)
	mux := http.NewServeMux()
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
