# Laravel API Template

This Laravel 13 / PHP 8.5 backend template is an application option for the
Modular DevOps Stack. It uses the `app` image name, container port, health
checks, CI image publishing, and Flux staging/production flow. Select it when
rendering the repositories with `./scripts/copy-templates.sh laravel`.

The starter includes a JSON endpoint at `/api/hello`, liveness at `/healthz`,
readiness at `/readyz`, and Prometheus metrics at `/metrics` on the internal
metrics port `9090`. HTTP requests are served by FrankenPHP and Caddy; the
metrics endpoint runs on a separate PHP built-in server listener. The built-in
server is limited to this internal, unrouted metrics port and does not serve
application traffic.
Port `9090` is not routed by the app Ingress. The HTTP request counter and
duration histogram use technology-neutral metric names and are scraped by the
monitoring stack. Health and scrape requests are excluded. The SQLite file at
`storage/framework/cache/http-metrics.sqlite` is used only to aggregate
Prometheus request and PHP runtime metrics across requests; it is not the
application database. Metric data resets when the container is replaced and
is intended for this single-replica local lab.
The `/metrics` output also includes PHP memory usage and peak memory from the
last application request, plus garbage-collection counters and buffered roots.
These runtime samples are updated after application requests and reflect the
last request served by the PHP application runtime.

The image installs the OpenTelemetry PHP extension, SDK, OTLP exporter, and
official Laravel auto-instrumentation package. With
`OTEL_PHP_AUTOLOAD_ENABLED=true`, Laravel request spans are exported over
OTLP/HTTP to the configured Collector endpoint. The shared deployment sets
`OTEL_SERVICE_NAME=app` and points the exporter at the in-cluster Collector.
The Laravel Monolog channel also exports structured logs over OTLP. Logs keep
the active trace and span IDs, so Grafana can link between Tempo traces and Loki
logs. In Grafana, open Explore, select Tempo, and search for service `app` to
inspect request traces; choose a span and use its Logs link to find matching
Loki entries. Avoid logging lead form values, credentials, or other sensitive
data because the same log record is sent to both container stderr and Loki.

The `config/cors.php` configuration supports the separate Vue frontend
template. Set `CORS_ALLOWED_ORIGINS` to the exact browser origin in the
matching `apps/app/overlays/staging/runtime.env` or
`apps/app/overlays/production/runtime.env` file in GitOps. The defaults are
`http://staging.localhost` and `http://production.localhost` for frontends on
the default HTTP port `80`; add a port such as `:8081` only when the frontend
uses a non-default HTTP port. Browsers omit the default `:80` when serializing
an origin. CORS allows the W3C `traceparent`, `tracestate`, and `baggage`
headers so the browser's trace context can reach Laravel. The generated
runtime configuration enables the `tracecontext,baggage` propagators. CORS
does not authenticate requests; keep the allowlist narrow and do not log
submitted personal data.

In the two-stack Vue/Laravel exercise, this API stack forwards its traces and
OTLP logs to the frontend stack's central Collector. Open the combined trace
and its trace-to-logs links in the frontend stack's Grafana.

The application has Laravel's database and cache integrations configured for
MariaDB 13.0 and Redis 8.10, which are deployed with the Laravel GitOps
template in each environment. The sample API has not yet added
application-specific models, migrations, or queries; add those as application
features require them. The template includes a migration only for Laravel's
failed-job table. MariaDB data is stored in a per-environment persistent
volume, while Redis is an ephemeral cache. Create the `app-database`
Kubernetes Secret in both `staging` and `production` before deploying to those
namespaces. Production is opt-in, so create its Secret when enabling that
environment. Generate separate credentials for each namespace:

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

### Connecting to a Kubernetes database

You can use HeidiSQL to inspect either environment without exposing MariaDB
outside the cluster. In a terminal with the correct Kubernetes context, start
a local port-forward. Keep this command running while HeidiSQL is connected:

```sh
# Staging
kubectl port-forward --namespace staging service/mariadb 3308:3306

# Production
kubectl port-forward --namespace production service/mariadb 3309:3306
```

The database user and database name are both `app`. Retrieve the password for
the chosen namespace from its Kubernetes Secret:

