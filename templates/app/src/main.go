package main

import (
	"fmt"
	"log"
	"net/http"
)

func homeHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintf(w, "Hello from Modular DevOps Stack App!\n")
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintln(w, "ok")
}

func readyHandler(w http.ResponseWriter, r *http.Request) {
	// Before reporting ready, check required dependencies and return
	// ServiceUnavailable if one is unavailable. For example:
	// if err := db.PingContext(r.Context()); err != nil {
	//     http.Error(w, "database unavailable", http.StatusServiceUnavailable)
	//     return
	// }
	fmt.Fprintln(w, "ok")
}

func handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", healthHandler)
	mux.HandleFunc("/readyz", readyHandler)
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		homeHandler(w, r)
	})
	return mux
}

func main() {
	fmt.Println("Starting server on :8080")
	log.Fatal(http.ListenAndServe(":8080", handler()))
}
