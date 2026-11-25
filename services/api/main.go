// api は短縮 URL を発行し、短縮コードへのアクセスを元の URL へリダイレクトする。
package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"

	"golang.org/x/time/rate"

	"github.com/ymotongpoo/bazel-k8s-sample/services/api/shortener"
)

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
		url := r.FormValue("url")
		if url == "" {
			http.Error(w, "url is required", http.StatusBadRequest)
			return
		}
		fmt.Fprintln(w, store.Shorten(url))
	})
	mux.HandleFunc("GET /{code}", func(w http.ResponseWriter, r *http.Request) {
		url, err := store.Resolve(r.PathValue("code"))
		if err != nil {
			http.NotFound(w, r)
			return
		}
		http.Redirect(w, r, url, http.StatusFound)
	})

	log.Printf("listening on %s", *addr)
	log.Fatal(http.ListenAndServe(*addr, mux))
}