```sh
# Replace staging with production when connecting to production.
kubectl get secret app-database --namespace staging \
  --output jsonpath='{.data.password}' | base64 --decode
echo
```

In HeidiSQL, create a MariaDB/MySQL session with host `127.0.0.1`, port
`3308` or `3309`, user `app`, database `app`, and the decoded password. The Kubernetes
user running `kubectl` must be allowed to read the Secret and port-forward to
the database pod. Stop the port-forward with Ctrl-C when finished.

Production database access should be exceptional and authorized. Use the
production context and Secret only when needed, avoid saving the production
password in HeidiSQL, and do not paste it into chat or store it in Git. The
`app` account is the application's database account, not a read-only account;
avoid running queries that modify production data.

## Local development with Dev Containers

Open the app repository in VS Code and choose **Dev Containers: Reopen in
Container**. The devcontainer runs FrankenPHP and the metrics listener with
Laravel's local/debug settings, and forwards HTTP on `8080` and metrics on
`9090`. On startup it installs Composer dependencies, creates `.env` if needed,
and generates a local application key.

The Laravel `.devcontainer/compose.infra.yaml` provides a local MariaDB and
Redis for this app only. These are development-only services and credentials,
separate from MariaDB 13.0 and Redis 8.10 deployed by this template in Kubernetes.
Compose keeps this data and network separate from the Modular DevOps Stack.
MariaDB is published only on localhost port `3307` for desktop database
clients. In HeidiSQL, connect to host `127.0.0.1`, port `3307`, user `app`,
password `app`, and database `app`. These credentials are for local
development only.

The Laravel GitOps component also deploys one Redis-backed queue worker per
environment. It runs `php artisan queue:work` as its container's main process;
Kubernetes restarts it and controls its replica count, so Supervisor is not
needed. Worker traces use the service name `app-worker`. Worker settings are
in `gitops/runtime.env`, including queue names,
sleep interval, retry count, timeout, and maximum worker lifetime. The worker
timeout is 90 seconds, the queue reservation timeout is 120 seconds, and the
pod termination grace period is 120 seconds so a worker can finish its
current job during a rollout.

To change the default worker settings for a new setup, edit the Laravel
template's `gitops/runtime.env`. For an already-rendered stack, edit
`apps/app/base/app-template/runtime.env` in the GitOps repository for shared
settings, or override a setting in
`apps/app/overlays/staging/runtime.env` or
`apps/app/overlays/production/runtime.env`. Kustomize merges overlay values
into the base ConfigMap; Flux applies its new hashed reference and Kubernetes
rolls out the app and worker pods. To change worker capacity for new setups,
edit `gitops/worker-deployment.yaml` in this template. For an installed stack,
adjust `replicas` in
`apps/app/base/app-template/worker-deployment.yaml` or use an environment
overlay patch for different staging and production capacity. App code changes
are built into the shared image and its digest update applies to both the web
and worker Deployments. `gitops/runtime.env` is intentionally tracked despite
the repository's general `*.env` ignore rule; it contains non-secret
deployment configuration. Do not put credentials in it.

Queue jobs that exhaust their retries are recorded in Laravel's `failed_jobs`
table. A dedicated Kubernetes Job runs `php artisan migrate --force` using the
exact image digest selected for the release. Flux
reconciles database dependencies first, waits for the migration Job to
complete, and only then reconciles the web and worker Deployments. A migration
failure blocks that release's workloads and must be fixed before deployment
continues. The template does not yet enqueue jobs; add dispatching as
application features require it.

The GitOps component also installs a Kubernetes CronJob that runs
`php artisan schedule:run` every minute. Define scheduled tasks in
`routes/console.php`; code and schedule changes are delivered with the app
image. The CronJob uses the same runtime ConfigMap and database Secret as the
app and worker, and scheduler traces use the service name `app-scheduler`.
`concurrencyPolicy: Forbid` prevents overlapping scheduler runs, while a
five-minute active deadline bounds a stuck run. If a run is still active at
the next tick, Kubernetes skips that tick. Keep scheduled work short or
dispatch long-running work to the queue. For tasks that need cross-run
exclusion, use Laravel's `withoutOverlapping()` or `onOneServer()` scheduling
locks; the configured Redis cache provides the shared lock store.

