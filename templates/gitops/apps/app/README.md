# App Manifests

The `base/` directory contains the shared app Deployment and Service.
Environment overlays in `overlays/staging/` and `overlays/production/` select
the environment namespace and tune replicas/resources.

Keep environment-specific services, configuration, secrets, and persistent
storage in the corresponding environment overlay so staging and production do
not share runtime dependencies. The sample app does not currently require a
database or cache.

The shared Deployment configures liveness and readiness probes against the
app's `/healthz` and `/readyz` endpoints.

The app Service exposes its internal `/metrics` endpoint on the `metrics`
port. Applications publish the `http_server_requests_total` counter and
`http_server_request_duration_seconds` histogram for Prometheus and the shared
dashboard. Runtime-specific metrics may also be exposed, but the shared
dashboard and alerts do not depend on them.
