# App Manifests

The `base/` directory contains the shared app Deployment and Service.
Environment overlays in `overlays/staging/` and `overlays/production/` select
the environment namespace and tune replicas/resources.

The rendered base includes the runtime dependencies selected by the
application template. Resources in the base are instantiated in each
environment namespace so staging and production do not share runtime
dependencies. Keep credentials out of Git and provision required Kubernetes
Secrets in each namespace before deploying workloads that reference them.

The shared Deployment configures liveness and readiness probes against the
app's `/healthz` and `/readyz` endpoints.

The app Service exposes its internal `/metrics` endpoint on the `metrics`
port. Applications publish the `http_server_requests_total` counter and
`http_server_request_duration_seconds` histogram for Prometheus and the shared
dashboard. Runtime-specific metrics may also be exposed, but the shared
dashboard and alerts do not depend on them.
