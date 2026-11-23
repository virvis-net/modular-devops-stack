## Stack-specific rules: Laravel

This is a Laravel application. These rules extend the sections above.

- Section 3, step 2: if the issue concerns an HTTP route, routes in routes/api.php are served under the /api prefix, so /api/hello is declared there as '/hello'. Search routes/ for the last path segment. A file that only mentions the path (for example as a JSON field) is not the handler.
- Section 3, step 3: do not add traits to tests.
- Section 4: the runtime is not available if `php` is missing.
