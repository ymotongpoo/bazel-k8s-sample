// api は短縮 URL を発行し、短縮コードへのアクセスを元の URL へリダイレクトする。
package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"

	"github.com/ymotongpoo/bazel-k8s-sample/services/api/shortener"
)

func main() {
	addr := flag.String("addr", ":8080", "listen address")
	flag.Parse()

	store := shortener.NewStore()
	mux := http.NewServeMux()
	mux.HandleFunc("POST /shorten", func(w http.ResponseWriter, r *http.Request) {
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
