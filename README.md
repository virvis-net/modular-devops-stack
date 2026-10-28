# Modular DevOps Stack

A local-first lab and demo for learning how source control, CI, container
registries, Kubernetes, and GitOps fit together. The current working path uses
Gitea, Woodpecker CI, a local Docker registry, k3d, Flux, and ingress-nginx.

The example delivery flow is:

1. Every push to the app repository runs the Go test suite.
2. A push to `main` builds and publishes the app image once, identified by its
   registry digest, then updates the staging GitOps configuration.
3. Flux deploys that digest to the staging namespace.
4. A GitOps change promotes the same digest to production (optionally through
   a pull request for review).
5. Flux deploys it to the separate production namespace.

## Application health checks

The sample app exposes `/healthz` for liveness and `/readyz` for readiness.
Both staging and production Deployments use these endpoints as Kubernetes
probes. They currently return healthy whenever the HTTP server is responding;
the readiness check can be extended to verify dependencies if the app gains
any.

## Application metrics

The example app exposes request counters and request-duration histograms in
Prometheus text format on its internal `9090` metrics port. Prometheus
discovers app Services in the staging and production namespaces; Grafana
provides a provisioned dashboard for request rate, status, p95 latency, and
selected Go runtime metrics.
Access the local dashboard at
`http://monitoring.localhost:<K3D_CLUSTER_PORT>` (port `80` by default).
Grafana is routed through ingress-nginx; Prometheus remains an internal
ClusterIP Service. Grafana allows anonymous read-only access for this local
demo, so do not expose this ingress outside a trusted local environment.
Prometheus stores its seven-day retention window on ephemeral pod storage, so
its metrics history is lost if the pod is recreated. This increment covers
application, Kubernetes object-state, and ingress metrics; database and cache
telemetry remain future work.
The app also exports selected Go runtime metrics (goroutines, heap and stack
memory, and garbage-collection cycles), which appear on the Grafana dashboard.

The sample Go app emits Prometheus metrics directly to keep this first step
small. A later OpenTelemetry Collector integration can provide a more
backend-independent telemetry path for other application stacks.

This is a learning and proof-of-concept project, not a production-ready or
provider-independent platform. Some local Docker, host networking, and
single-user lab assumptions are intentional.

## Prerequisites

- Docker Engine/Desktop with Docker Compose
- k3d, kubectl, Git, and OpenSSH client tools
- Python 3
- Available host ports configured by `K3D_CLUSTER_PORT` (default `80`),
  `K3D_CLUSTER_PORT_SSL` (`443`), `GITEA_SSH_PORT` (`2222`),
  `GITEA_HTTP_PORT` (`3000`), `REGISTRY_PORT` (`5000`), and
  `WOODPECKER_PORT` (`8000`)
- A Gitea account with permission to create repositories and deploy keys

The repository setup helper renders the app and GitOps templates using the
relevant stack, registry, Gitea SSH, and cluster settings from `.env`.

The CI agent mounts the host Docker socket so pipelines can build images. Only
activate trusted repositories whose code you control.

## Setup

### 1. Configure and start the stack

```sh
cp .env.example .env
```

Review `.env` and adjust the values for your environment. Start the providers
and cluster:

Set `GITEA_ADMIN_USER` to the username you will create in Gitea. The example
configuration uses that value for `WOODPECKER_ADMIN`, granting the matching
Gitea account Woodpecker server-admin privileges. This does not create a Gitea
user; create the account during Gitea's initial setup, using the same username.

```sh
./scripts/up.sh
```

On first start, the script may pause after generating a Flux SSH deploy key.
Leave it waiting while you complete the Gitea and GitOps setup below.
If it does not pause (for example, if the key already exists), finish Gitea
and repository setup, then rerun `./scripts/up.sh` if Flux bootstrap did not
complete.

### 2. Set up Gitea and the repositories

Open Gitea at `http://localhost:<GITEA_HTTP_PORT>` (port `3000` by default),
complete its initial setup, and create an organization matching `STACK_NAME`
(`mds` by default) with two empty repositories named `app` and `gitops`.

