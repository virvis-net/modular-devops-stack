# Laravel API Template

This Laravel 12 / PHP 8.3 backend template is an application option for the
Modular DevOps Stack. It uses the `app` image name, container port, health
checks, CI image publishing, and Flux staging/production flow. Select it when
rendering the repositories with `./scripts/copy-templates.sh laravel`.

The starter includes a JSON endpoint at `/api/hello`, liveness at `/healthz`,
readiness at `/readyz`, and Prometheus metrics at `/metrics` on the internal
metrics port `9090`. That port is not routed by the app Ingress. Its HTTP
request counter and duration histogram use technology-neutral metric names
and are scraped by the monitoring stack. Health and scrape requests are
excluded. The SQLite file at `storage/framework/cache/http-metrics.sqlite` is
used only to aggregate Prometheus request and PHP runtime metrics across
separate PHP requests; it is not the application's database. Metric data
resets when the container is replaced and is intended for this single-replica
local lab.
The `/metrics` output also includes PHP memory usage and peak memory from the
last application request, plus garbage-collection counters and buffered roots.
These runtime samples are updated after application requests and are specific
to the single-process PHP built-in server used here.

The image installs the OpenTelemetry PHP extension, SDK, OTLP exporter, and
official Laravel auto-instrumentation package. With
`OTEL_PHP_AUTOLOAD_ENABLED=true`, Laravel request spans are exported over
OTLP/HTTP to the configured Collector endpoint. The shared deployment sets
`OTEL_SERVICE_NAME=app` and points the exporter at the in-cluster Collector.
In Grafana, open Explore, select Tempo, and search for service `app` to inspect
the request traces. The starter does not export Laravel logs over OTLP, so
trace-to-logs correlation is not enabled for this template.

The application has Laravel's database and cache integrations configured for
MariaDB and Redis, which are deployed with the Laravel GitOps template in each
environment. The sample API has not yet added application models, migrations,
or queries; add those as application features require them. MariaDB data is
stored in a per-environment persistent volume, while Redis is an ephemeral
cache. Create the `app-database` Kubernetes Secret in both `staging` and
`production` before deploying to those namespaces. Production is opt-in, so
create its Secret when enabling that environment. Generate separate
credentials for each namespace:

```sh
kubectl create secret generic app-database --namespace staging \
  --from-literal=root-password="$(python3 -c 'import secrets; print(secrets.token_hex(32))')" \
  --from-literal=password="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"

# Run after the production namespace has been created.
kubectl create secret generic app-database --namespace production \
  --from-literal=root-password="$(python3 -c 'import secrets; print(secrets.token_hex(32))')" \
  --from-literal=password="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
```

The secret is intentionally not stored in Git. These services are configured
for this local learning stack; add appropriate authentication, network
controls, backups, and operational management before adapting them for
production. The sample routes are stateless; provide `APP_KEY` as a secret
before adding features that use encrypted cookies, sessions, or other
application encryption. Do not commit keys or credentials to GitOps.

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
