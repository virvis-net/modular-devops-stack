# Example App Repository

This repository is a minimal Go application and Woodpecker pipeline for the
Modular DevOps Stack lab.

## Delivery flow

For every pipeline, `.woodpecker.yml`:

1. Runs the Go test suite.
2. On a push to `main`, builds and pushes an image tagged with the commit SHA.
3. Records the registry's immutable image digest in the staging GitOps overlay.
4. Flux deploys the image to the staging namespace.

Production promotion is a separate GitOps pull request that copies the tested
staging digest into the production overlay and enables the production
environment in the cluster Kustomization. This promotes the same image without
rebuilding it.

## Setup

1. Push the contents of this directory to the Gitea `__STACK_NAME__/app`
   repository.
2. In Woodpecker, activate `__STACK_NAME__/app` and mark it as trusted because
   the build mounts the Docker socket.
3. Add the contents of the Flux deploy key's private key file (by default
   `~/.ssh/flux_deploy_key`) to the `__STACK_NAME__/app` repository secrets in
   Woodpecker as `GIT_SSH_KEY`. Its public key must already be configured
   with write access to `__STACK_NAME__/gitops`. Do not commit the private key.
4. Merge an app change to `main` and confirm that the pipeline publishes an
   image and updates staging in the GitOps repository.

The setup helper renders `.woodpecker.yml` with the registry and Gitea SSH
settings from the stack's `.env`.

The app responds with `200 OK` at `/healthz` and `/readyz`. Kubernetes uses
these endpoints for liveness and readiness probes in both staging and
production. Readiness currently matches liveness because the sample app has no
external dependencies.

The app exposes request counters and request-duration histograms in Prometheus
text format at port `9090` on `/metrics`. That port is internal to the cluster
and is not routed by the app Ingress. Health and metrics scrape requests are
excluded from the application request metrics. The same endpoint also exposes
Go runtime goroutine, heap, stack, and garbage-collection metrics using the Go
standard library.

The HTTP server is also instrumented with OpenTelemetry and exports traces and
HTTP server metrics over OTLP/HTTP to the Collector at
`http://otel-collector.monitoring.svc:4318`. The Collector currently uses a
debug exporter, so after sending requests to the app you can inspect received
telemetry with `kubectl logs -n monitoring deployment/otel-collector`. Set
`OTEL_SERVICE_NAME` and `OTEL_EXPORTER_OTLP_ENDPOINT` to use a different
service name or Collector endpoint; instrumentation does not depend on a
specific telemetry backend.
