# Laravel API Starter

This is an optional Laravel 12 / PHP 8.3 backend template for the Modular
DevOps Stack. It keeps the existing `app` image name, container port, health
checks, CI image publishing, and Flux staging/production flow. Select it when
rendering the repositories with `./scripts/copy-templates.sh laravel`.

The starter includes a JSON endpoint at `/api/hello`, liveness at `/healthz`,
readiness at `/readyz`, and Prometheus metrics at `/metrics` on the internal
metrics port `9090`. That port is not routed by the app Ingress. Its HTTP
request counter and duration histogram use the same technology-neutral metric
names as the Go example and are scraped by the existing monitoring stack.
Health and scrape requests are excluded. Laravel metrics are stored in a
local SQLite file so they aggregate across PHP requests; they reset when the
container is replaced and are intended for this single-replica local lab.

The image installs the OpenTelemetry PHP extension, SDK, OTLP exporter, and
official Laravel auto-instrumentation package. With
`OTEL_PHP_AUTOLOAD_ENABLED=true`, Laravel request spans are exported over
OTLP/HTTP to the configured Collector endpoint. The shared deployment sets
`OTEL_SERVICE_NAME=app` and points the exporter at the in-cluster Collector.
In Grafana, open Explore, select Tempo, and search for service `app` to inspect
the request traces. The starter does not export Laravel logs over OTLP, so
trace-to-logs correlation is not enabled for this template.

The starter does not include a database deployment, authentication, or queue
worker. Its routes are stateless; provide `APP_KEY` as a secret before adding
features that use encrypted cookies, sessions, or other application
encryption. Do not commit the key or other credentials to GitOps.

The CI job installs Composer dependencies and runs `php artisan test` before
building the image. Generate and commit `composer.lock` with Composer before
using this as a long-lived application so dependency resolution is
reproducible.

For local development, copy `.env.example` to `.env`, install dependencies
with Composer, and run `php artisan key:generate` before using encrypted
cookies, sessions, or other application encryption.

The image uses PHP's built-in development server, which is suitable for this
local lab, not a production web server. For production, replace it with a
maintained PHP application-server setup and shared metrics storage
appropriate for multiple workers. Review runtime, secrets, database,
migrations, storage, and backup requirements.
