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
environment. The sample API has not yet added application-specific models,
migrations, or queries; add those as application features require them. The
template includes a migration only for Laravel's failed-job table. MariaDB
data is stored in a per-environment persistent volume, while Redis is an
ephemeral cache. Create the `app-database` Kubernetes Secret in both `staging` and
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
`apps/app/base/app-template/runtime.env` in the GitOps repository and push the
change. Kustomize generates a content-hashed ConfigMap; Flux applies the new
reference and Kubernetes rolls out the app and worker pods. To change worker
capacity for new setups, edit `gitops/worker-deployment.yaml` in this
template. For an installed stack, adjust `replicas` in
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
