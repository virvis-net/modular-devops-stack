package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel/trace"
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
	return otelhttp.NewHandler(
		metrics.instrument(mux),
		"http.server",
		otelhttp.WithFilter(func(r *http.Request) bool {
			return r.URL.Path != "/healthz" && r.URL.Path != "/readyz"
		}),
	)
}

func metricsHandler(metrics *appMetrics) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/metrics", metrics.serveHTTP)
	return mux
}

func logRequest(r *http.Request, status int, duration time.Duration) {
	spanContext := trace.SpanContextFromContext(r.Context())
	args := []any{
		"method", r.Method,
		"path", r.URL.Path,
		"status", status,
		"duration_ms", float64(duration.Microseconds()) / 1000,
	}
	if spanContext.IsValid() {
		args = append(args,
			"trace_id", spanContext.TraceID().String(),
			"span_id", spanContext.SpanID().String(),
		)
	}
	slog.InfoContext(r.Context(), "HTTP request completed", args...)
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "app stopped with an error: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	shutdownTelemetry, err := initTelemetry(ctx)
	if err != nil {
		return fmt.Errorf("initialize OpenTelemetry: %w", err)
	}
	slog.SetDefault(slog.New(createOTelSlogHandler()))

	metrics := newAppMetrics()
	appServer := &http.Server{Addr: ":8080", Handler: applicationHandler(metrics)}
	metricsServer := &http.Server{Addr: ":9090", Handler: metricsHandler(metrics)}
	serverErrors := make(chan error, 2)

	slog.Info("starting app servers", "http_address", appServer.Addr, "metrics_address", metricsServer.Addr)
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
