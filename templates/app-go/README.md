# Go Application Template

This repository contains a Go application and Woodpecker pipeline for the
Modular DevOps Stack lab. Select it when rendering the repositories with
`./scripts/copy-templates.sh` or `./scripts/copy-templates.sh go`.

## Delivery flow

The pipeline in `.woodpecker.yml`:

1. Runs the Go test suite on each branch push.
2. On a push to `main`, builds and pushes an image tagged with the commit SHA.
3. Records the registry's immutable image digest in the staging GitOps overlay.
4. Flux deploys the image to the staging namespace.

Production promotion is a separate GitOps change that copies the tested
staging digest into the production overlay and enables the production
environment in the cluster Kustomization. You can make the change directly on
`main` or use a pull request for review. Either way, this promotes the same
image without rebuilding it.

## Setup

1. Push the contents of this directory to the Gitea `__GITEA_ORG__/app`
   repository.
2. In Woodpecker, activate `__GITEA_ORG__/app` and mark it as trusted because
   the build mounts the Docker socket.
3. From the framework repository, add the contents of the Flux deploy key's
   private key file (by default `stack/.state/ssh/flux_deploy_key`) to the
   `__GITEA_ORG__/app` repository secrets in Woodpecker as `GIT_SSH_KEY`. If
   `FLUX_PRIVATE_KEY` is set in the framework's `.env`, use that path instead.
   The key's public half must already have write access to
   `__GITEA_ORG__/gitops`. Do not commit or share the private key.
4. Merge an app change to `main` and confirm that the pipeline publishes an
   image and updates staging in the GitOps repository.

The setup helper renders `.woodpecker.yml` with the registry and Gitea SSH
settings from the stack's `.env`.

The app responds with `200 OK` at `/healthz` and `/readyz`. Kubernetes uses
these endpoints for liveness and readiness probes in both staging and
production. Readiness currently matches liveness because the sample app has no
external dependencies.

The app exposes technology-neutral HTTP request counters and
request-duration histograms in Prometheus text format at `/metrics` on
internal port `9090`. The endpoint is not routed by the app Ingress. Health
and metrics scrape requests are excluded from the HTTP request metrics. The
endpoint also exposes Go runtime goroutine, heap, stack, and garbage-collection
metrics using the Go standard library.

The HTTP server is instrumented with OpenTelemetry and exports traces, HTTP
server metrics, and structured request logs over OTLP/HTTP to the Collector at
`http://otel-collector.monitoring.svc:4318`. Request logs include the active
trace and span IDs. The monitoring provider routes traces to Tempo, logs to
Loki, and metrics to Prometheus; the app instrumentation does not depend on
these backends. In Grafana Explore, query Loki with
`{service_name="app"} | trace_id != ""` and follow the TraceID link to
Tempo. Set `OTEL_SERVICE_NAME` and `OTEL_EXPORTER_OTLP_ENDPOINT` to use a
different service name or Collector endpoint.

## Local development with Dev Containers

Open the app repository in VS Code and choose **Dev Containers: Reopen in
Container**. The Go app runs with `go run ./src`; use the forwarded port `8080`
for HTTP and `9090` for metrics.

The Go devcontainer has no MariaDB or Redis services because the Go app does
not depend on them. Its separate Compose project and private default network
keep it from joining or changing the Modular DevOps Stack network.
