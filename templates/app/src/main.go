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

func applicationHandler(metrics *appMetrics) http.Handler {
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
	return metrics.instrument(mux)
}

func metricsHandler(metrics *appMetrics) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/metrics", metrics.serveHTTP)
	return mux
}

func main() {
	metrics := newAppMetrics()
	appServer := &http.Server{Addr: ":8080", Handler: applicationHandler(metrics)}
	metricsServer := &http.Server{Addr: ":9090", Handler: metricsHandler(metrics)}
	errors := make(chan error, 2)

	fmt.Println("Starting app server on :8080 and metrics server on :9090")
	go func() { errors <- appServer.ListenAndServe() }()
	go func() { errors <- metricsServer.ListenAndServe() }()
	log.Fatal(<-errors)
}
