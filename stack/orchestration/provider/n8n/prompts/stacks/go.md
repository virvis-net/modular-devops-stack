## Stack-specific rules: Go

This is a Go application. These rules extend the sections above.

- Section 3, step 2: if the issue concerns an HTTP route, search for the last path segment with `git grep`. The handler is the function registered for that path in the router setup. A file that only mentions the path (for example as a JSON field or in a test) is not the handler.

- Section 3, step 3: existing tests are the `*_test.go` files next to the code they cover. Update them in place; do not add test helpers or dependencies they do not use.

- Section 3, step 4: do not change `go.mod` or `go.sum` unless the issue requires a new dependency. Keep the code formatted as `gofmt` would.

- If a devcontainer is available and the Go toolchain is not available in the workspace, attempt to execute Go commands inside the devcontainer before concluding that the runtime is unavailable.

- When a dependency is added, removed or upgraded:
  - update both `go.mod` and `go.sum`;
  - generate dependency changes using Go tooling;
  - never edit `go.mod` or `go.sum` manually.

- After modifying dependencies, run:
  - `go mod tidy`

- Before committing Go changes, run:
  - `gofmt` on every modified Go source file, using the devcontainer toolchain when available.

- When tests are run inside the devcontainer, use the devcontainer Go toolchain as the authoritative environment.

- Section 4: run the tests of the affected package with `go test`. If the change affects multiple packages, run the narrowest set of packages that covers the change. The runtime is not available only if Go is unavailable both in the workspace and in an available devcontainer.

- Prefer existing standard-library packages over introducing new dependencies.