Each Laravel environment has separate Flux reconciliations for its database
dependencies, migrations, and workloads. The staging CI job updates the image
digest in both the staging workload and migration overlays, and creates a
release-specific migration Job and Flux dependency. This ensures the workload
waits for the migration Job for that exact release rather than relying on a
previous release's successful status.

When promoting to production, use the same release ID as staging (the first
12 hexadecimal characters of the digest). Set the digest in both
`apps/app/overlays/production/kustomization.yaml` and
`apps/app/overlays/production/migration/kustomization.yaml`, and set the
migration overlay's `nameSuffix` to `-<release-id>`. In
`clusters/<cluster>/environments/production/app-template/migration-kustomization.yaml`,
set the Kustomization name to `production-app-migration-<release-id>`. In
`workload-kustomization.yaml`, update `dependsOn.name` to that same
`production-app-migration-<release-id>` value. Make these changes before
enabling production.

### Production rollback

A production image downgrade by itself is not a database rollback. The normal
migration Job runs `php artisan migrate`, which applies pending migrations but
does not call migrations' `down()` methods. Laravel's
`php artisan migrate:rollback` does call `down()`, but it is a separate
operation. The current template does not automate reverse migrations: do not
try to initiate this workflow just by changing the production image digest.

A database-aware rollback must be an explicit, gated operation that reverses
the deployment sequence:

1. Record the current production image digest and the target previous digest.
   The currently deployed image must remain available because it contains the
   migration files whose `down()` methods will be run. Identify and review the
   exact migration batch or number of steps to reverse; Laravel's default
   rollback can reverse multiple migrations from a batch.
2. Pause the ordinary forward migration and workload reconciliations so they
   cannot race with rollback. Stop new web traffic and scale the web and queue
   worker workloads to zero. Wait for pods to terminate and workers to finish
   in-flight jobs; the worker's termination grace period is 120 seconds.
3. Run a one-off rollback Job using the **currently deployed image** and the
   reviewed rollback scope. Wait for successful Job completion before
   proceeding. If draining or the Job fails, stop and recover deliberately;
   do not deploy the target image against an uncertain schema.
4. Only after rollback succeeds, set the web and worker image to the previous
   digest, and reconcile those workloads. Verify readiness and application
   behavior before restoring normal forward-deploy reconciliation.
5. Close the rollback operation and ensure the production migration and
   workload configuration agree on the target release before resuming normal
   releases.

This sequence should be implemented as a dedicated rollback mode or workflow
with explicit current and target digests, rollback scope, and success gates.
A plain Git revert or digest edit is insufficient: Flux must not apply the
target image until the rollback Job succeeds. If the database rollback loses
data, fails partway, or leaves the schema uncertain, keep the app stopped and
use the reviewed recovery plan, which may require restoring a backup or
applying a forward fix.

Reverse migrations can be destructive. Prefer expand/contract migrations so
the previous app can run against the newer schema; use database rollback only
when the affected `down()` methods and data impact have been reviewed and a
backup is available.

The Dev Container runs `composer install` on startup, which creates
`composer.lock` if it is absent. Commit that generated file before the first
push; CI and the production image require it and use `composer install`. To
generate the lock manually, run this from the app repository root before the
first push:

```sh
composer update --no-interaction --prefer-dist
```

Both methods resolve dependency versions and write `composer.lock`. After it is
committed, `composer install` uses those locked versions.

For local development, copy `.env.example` to `.env`, install dependencies
with Composer, and run `php artisan key:generate` before using encrypted
cookies, sessions, or other application encryption.

The image uses FrankenPHP and Caddy for HTTP serving. The separate metrics
listener remains a lightweight PHP listener on an internal, unrouted port.
The Caddy configuration caps PHP request execution at four concurrent
threads and recycles each thread after 500 requests.
Request metrics are aggregated in a local SQLite file, which is suitable for
this single-replica learning stack; use shared metrics storage before scaling
the web Deployment to multiple pods. Review runtime, secrets, database,
migrations, storage, and backup requirements before production use.
