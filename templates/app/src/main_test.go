package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHandlers(t *testing.T) {
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

			handler().ServeHTTP(response, request)

			if response.Code != test.wantStatus {
				t.Fatalf("handler returned status %d, want %d", response.Code, test.wantStatus)
			}
			if response.Body.String() != test.wantBody {
				t.Errorf("handler returned %q, want %q", response.Body.String(), test.wantBody)
			}
		})
	}
}
