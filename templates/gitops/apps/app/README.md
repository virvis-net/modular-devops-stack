# App Manifests

The `base/` directory contains the shared app Deployment and Service.
Environment overlays in `overlays/staging/` and `overlays/production/` select
the environment namespace and tune replicas/resources.

Keep environment-specific services, configuration, secrets, and persistent
storage in the corresponding environment overlay so staging and production do
not share runtime dependencies. The sample app does not currently require a
database or cache.
