## Stack-specific rules: Go

This is a Go application. These rules extend the sections above.

- Section 3, step 2: if the issue concerns an HTTP route, search for the last path segment with `git grep`. The handler is the function registered for that path in the router setup. A file that only mentions the path (for example as a JSON field or in a test) is not the handler.
- Section 3, step 3: existing tests are the `*_test.go` files next to the code they cover. Update them in place; do not add test helpers or dependencies they do not use.
- Section 3, step 4: do not change `go.mod` or `go.sum` unless the issue requires a new dependency. Keep the code formatted as `gofmt` would.
- Section 4: run the tests of the affected package with `go test`. The runtime is not available if `go` is missing.
