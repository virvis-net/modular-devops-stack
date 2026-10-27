package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHandlers(t *testing.T) {
	app := applicationHandler(newAppMetrics())
	tests := []struct {
		name       string
		path       string
		wantStatus int
		wantBody   string
	}{
		{
			name:       "home",
			path:       "/",
			wantStatus: http.StatusOK,
			wantBody:   "Hello from Modular DevOps Stack App!\n",
		},
		{
			name:       "liveness",
			path:       "/healthz",
			wantStatus: http.StatusOK,
			wantBody:   "ok\n",
		},
		{
			name:       "readiness",
			path:       "/readyz",
			wantStatus: http.StatusOK,
			wantBody:   "ok\n",
		},
		{
			name:       "not found",
			path:       "/missing",
			wantStatus: http.StatusNotFound,
			wantBody:   "404 page not found\n",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			request := httptest.NewRequest(http.MethodGet, test.path, nil)
			response := httptest.NewRecorder()

			app.ServeHTTP(response, request)

			if response.Code != test.wantStatus {
				t.Fatalf("handler returned status %d, want %d", response.Code, test.wantStatus)
			}
			if test.wantBody != "" && response.Body.String() != test.wantBody {
				t.Errorf("handler returned %q, want %q", response.Body.String(), test.wantBody)
			}
		})
	}
}

func TestMetricsRecordRequestsAndDurations(t *testing.T) {
	metrics := newAppMetrics()
	app := applicationHandler(metrics)

	for _, path := range []string{"/", "/missing", "/healthz", "/readyz"} {
		response := httptest.NewRecorder()
		app.ServeHTTP(response, httptest.NewRequest(http.MethodGet, path, nil))
	}

	response := httptest.NewRecorder()
	metricsHandler(metrics).ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/metrics", nil))

	body := response.Body.String()
	if response.Header().Get("Content-Type") != "text/plain; version=0.0.4; charset=utf-8" {
		t.Errorf("metrics content type = %q", response.Header().Get("Content-Type"))
	}
	for _, want := range []string{
		"# TYPE app_http_requests_total counter",
		"# TYPE app_http_request_duration_seconds histogram",
		"# TYPE go_goroutines gauge",
		"# TYPE go_memstats_alloc_bytes gauge",
		"# TYPE go_memstats_heap_inuse_bytes gauge",
		"# TYPE go_memstats_heap_sys_bytes gauge",
		"# TYPE go_memstats_stack_inuse_bytes gauge",
		"# TYPE go_gc_cycles_total counter",
		`app_http_requests_total{method="GET",status="200"} 1`,
		`app_http_requests_total{method="GET",status="404"} 1`,
		`app_http_request_duration_seconds_bucket{method="GET",status="200",le="+Inf"} 1`,
		`app_http_request_duration_seconds_count{method="GET",status="404"} 1`,
	} {
		if !strings.Contains(body, want) {
			t.Errorf("metrics response does not contain %q:\n%s", want, body)
		}
	}
	for _, metric := range []string{
		"go_goroutines ",
		"go_memstats_alloc_bytes ",
		"go_memstats_heap_inuse_bytes ",
		"go_memstats_heap_sys_bytes ",
		"go_memstats_stack_inuse_bytes ",
		"go_gc_cycles_total ",
	} {
		if !strings.Contains(body, metric) {
			t.Errorf("metrics response does not contain a value for %q:\n%s", metric, body)
		}
	}
	if strings.Contains(body, `method="GET",status="200"} 3`) {
		t.Error("health and metrics endpoints should not be included in request counts")
	}
}
