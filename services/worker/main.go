// worker は短縮 URL へのアクセスを受け取って、短縮コードごとの回数を集計する。
package main

import (
	"flag"
	"io"
	"log"
	"net"
	"net/http"

	"google.golang.org/protobuf/encoding/protojson"

	clicksv1 "github.com/ymotongpoo/bazel-k8s-sample/proto/clicks/v1"
	"github.com/ymotongpoo/bazel-k8s-sample/services/worker/counter"
)

func main() {
	addr := flag.String("addr", ":8081", "listen address")
	flag.Parse()

	counts := counter.New()
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		io.WriteString(w, "ok\n")
	})
	mux.HandleFunc("POST /clicks", func(w http.ResponseWriter, r *http.Request) {
		if ct := r.Header.Get("Content-Type"); ct != "application/json" {
			http.Error(w, "content type must be application/json", http.StatusUnsupportedMediaType)
			return
		}
		body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 1024))
		if err != nil {
			http.Error(w, "cannot read request", http.StatusBadRequest)
			return
		}
		var ev clicksv1.ClickEvent
		if err := protojson.Unmarshal(body, &ev); err != nil || ev.GetCode() == "" {
			http.Error(w, "invalid request", http.StatusBadRequest)
			return
		}
		counts.Add(ev.GetCode())
		w.WriteHeader(http.StatusNoContent)
	})
	mux.HandleFunc("GET /stats/{code}", func(w http.ResponseWriter, r *http.Request) {
		code := r.PathValue("code")
		resp, err := protojson.Marshal(&clicksv1.ClickStats{Code: code, Count: counts.Get(code)})
		if err != nil {
			http.Error(w, "cannot encode response", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write(resp)
	})

	ln, err := net.Listen("tcp", *addr)
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("listening on %s", ln.Addr())
	log.Fatal(http.Serve(ln, mux))
}
