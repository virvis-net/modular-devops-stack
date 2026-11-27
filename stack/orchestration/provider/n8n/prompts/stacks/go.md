## Stack-specific rules: Go

This is a Go application. These rules extend the rules above.

### Commands
- Tests of one package: `go test ./<package-dir>/...`
- One test: `go test ./<package-dir>/... -run <TestName>`
- Several packages affected: `go test ./...`
- Formatter: `gofmt -l -w <files>` (only the Go files you changed)
- Add a dependency: `go get <module>`, then `go mod tidy`

### Locating code
- For an HTTP route, search for the last path segment with `git grep`. The handler is the function registered for that path in the router setup.

### Tests
- Existing tests are the *_test.go files next to the code they cover. Follow their style.

### Dependencies
- Prefer the standard library over a new dependency.
- Change go.mod and go.sum only through `go get` and `go mod tidy`, and commit them together.
- Do not edit files that start with a "Code generated ... DO NOT EDIT" header.

### Formatting
- Run gofmt on every changed Go file before committing, and keep the diff free of unrelated reformatting.

### Never modify or stage
- vendor/ (if present)
