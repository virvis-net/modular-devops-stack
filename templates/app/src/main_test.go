package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHandler(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/", nil)
	response := httptest.NewRecorder()

	handler(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("handler returned status %d, want %d", response.Code, http.StatusOK)
	}

	const want = "Hello from Modular DevOps Stack App!\n"
	if response.Body.String() != want {
		t.Errorf("handler returned %q, want %q", response.Body.String(), want)
	}
}
