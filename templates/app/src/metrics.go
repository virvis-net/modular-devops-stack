package main

import (
	"fmt"
	"net/http"
	"sort"
	"sync"
	"time"
)

var durationBuckets = []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10}

type requestLabels struct {
	method string
	status int
}

type requestObservation struct {
	count       uint64
	durationSum float64
	buckets     []uint64
}

type appMetrics struct {
	mu       sync.Mutex
	requests map[requestLabels]*requestObservation
}

func newAppMetrics() *appMetrics {
	return &appMetrics{requests: make(map[requestLabels]*requestObservation)}
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (recorder *statusRecorder) WriteHeader(status int) {
	if recorder.status != 0 {
		return
	}
	recorder.status = status
	recorder.ResponseWriter.WriteHeader(status)
}

func (recorder *statusRecorder) Write(body []byte) (int, error) {
	if recorder.status == 0 {
		recorder.WriteHeader(http.StatusOK)
	}
	return recorder.ResponseWriter.Write(body)
}

func normalizedMethod(method string) string {
	switch method {
	case http.MethodGet, http.MethodHead, http.MethodPost, http.MethodPut,
		http.MethodPatch, http.MethodDelete, http.MethodOptions:
		return method
	default:
		return "OTHER"
	}
}

func (metrics *appMetrics) instrument(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/healthz" || r.URL.Path == "/readyz" {
			next.ServeHTTP(w, r)
			return
		}

		recorder := &statusRecorder{ResponseWriter: w}
		start := time.Now()
		next.ServeHTTP(recorder, r)
		if recorder.status == 0 {
			recorder.status = http.StatusOK
		}

		metrics.observe(normalizedMethod(r.Method), recorder.status, time.Since(start).Seconds())
	})
}

func (metrics *appMetrics) observe(method string, status int, duration float64) {
	labels := requestLabels{method: method, status: status}

	metrics.mu.Lock()
	defer metrics.mu.Unlock()

	observation, exists := metrics.requests[labels]
	if !exists {
		observation = &requestObservation{buckets: make([]uint64, len(durationBuckets))}
		metrics.requests[labels] = observation
	}
	observation.count++
	observation.durationSum += duration
	for index, boundary := range durationBuckets {
		if duration <= boundary {
			observation.buckets[index]++
		}
	}
}

func (metrics *appMetrics) serveHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")

	metrics.mu.Lock()
	labels := make([]requestLabels, 0, len(metrics.requests))
	observations := make(map[requestLabels]requestObservation, len(metrics.requests))
	for label := range metrics.requests {
		labels = append(labels, label)
		observation := metrics.requests[label]
		observations[label] = requestObservation{
			count:       observation.count,
			durationSum: observation.durationSum,
			buckets:     append([]uint64(nil), observation.buckets...),
		}
	}
	metrics.mu.Unlock()

	sort.Slice(labels, func(i, j int) bool {
		if labels[i].method == labels[j].method {
			return labels[i].status < labels[j].status
		}
		return labels[i].method < labels[j].method
	})

	fmt.Fprintln(w, "# HELP app_http_requests_total Total HTTP requests handled by the app.")
	fmt.Fprintln(w, "# TYPE app_http_requests_total counter")
	fmt.Fprintln(w, "# HELP app_http_request_duration_seconds HTTP request duration in seconds.")
	fmt.Fprintln(w, "# TYPE app_http_request_duration_seconds histogram")

	for _, label := range labels {
		observation := observations[label]
		labelSet := fmt.Sprintf(`method="%s",status="%d"`, label.method, label.status)
		fmt.Fprintf(w, "app_http_requests_total{%s} %d\n", labelSet, observation.count)

		for index, boundary := range durationBuckets {
			fmt.Fprintf(
				w,
				`app_http_request_duration_seconds_bucket{%s,le="%g"} %d`+"\n",
				labelSet,
				boundary,
				observation.buckets[index],
			)
		}
		fmt.Fprintf(w, `app_http_request_duration_seconds_bucket{%s,le="+Inf"} %d`+"\n", labelSet, observation.count)
		fmt.Fprintf(w, "app_http_request_duration_seconds_sum{%s} %g\n", labelSet, observation.durationSum)
		fmt.Fprintf(w, "app_http_request_duration_seconds_count{%s} %d\n", labelSet, observation.count)
	}
}
