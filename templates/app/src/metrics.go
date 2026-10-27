package main

import (
	"fmt"
	"net/http"
	"runtime"
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

	var runtimeStats runtime.MemStats
	runtime.ReadMemStats(&runtimeStats)

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
	fmt.Fprintln(w, "# HELP go_goroutines Number of goroutines that currently exist.")
	fmt.Fprintln(w, "# TYPE go_goroutines gauge")
	fmt.Fprintf(w, "go_goroutines %d\n", runtime.NumGoroutine())
	fmt.Fprintln(w, "# HELP go_memstats_alloc_bytes Bytes of allocated heap objects.")
	fmt.Fprintln(w, "# TYPE go_memstats_alloc_bytes gauge")
	fmt.Fprintf(w, "go_memstats_alloc_bytes %d\n", runtimeStats.Alloc)
	fmt.Fprintln(w, "# HELP go_memstats_heap_inuse_bytes Bytes in in-use heap spans.")
	fmt.Fprintln(w, "# TYPE go_memstats_heap_inuse_bytes gauge")
	fmt.Fprintf(w, "go_memstats_heap_inuse_bytes %d\n", runtimeStats.HeapInuse)
	fmt.Fprintln(w, "# HELP go_memstats_heap_sys_bytes Bytes of heap memory obtained from the OS.")
	fmt.Fprintln(w, "# TYPE go_memstats_heap_sys_bytes gauge")
	fmt.Fprintf(w, "go_memstats_heap_sys_bytes %d\n", runtimeStats.HeapSys)
	fmt.Fprintln(w, "# HELP go_memstats_stack_inuse_bytes Bytes in stack spans.")
	fmt.Fprintln(w, "# TYPE go_memstats_stack_inuse_bytes gauge")
	fmt.Fprintf(w, "go_memstats_stack_inuse_bytes %d\n", runtimeStats.StackInuse)
	fmt.Fprintln(w, "# HELP go_gc_cycles_total Total number of completed garbage collection cycles.")
	fmt.Fprintln(w, "# TYPE go_gc_cycles_total counter")
	fmt.Fprintf(w, "go_gc_cycles_total %d\n", runtimeStats.NumGC)

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
