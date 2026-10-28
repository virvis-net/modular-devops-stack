package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
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
	return otelhttp.NewHandler(metrics.instrument(mux), "http.server")
}

func metricsHandler(metrics *appMetrics) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/metrics", metrics.serveHTTP)
	return mux
}

func main() {
	if err := run(); err != nil {
		log.Fatal(err)
	}
}

func run() error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	shutdownTelemetry, err := initTelemetry(ctx)
	if err != nil {
		return fmt.Errorf("initialize OpenTelemetry: %w", err)
	}

	metrics := newAppMetrics()
	appServer := &http.Server{Addr: ":8080", Handler: applicationHandler(metrics)}
	metricsServer := &http.Server{Addr: ":9090", Handler: metricsHandler(metrics)}
	serverErrors := make(chan error, 2)

	fmt.Println("Starting app server on :8080 and metrics server on :9090")
	go func() { serverErrors <- appServer.ListenAndServe() }()
	go func() { serverErrors <- metricsServer.ListenAndServe() }()

	var runErr error
	select {
	case err := <-serverErrors:
		if !errors.Is(err, http.ErrServerClosed) {
			runErr = err
		}
	case <-ctx.Done():
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := appServer.Shutdown(shutdownCtx); err != nil {
		runErr = errors.Join(runErr, fmt.Errorf("shut down app server: %w", err))
	}
	if err := metricsServer.Shutdown(shutdownCtx); err != nil {
		runErr = errors.Join(runErr, fmt.Errorf("shut down metrics server: %w", err))
	}
	if err := shutdownTelemetry(shutdownCtx); err != nil {
		runErr = errors.Join(runErr, fmt.Errorf("shut down OpenTelemetry: %w", err))
	}
	return runErr
}