Use the ignored `workspace/` directory for local clones; these working copies
will not be added to the Modular DevOps Stack repository. From the project
root, source the environment, clone both repositories, then run the helper to
copy and render the templates:

```sh
source .env
git clone "http://localhost:${GITEA_HTTP_PORT}/${STACK_NAME}/app.git" workspace/app
git clone "http://localhost:${GITEA_HTTP_PORT}/${STACK_NAME}/gitops.git" workspace/gitops
./scripts/copy-templates.sh
```

The helper reads `.env`, renders the registry port, GitOps SSH URL, stack name,
and cluster name/port into the templates, and renames the GitOps cluster
directory to match `K3D_CLUSTER_NAME`. It requires both clones to be empty
repositories; create them without autogenerated files.

Commit and push the rendered templates:

```sh
git -C workspace/app add .
git -C workspace/app -c user.name="Your Name" -c user.email="you@example.com" \
  commit -m "Add example app"
git -C workspace/app push -u origin HEAD:main

git -C workspace/gitops add .
git -C workspace/gitops -c user.name="Your Name" -c user.email="you@example.com" \
  commit -m "Add cluster desired state"
git -C workspace/gitops push -u origin HEAD:main
```

Add the Flux public key printed by `up.sh` as a **write-enabled deploy key** on
the `gitops` repository. Flux bootstrap needs write access to commit its
generated sync manifests. Once the key and repositories are ready, return to
the waiting terminal and press Enter.

### 3. Configure Woodpecker OAuth

In Gitea, create an OAuth2 application for Woodpecker. Use these callback URLs,
replacing `<WOODPECKER_PORT>` with the value configured in `.env` (default
`8000`):

```text
http://localhost:<WOODPECKER_PORT>/authorize
http://host.docker.internal:<WOODPECKER_PORT>/authorize
http://ci-server:8000/authorize
```

The `ci-server:8000` URL uses Woodpecker's fixed internal container port; it
does not change when you change the host port.

Copy the generated client ID and secret into `GITEA_CLIENT` and `GITEA_SECRET`
in `.env`, then rerun:

```sh
./scripts/up.sh
```

This updates the running Woodpecker configuration and reruns the idempotent
cluster/bootstrap steps.

### 4. Enable the CI workflow

Open `http://localhost:<WOODPECKER_PORT>/login` (default port `8000`), sign in
through Gitea, and activate the `mds/app` repository in Woodpecker. In the
repository settings, ensure push events are enabled. The test step runs for
pushes to every branch; only pushes to `main` build and publish an image and
update staging. The example pipeline requires trusted volumes for its Docker
socket mount.
The Trusted option is only shown to Woodpecker server admins. If it is missing,
confirm that `GITEA_ADMIN_USER` in `.env` exactly matches the signed-in Gitea
username, then rerun `./scripts/up.sh` and reload the settings page.

The Flux deploy key was created in step 1 and its public key was added to the
GitOps repository in step 2. In the Woodpecker `app` repository settings, add
the contents of the matching private key file (by default
`~/.ssh/flux_deploy_key`) as a repository secret named `GIT_SSH_KEY`. If
`FLUX_PRIVATE_KEY` is set in your environment, use the file at that path
instead. Keep the private key secret; do not commit it to either repository.

### 5. Verify the end-to-end flow

Push an app change to any branch and confirm that the Woodpecker test step
passes. When a change is pushed to `main`, Woodpecker should also build and
push the image, then update the staging digest in GitOps. Flux should deploy
that revision to the `staging` namespace. Check Flux and staging with:

```sh
kubectl get kustomization flux-system -n flux-system
kubectl get pods,services,ingress -n staging
```

When the staging Pod is Ready, open
`http://staging.localhost:<K3D_CLUSTER_PORT>/` (default port `80`). The sample
app should display its greeting.

After Flux reconciles the monitoring resources, generate some app traffic and
open `http://monitoring.localhost:<K3D_CLUSTER_PORT>`. Prometheus scrapes every
15 seconds; the request-rate and latency panels need traffic to show meaningful
values.

### 6. Promote the tested image to production

