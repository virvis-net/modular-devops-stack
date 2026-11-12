# Vue Frontend Template

This repository contains a small Vue 3 funnel UI, a Node.js static-file host,
and its Woodpecker build pipeline. Select it with
`./scripts/copy-templates.sh vue`. It is intended to run in a frontend stack
separate from a Laravel API stack.

## What the demo does

The three-step UI records browser page-load and funnel-navigation spans. On
the final step, **Send demo request** creates a client span and calls
`GET /api/hello` directly from the browser. The W3C `traceparent` header is
propagated to Laravel, whose request instrumentation continues that trace.
The topic selected in the demo remains in browser memory and is not submitted
or attached to spans.

The browser exports OTLP/HTTP protobuf to the same-origin
`/_otel/v1/traces` endpoint. The small Node server forwards that request to
the stack-local Collector at `otel-collector.monitoring.svc:4318`. The
Collector's configured export mode then keeps or forwards the trace. The
browser never receives Collector credentials.

In the two-stack exercise, this frontend stack is the central receiver. Its
Collector keeps browser spans locally, while the Laravel API stack's Collector
forwards backend spans and logs to it. The frontend stack's Grafana then shows
the combined trace and its trace-to-logs link can find the Laravel demo
`/api/hello` log record.

The relay accepts same-origin POST requests with OTLP protobuf content and
limits each batch to 1 MiB. It has no authentication and is not a production
ingestion gateway; the Origin check is a browser guard, not authentication.
Keep it inside this trusted local lab.

The [OpenTelemetry browser instrumentation guide](https://opentelemetry.io/docs/languages/js/getting-started/browser/)
marks browser instrumentation experimental. This starter uses explicit spans
and propagation so the trace path is visible in the code; it does not install
broad click or form instrumentation. It records route names and coarse page
timing only. Do not add field values, email addresses, tokens, or other
personal data to spans. Browser OTLP uses HTTP/protobuf; the [exporter guide](https://opentelemetry.io/docs/languages/js/exporters/)
covers browser transport constraints.

## Configure the API URL and CORS

The deployed Vue app reads `BACKEND_API_URL` from its runtime ConfigMap. This
must be the API stack's browser-accessible URL, including that stack's host
port; it is not the Vue stack's port or an in-cluster Service URL. In the Vue
stack's GitOps repository, set it in the file for each environment:

- `apps/app/overlays/staging/runtime.env`
- `apps/app/overlays/production/runtime.env`

For example, if the Vue app is at `http://staging.localhost:9080` and the
Laravel API is at `http://staging.localhost:80`, the Vue stack's staging
file should contain:

```env
BACKEND_API_URL=http://staging.localhost
```

The template default assumes the API stack uses host port `9080`. Use the
Laravel stack's actual `K3D_CLUSTER_PORT` when yours differs. The production
file works the same way, using `production.localhost`.

The Laravel API separately checks the browser's origin through
`CORS_ALLOWED_ORIGINS`. In the Laravel stack's GitOps repository, set the
matching staging or production `runtime.env` to the Vue app's exact browser
origin. For the example above, the Laravel stack's staging file should contain:

```env
CORS_ALLOWED_ORIGINS=http://staging.localhost:9080
```

Use the Vue stack's `K3D_CLUSTER_PORT`; omit the port when it is the default
HTTP port `80`. The API allows GET/POST preflight and the W3C tracing headers,
without cookies or credentials. CORS is not an authentication mechanism.

Commit and push each change to its stack's GitOps repository; Flux applies the
runtime configuration, so a CI rerun is not needed. Re-rendering templates
overwrites generated files. To preserve custom defaults across re-renders,
edit the corresponding source files under
`templates/app-vue/gitops/overlays/` or
`templates/app-laravel/gitops/overlays/` in the framework checkout as well.

These runtime settings are not secrets. Keep the actual Collector Basic Auth
credentials in Kubernetes Secrets, never in browser configuration.

## Delivery and runtime

The CI pipeline runs `npm ci` and builds the Vue bundle on pushes. A push to
`main` builds the production Node image, publishes it, and updates the staging
image digest in GitOps. The runtime container serves the Vue bundle and the
OTLP forwarding route. It also exposes `/healthz`, `/readyz`, and Prometheus
metrics on internal port `9090` for the shared application monitors.

To connect delivery, push this repository to the Gitea `__GITEA_ORG__/app`
repository, activate it in Woodpecker, and mark it trusted because the build
uses the Docker socket. Add the Flux deploy key's private key as the
`GIT_SSH_KEY` repository secret, as described in the root README. Push a commit
to `main` to publish the image and update staging.

The generated frontend image is a static UI host, not an API backend. Browser
requests go directly to the Laravel API. The Node host's only forwarding
route is for browser telemetry to the local Collector.

Like the Laravel template, this starter does not include a dependency lock
file. Creating its Dev Container runs `npm install`, which creates
`package-lock.json` in the generated app repository. Commit that file before
the first push: CI and Docker use `npm ci` and require the lockfile. The Vue
range starts at `3.5.45`; the generated lock records the exact release used.
To generate the lock manually instead, run this from the generated app
repository root before the first push:

```sh
npm install
```

## Develop in a Dev Container

Open the generated Vue app repository in VS Code with the Dev Containers
extension and choose **Reopen in Container**. The container uses Node.js 26,
runs `npm install` once after creation (creating the lock file), starts the Vite
dev server each time the container starts, and forwards port `5173`. VS Code
should open the forwarded app automatically. If it does not,
open `http://localhost:5173` or select port `5173` in the VS Code **Ports**
panel and choose **Open in Browser**. Vite output is written to
`/tmp/vite-dev-server.log` in the container.

The Vite dev server provides `/runtime-config.json` and defaults the API
origin to `http://staging.localhost:9080`. To use another browser-accessible
API origin in the Dev Container, set `VITE_BACKEND_API_URL` under
`containerEnv` in `.devcontainer/devcontainer.json`, then rebuild the
container. For a manually started Vite process, you can instead run:

```sh
VITE_BACKEND_API_URL=http://localhost:8000 npm run dev
```

For API calls from the Vite page at `http://localhost:5173`, Laravel must
allow that origin in `CORS_ALLOWED_ORIGINS`. The Dev Container is for editing
and running the UI; browser spans reach the Collector through the deployed
Node host's telemetry relay, so the full trace demo still uses the deployed
frontend and API stacks.