Production is not reconciled until it is explicitly enabled in GitOps. To
promote the staging image:

1. In `workspace/gitops`, pull the latest `main`.
2. Copy the complete `digest: sha256:...` value from
   `apps/app/overlays/staging/kustomization.yaml` into the `images` section of
   `apps/app/overlays/production/kustomization.yaml`, replacing its initial
   `newTag: "latest"` entry with `digest`.
3. Add `- environments/production` to the `resources` list in
   `clusters/${K3D_CLUSTER_NAME}/kustomization.yaml`.
4. Confirm that the staging and production overlays specify the same digest,
   then commit and push the changes to GitOps `main`. Flux will deploy the
   already-tested image to the `production` namespace; no image rebuild occurs.

For an additional review or approval gate, make these changes on a separate
branch and open a pull request to `main` instead. Flux deploys the image after
the promotion reaches `main`.

After reconciliation, verify production with
`kubectl get pods,services,ingress -n production` and open
`http://production.localhost:<K3D_CLUSTER_PORT>/`.

The two environments have separate namespaces, app Deployments, Services,
Ingresses, and Kubernetes namespaced configuration. Future databases, caches,
Secrets, and persistent volume claims should be instantiated independently
under each environment. Both environments still share one local k3d cluster
and host, so namespaces provide logical separation, not a strong security
boundary. Use separate clusters where stronger isolation is required.

To stop the lab, run `./scripts/down.sh`. This deletes the k3d cluster and
stops the providers; source data is stored in the provider `data/` directories.

## Project layout

- `source-control/provider/gitea/` — Gitea
- `ci/provider/woodpecker/` — Woodpecker server and agent
- `registry/provider/local/` — local container registry
- `cluster/provider/k3d/` — k3d cluster and registry configuration
- `ingress/provider/nginx/` — ingress-nginx install, readiness, and teardown
- `gitops/provider/flux/` — Flux bootstrap and teardown
- `monitoring/provider/kubernetes/` — Kubernetes observability provider
  configuration and manifests, rendered into GitOps for Flux to apply
- `scripts/copy-templates.sh` — render templates from `.env` into empty Gitea
  clones
- `templates/app/` and `templates/gitops/` — example repositories to copy into
  Gitea

## Observability

The Kubernetes monitoring provider deploys Prometheus, Grafana, Loki, Tempo,
an OpenTelemetry Collector, and supporting event and alert services. The
example app exports request metrics, structured logs, and traces over OTLP.
Prometheus collects app, cluster, node, ingress, and Collector metrics;
Kubernetes events and app logs are stored in Loki, while traces are stored in
Tempo. Grafana connects these signals so requests can be investigated across
metrics, logs, and traces.

After rendering the provider into GitOps and allowing Flux to reconcile:

- Open the provisioned dashboards and Explore at
  `http://monitoring.localhost:<K3D_CLUSTER_PORT>/`.
- Open the local alert notification inbox at
  `http://notifications.localhost:<K3D_CLUSTER_PORT>/`.
- Use Grafana Explore with Loki query
  `{service_name="example-app"} | trace_id != ""` for app request logs, or
  `{job="kubernetes-events"}` for Kubernetes events. Follow trace links to
  Tempo and metric exemplars back to traces.
- Prometheus remains internal. To inspect its alert rules or query metrics,
  forward its Service with
  `kubectl port-forward -n monitoring service/prometheus 9090:9090`, then open
  `http://localhost:9090/alerts`.

The provider README documents alert testing, retention, storage, and
configuration details: [Kubernetes monitoring provider](monitoring/provider/kubernetes/README.md).
This single-replica local setup is intended for a trusted development
environment, not production. Grafana and the notification inbox have no login;
Loki and Tempo use local PVCs with finite retention, and those volumes are not
backups.

## Next steps

- Define clear provider interfaces and configuration so components can be
  selected or replaced without rewriting the end-to-end workflow.
- Review persistent storage across Docker Compose providers and use named
  Docker volumes where appropriate, with documented backup and migration
  steps. Keep ephemeral container data separate from state that must survive
  container recreation.
