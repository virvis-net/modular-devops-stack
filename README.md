# Modular DevOps Stack

Modular DevOps Stack is a local-first **skeleton for simulating a complete
DevOps system**. It provides a working example of how source control, CI,
container images, Kubernetes, GitOps delivery, ingress, and observability fit
together. Use it as a learning lab or as a starting point for replacing or
extending components — not as a production-ready, provider-independent platform.

The current example is built from Gitea, Woodpecker CI, a local Docker
registry, k3d, Flux, ingress-nginx, and a Kubernetes observability stack. The
delivery flow, described in terms of component responsibilities, is:

1. A change to the application source code triggers automated tests.
2. A change to the release branch triggers the CI system, which builds and
   publishes an application image, records its immutable digest, and updates
   the desired configuration for staging.
3. A GitOps reconciler applies that exact image digest to staging.
4. To promote a validated image, update production's desired configuration to
   use the same digest. The reconciler then applies that image to production.

The stack is intentionally small and local. The components and example app
form an end-to-end path that can be inspected, tested, and adapted.

## Prerequisites

- Docker Engine/Desktop with Docker Compose
- k3d, kubectl, Git, and OpenSSH client tools
- Python 3
- Available host ports configured by `K3D_CLUSTER_PORT` (default `80`),
  `K3D_CLUSTER_PORT_SSL` (`443`), `GITEA_SSH_PORT` (`2222`),
  `GITEA_HTTP_PORT` (`3000`), `REGISTRY_PORT` (`5000`), and
  `WOODPECKER_PORT` (`8000`)

A repository setup helper renders the app and GitOps templates using the
relevant stack, registry, Gitea SSH, and cluster settings from `.env`.

The CI agent mounts the host Docker socket so pipelines can build images. Only
activate trusted repositories whose code you control.

## Initial installation

### 1. Configure the environment and start setup

```sh
cp .env.example .env
```

Review `.env` and adjust any values as needed. Make sure the configured host
ports are available; if a port is already in use, choose a different value.
If the defaults are available, no changes are needed.

Start the setup script:

```sh
./scripts/up.sh
```

On a new installation, the script starts **only Gitea**, generates or reuses
the Flux SSH deploy key, waits for Gitea to become available, then pauses.
Leave it running while you complete the next step. The registry, CI providers,
Kubernetes cluster, and Flux are not started until the initial Gitea and
GitOps setup is verified.

### 2. Set up Gitea and the repositories

#### Gitea setup

Open Gitea at `http://localhost:<GITEA_HTTP_PORT>` (port `3000` by default)
and complete its initial configuration. You can usually keep the default
database and HTTP server settings. Docker maps the configured host HTTP port
to Gitea's internal port `3000`, and the configured SSH host port to Gitea's
internal port `22`. For working SSH clone URLs in Gitea, set its SSH domain to
`host.docker.internal` and its advertised SSH port to `GITEA_SSH_PORT`
(`2222` by default). `host.docker.internal` is useful to containers, but may
not resolve to the host from a Linux shell. For host-side cloning, use
`localhost` with the published port as shown below.

Create the initial Gitea account and set its username and password. Once
signed in, create two empty repositories named `app` and `gitops`.

In `.env`, set `GITEA_ADMIN_USER` to the account username and `GITEA_ORG` to
the user or organization that owns the repositories. By default, `GITEA_ORG`
uses the `GITEA_ADMIN_USER` value. If you create the repositories under a
different owner, update `GITEA_ORG` before rendering the templates.

Add the public key printed by `up.sh` as a **write-enabled deploy key** on the
`gitops` repository (Settings > Deploy keys). Flux bootstrap needs write access
to commit its generated sync manifests.

#### Clone repositories

Use the ignored `workspace/` directory for local clones. The default render
needs both repositories cloned. If you render only one repository, clone only
that one; use `--app-only` or `--gitops-only` as described below. From the
project root, load the environment variables and clone the repositories you
need.

```sh
source .env
git clone "http://localhost:${GITEA_HTTP_PORT}/${GITEA_ORG}/app.git" workspace/app
git clone "http://localhost:${GITEA_HTTP_PORT}/${GITEA_ORG}/gitops.git" workspace/gitops
./scripts/copy-templates.sh
```

Or if you want to use SSH:

```sh
source .env
git clone "ssh://git@localhost:${GITEA_SSH_PORT}/${GITEA_ORG}/app.git" workspace/app
git clone "ssh://git@localhost:${GITEA_SSH_PORT}/${GITEA_ORG}/gitops.git" workspace/gitops
./scripts/copy-templates.sh
```

The commands above are for a host terminal, where the published Gitea port is
available on `localhost`. Inside an app Dev Container, `localhost` refers to
that container. The Go, Laravel, and Vue Dev Container configurations map
`host.docker.internal` to the Docker host gateway and automatically rewrite
SSH Git URLs from `localhost` to that hostname. They also retain `localhost`
as the repository's SSH host-key alias, so a key accepted during the host-side
clone can be used inside the container. Post-create also configures the Git
repository and fails if the workspace isn't a Git repository. The Go and
Laravel containers mark only their mounted workspace as safe for Git, because
they run as root while bind-mounted files may belong to a different host user.
This works without changing the repository's remote URL. If the app repository
was rendered before these settings were added, update its `.devcontainer`
configuration and rebuild the Dev Container.

Choose the application template when rendering the repositories. The Go
template is selected by default:

```sh
./scripts/copy-templates.sh
```

To select the Laravel template, pass `laravel`:

```sh
./scripts/copy-templates.sh laravel
```

To select the Vue frontend template, pass `vue`:

```sh
./scripts/copy-templates.sh vue
```

By default, the helper renders both `workspace/app` and `workspace/gitops`.
To render only the application repository, add `--app-only`:

```sh
./scripts/copy-templates.sh vue --app-only
```

To render only the GitOps repository, add `--gitops-only`. The app template
still selects the app-specific GitOps manifests and dashboard:

```sh
./scripts/copy-templates.sh laravel --gitops-only
```

For an initial render, each selected destination must be an empty Git clone.
App-only rendering needs only `workspace/app`; GitOps-only rendering needs
only `workspace/gitops`.

To apply changed `.env` values after a repo has already been rendered, use a
single-target mode on that existing clone. For example, to refresh GitOps:

```sh
git -C workspace/gitops pull --ff-only
./scripts/copy-templates.sh vue --gitops-only
git -C workspace/gitops diff
```

The existing repo must be clean, with no staged, unstaged, or untracked
changes. Rendering overwrites files generated by the selected template, so
review the diff before committing and pushing. The default both-repo mode
continues to require empty clones. Re-render with the same app template; the
renderer does not delete files left by an earlier template.

The Go template uses Go 1.22 as a simple single-stack service. The Laravel
template uses Laravel 13 and PHP 8.5, with MariaDB 13.0 and Redis 8.10 for its
app dependencies. The Vue template uses Vue 3 and Node 26 to build a browser
funnel UI; it is intended for a frontend stack that potentially calls an API in
another stack. Each option is rendered into the `app` repository and uses the
stack's shared GitOps delivery flow, technology-agnostic application
dashboard, and its runtime dashboard. Cluster, ingress, and infrastructure
monitoring are shared.
The app repositories include VS Code Dev Containers; open `workspace/app` in
VS Code and choose **Dev Containers: Reopen in Container** to run the app
locally. The Laravel template also starts local MariaDB and Redis services
for its development dependencies. Each app's Compose project and network is
separate from the stack's infrastructure.

The helper reads `.env` and renders the values needed by the selected target.
GitOps rendering also renames the cluster directory to match
`K3D_CLUSTER_NAME`. For initial setup, create each selected destination as an
empty repository without autogenerated files.

Application templates can provide GitOps-specific resources and workload
configuration in their `gitops/` directory. The renderer copies that directory
into `apps/app/base/app-template/` in the generated GitOps repository, separate
from the app source repository. It is a Kustomize Component: use its resources
for optional services, and patches for environment variables or other
implementation-specific pod settings. This keeps new app options from
requiring implementation-specific logic in the renderer.

Commit and push the rendered GitOps files. Git may ask for your Gitea
credentials:

```sh
git -C workspace/gitops add .
git -C workspace/gitops -c user.name="Your Name" -c user.email="you@example.com" \
  commit -m "Add cluster desired state"
git -C workspace/gitops push -u origin HEAD:main
```

#### Configure Woodpecker OAuth

In Gitea, create an OAuth2 application for Woodpecker (Profile menu >
Settings > Applications > Create a new OAuth2 Application). Use these
callback URLs, replacing `<WOODPECKER_PORT>` with the value configured in
`.env` (default `8000`):

```text
http://localhost:<WOODPECKER_PORT>/authorize
http://host.docker.internal:<WOODPECKER_PORT>/authorize
http://ci-server:8000/authorize
```

The `ci-server:8000` URL uses Woodpecker's fixed internal container port; it
does not change when you change the host port.

Copy the generated client ID and secret into `GITEA_CLIENT` and `GITEA_SECRET`
in `.env`. Make sure `GITEA_ADMIN_USER` is set to the username you used when
setting up Gitea, so Woodpecker grants that account server-admin privileges.

Optionally add your personal SSH key to Gitea so you won't be asked for the
username and password when you push or pull the repos.

Return to the waiting terminal and press Enter. The script reloads `.env` and
checks that the OAuth settings are configured and the GitOps branch is
accessible with the Flux deploy key. If you stopped the script instead,
rerun `./scripts/up.sh` to resume; it will repeat the setup checks without
restarting the installation from scratch. With the default storage settings,
the first run creates fresh named volumes.

After the script completes, check the Gitea commit history: Flux has pushed
the bootstrap manifests to the configured cluster path using the deploy key
you added.

Now all you need to do is connect CI and Source Control and you're good to go.

### 3. Enable the CI workflow

Open `http://localhost:<WOODPECKER_PORT>/login` (default port `8000`), sign
in through Gitea, authorise the application, and add the `<GITEA_ORG>/app`
repository in Woodpecker (+ / Add repository > Enable). In the repository
settings, enable **Volumes** under **Trusted**. The example pipeline requires
trusted volumes for its Docker socket mount.

> The Trusted option is only shown to Woodpecker server admins. If it is missing,
> confirm that `GITEA_ADMIN_USER` in `.env` exactly matches the signed-in Gitea
> username, then restart the stack with `./scripts/up.sh` and reload the
> settings page.

In the same repository settings, open the Secrets tab and add the contents of
the Flux private key file (by default `stack/.state/ssh/flux_deploy_key`) as a
repository secret named `GIT_SSH_KEY`. If `FLUX_PRIVATE_KEY` is set in `.env`,
use the file at that path instead. Keep the private key secret; do not commit
it to either repository.

> The setup script sets the key's permissions to `0644` so the Flux bootstrap
> container can read it. Other users on the host can also read it, so use this
> setup only on a trusted machine and do not reuse the key for unrelated access.

### 4. Prepare secrets and verify the end-to-end flow

If you selected the Laravel template, create its `app-database` Secret after
Flux has created the `staging` namespace and before proceeding with the app
release. From the framework checkout, the helper can generate it without
putting credentials in Git. First run `kubectl config get-contexts`, then
replace `k3d-your-cluster` below with the context for this stack:

```sh
./scripts/setup-stack-secrets.sh --database-only \
  --database-context k3d-your-cluster
```

The namespace defaults to `staging`. Create the production Secret only after
the production namespace exists, adding
`--database-namespace production`. The helper preserves an existing database
Secret; if one is missing while a MariaDB PVC exists, it asks before creating
new credentials. The Laravel template README also documents manual secret
creation and database access.

For cross-stack Collector authentication, set the `OTEL_CENTRAL_*` values in
each stack's `.env` before rendering its GitOps repository. Once Flux has
created the central ingest Ingress and the Collector Deployments, run the
helper once with contexts from `kubectl config get-contexts`. Replace only the
sample context values; keep the option names as shown:

```sh
./scripts/setup-stack-secrets.sh \
  --central-context k3d-your-central-cluster \
  --forwarder-context k3d-your-forwarder-cluster \
  --collector-scheme http \
  --central-port 80 \
  --collector-only
```

Use the central stack's actual published port for both `--central-port` and
`OTEL_CENTRAL_COLLECTOR_ENDPOINT`. Add a `--forwarder-context` for each
application stack sending telemetry. For one Laravel forwarder, omit
`--collector-only` to also create its staging database Secret; with multiple
forwarders, pass `--database-context` for each Laravel stack that needs one.
Use `--database-only` when setting up database credentials without Collector
authentication. The helper uses temporary containers for `htpasswd` and
mkcert, so neither utility needs to be installed on the host. HTTP matches the
`.env.example` endpoint and sends credentials and telemetry without encryption,
so use it only on a trusted local network. HTTPS is an alternative; change the
endpoint and `--collector-scheme` to `https` and use the central HTTPS port.

This helper manages Kubernetes Secrets and restarts forwarding Collectors so
they reload client auth; it does not edit GitOps. See the [Collector setup
guide](stack/monitoring/provider/kubernetes/README.md) for the per-stack
settings, multi-stack flow, and manual commands. Re-render and push changed
GitOps settings separately. The central receiver Secret is updated on each
run: enter the existing shared forwarder password to keep
other clients working, or choose a new password and update every forwarder's
client Secret. After deleting and recreating a k3d cluster, local-path data
may remain in the Docker storage volume but its Kubernetes PVC metadata is not
restored automatically.

Push the rendered app repository to start the end-to-end delivery flow:

```sh
git -C workspace/app add .
git -C workspace/app -c user.name="Your Name" -c user.email="you@example.com" \
  commit -m "Add example app"
git -C workspace/app push -u origin HEAD:main
```

The push triggers the CI pipeline, which runs the tests and, on `main`, builds
and pushes the image to the registry. The pipeline records the new image
digest in GitOps, and Flux deploys it to the staging environment.

In Woodpecker confirm that the test step passes. Since the push was to `main`,
Woodpecker also builds and pushes the image, then updates the staging digest
in GitOps. Check Gitea to see a commit with a message similar to
`ci: deploy app digest sha256:... to staging`.

Flux should now deploy that revision to the `staging` namespace. You can check
Flux and staging with:

```sh
kubectl get kustomization flux-system -n flux-system
kubectl get pods,services,ingress -n staging
```

When the staging pod is ready, open
`http://staging.localhost:<K3D_CLUSTER_PORT>/` (default port `80`). The sample
app should display its greeting.

After Flux reconciles the monitoring resources, generate some app traffic and
open Grafana at `http://monitoring.localhost:<K3D_CLUSTER_PORT>/`. Prometheus
scrapes every 15 seconds; the request-rate and latency panels need traffic to
show meaningful values.

Finally, open Mailpit at `http://notifications.localhost:<K3D_CLUSTER_PORT>/`.
On a fresh install, expect to see 'FIRING' notifications followed by their
corresponding 'RESOLVED' notifications. These startup alerts are reassuring:
they show that Prometheus detected temporary conditions while services were
starting, and that Alertmanager delivered both the alert and its resolution
to Mailpit. If an alert remains firing after startup, investigate it.

## Normal usage

After installation, push app changes to a branch to run tests. Push or merge
to `main` to build and publish an image and update the staging digest. Check
the Woodpecker pipeline and wait for Flux to deploy the image before testing
the staging app. Generate traffic to populate the metrics dashboard and use
Grafana Explore to inspect logs, traces, and Kubernetes events.

> Grafana dashboards are available without signing in. To use Explore, sign
> in with the default username and password (`admin` / `admin`). Grafana may
> ask you to change the password on first login.

#### Release to production

Production is opt-in and is not reconciled until enabled in GitOps. To promote
the tested staging image:

1. In `workspace/gitops`, pull the latest `main`.
2. Copy the complete `digest: sha256:...` value from
   `apps/app/overlays/staging/kustomization.yaml` into the `images` section of
   `apps/app/overlays/production/kustomization.yaml`, replacing its initial
   `newTag: "latest"` entry with `digest`.
   If you selected Laravel, follow its README to prepare the production
   namespace and `app-database` Secret, then set the migration image digest,
   release-specific Job suffix, and Flux dependency before enabling production.
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

Staging and production each run in a separate Kubernetes namespace, with
their own app Deployments, Services, Ingresses, and configuration. The Laravel
template also provisions a MariaDB database and Redis cache independently in
each environment; its application README describes the required Kubernetes
Secret setup and database migration. It also deploys a separate Redis-backed
queue worker, configured through the template's GitOps component. Other app
templates can add environment-specific dependencies and workloads the same
way. In Kubernetes, a PersistentVolumeClaim (PVC) is a request for storage
that a workload can use; stateful services should have a separate claim for
each environment. The environments still share one local k3d cluster and
host, so namespaces provide logical separation, not a strong security
boundary. Use separate clusters where stronger isolation is required.

#### Shutting down the stack

To stop the lab, run `./scripts/down.sh`. This deletes the k3d cluster and
stops the Compose providers. Gitea, Woodpecker, and registry data live in
Docker-managed named volumes, which `down.sh` leaves intact. Running
`./scripts/up.sh` starts the providers again with their existing volume data.
The volumes are named `<STACK_NAME>-gitea-data`, `<STACK_NAME>-woodpecker-data`,
and `<STACK_NAME>-registry-data` (with `mds` as the default stack name).
Remove them explicitly with `docker volume rm` only if you intend to delete
that provider's data. k3d local-path storage uses one Docker named volume,
`<K3D_CLUSTER_NAME>-storage`, mounted on every cluster node. It remains after
cluster deletion, but a deleted cluster's Kubernetes metadata is not restored
when creating a new cluster. Remove it explicitly with `docker volume rm` only
if you intend to delete its contents.

The Compose files show a commented bind-mount alternative for each provider.
k3d's `cluster.yaml` also includes a commented host-folder alternative. To make
data visible in the repository, replace the named-volume entry with the
corresponding bind-mount entry. Each storage option has its own data; changing
between them does not copy or migrate existing data.

## Sharing providers across stacks

Each checkout starts its own Gitea, Woodpecker, and registry by default. To use
one set of these services for multiple stacks, choose one checkout to own them
and configure the other checkout(s) as clients:

1. In every checkout, use a unique `STACK_NAME` and `K3D_CLUSTER_NAME`, but set
   `NETWORK_NAME` to the same Docker network name. The provider-owning checkout
   keeps `START_LOCAL_PROVIDERS=true`; set it to `false` in each client.
2. Set `GITEA_HTTP_PORT`, `GITEA_SSH_PORT`, `WOODPECKER_PORT`, and
   `REGISTRY_PORT` to the provider owner's port values in every checkout.
   Only the owner publishes those ports; clients use them to reach the shared
   services. Keep each cluster's ingress ports unique.
3. Start the owner and complete its normal Gitea, Woodpecker OAuth, and
   registry setup first. In the shared Gitea instance, create a distinct
   organization for each stack, with `app` and `gitops` repositories in each.
   Set each checkout's `GITEA_ORG` and `GITOPS_REPO_URL` to its own
   organization and GitOps repository, add that stack's Flux deploy key to
   that repository, and activate each app repository in Woodpecker.
4. Start each client checkout. Its setup waits for the owner's Gitea and
   bootstraps that cluster's Flux against the shared Docker network. The shared
   registry receives the sample pipelines' `app` images, tagged by commit SHA;
   each stack's GitOps repository is updated independently.

The shared Docker network lets both k3d clusters reach Gitea and the registry
directly. Keep the provider owner running while client clusters use it. Run
`down.sh` for clients before shutting down the owner; client shutdown leaves
the shared providers and network alone. If other containers remain attached,
the owner's shutdown also leaves the network in place. This shared network and
the Woodpecker agent's Docker socket are appropriate only for this trusted
local lab.

## Observability

The Kubernetes monitoring provider deploys Prometheus, Grafana, Loki, Tempo,
an OpenTelemetry Collector, kube-state-metrics, a Kubernetes event exporter,
Alertmanager, and Mailpit. The server templates expose `/healthz` and `/readyz`
for Kubernetes probes, export request and runtime metrics, and send traces over
OTLP. The Go and Laravel templates also export logs written by the application;
the Laravel starter writes a fixed info log for each successful `/api/hello`
request. Prometheus collects app, cluster, node, ingress, and Collector
metrics; emitted app logs and Kubernetes events go to Loki, while traces go to
Tempo. Grafana connects these signals so requests can be investigated across
metrics, logs, and traces. The Vue template adds browser spans through its
local Collector and can be paired with a Laravel API in another stack.

After rendering the provider into GitOps and allowing Flux to reconcile:

- Open the provisioned dashboards and Explore at
  `http://monitoring.localhost:<K3D_CLUSTER_PORT>/`.
- Open the local alert notification inbox at
  `http://notifications.localhost:<K3D_CLUSTER_PORT>/`.
- Use Grafana Explore with Loki query
  `{service_name="app"} | trace_id != ""` for app request logs, or
  `{job="kubernetes-events"}` for Kubernetes events. Follow trace links to
  Tempo and metric exemplars back to traces.
- Prometheus remains internal. To inspect its alert rules or query metrics,
  forward its Service with
  `kubectl port-forward -n monitoring service/prometheus 9090:9090`, then open
  `http://localhost:9090/alerts`.

Prometheus alerts on scrape targets remaining down, elevated app 5xx rates,
image-pull failures, and crash loops. Alertmanager sends firing and resolved
notifications to the local Mailpit inbox. The [monitoring provider
documentation](stack/monitoring/provider/kubernetes/README.md) includes alert
testing steps, Loki queries, retention, storage, and configuration details.

This single-replica local setup is intended for a trusted development
environment, not production. Grafana dashboards are viewable without signing
in, but Explore requires a login; the Mailpit inbox has no authentication.
Loki and Tempo use local PVCs with finite retention, and those volumes are not
backups. Prometheus data uses ephemeral pod storage.

## Guided exercises (optional)

Try these after the initial installation to follow a request through the
stack, see alerting in action, and practice promoting an image.

### Trace a request

Generate a few requests to staging:

```sh
source .env
for i in 1 2 3 4 5; do
  curl -sS -o /dev/null "http://staging.localhost:${K3D_CLUSTER_PORT}/"
done
```

In Grafana, sign in and open Explore. Select Loki and run
`{service_name="app"} | trace_id != ""`. With the Go template, open a result
and follow its trace link to Tempo. The Laravel `/api/hello` route also writes
a correlated info log, which you can open and follow to its trace.

### Trace a frontend-to-backend request across two stacks

Run the [cross-stack frontend/backend exercise](stack/monitoring/provider/kubernetes/README.md#cross-stack-frontend-backend-exercise)
to connect a Vue frontend in one local k3d stack directly to a Laravel API in
another, then inspect their combined trace and any correlated logs in the
frontend stack's Grafana, which acts as the central receiver.

### Trigger and resolve an alert

Create a temporary staging pod with an invalid image:

```sh
kubectl run observability-alert-test -n staging \
  --image=example.invalid/observability-alert-test:missing --restart=Never
```

After the pod has been unable to pull its image for at least two minutes,
check Prometheus at `http://localhost:9090/alerts` (use the
`kubectl port-forward` command in the Observability section) and look for the
`KubernetesPodImagePullBackOff` alert. Check Mailpit for the firing
notification. Then remove the test pod:

```sh
kubectl delete pod observability-alert-test -n staging
```

After Prometheus observes that the condition has cleared, check Mailpit for
the resolved notification. The [monitoring provider
guide](stack/monitoring/provider/kubernetes/README.md) has more detail on this
exercise and the related Kubernetes events.

### Promote an image by digest

Follow the [Release to production](#release-to-production) steps to promote
the staging image. Compare the staging and production `digest` values and
confirm that production uses the already-tested image rather than rebuilding
it.

## Restarting after a host or Docker restart

Run `./scripts/up.sh` to resume the stack. It starts the Compose providers,
starts the existing k3d cluster if needed, selects its kubectl context, and
waits for all cluster nodes to become Ready before applying ingress and
bootstrapping Flux.

## Troubleshooting commands

These checks are optional during a clean install, but can help diagnose common
local setup problems. Run commands from the repository root.

### Remove a stale Gitea SSH host key

If Git reports that the Gitea host key has changed, remove only the known-host
entry for the hostname and port used by this stack, then retry the Git
operation. OpenSSH stores nonstandard ports in `[hostname]:port` form:

```sh
source .env
ssh-keygen -R "[$GITEA_SSH_DOMAIN]:$GITEA_SSH_PORT"
ssh-keygen -R "[localhost]:$GITEA_SSH_PORT"
```

The first command covers the configured Gitea SSH domain (the default is
`host.docker.internal`); the second covers clones made through `localhost`.
For port `22`, OpenSSH may store the hostname without a port, so remove those
entries with `ssh-keygen -R "$GITEA_SSH_DOMAIN"` and `ssh-keygen -R localhost`
instead. These commands affect your user-level `~/.ssh/known_hosts`; Flux uses
its own file at `stack/.state/ssh/known_hosts.flux`.
When Git reconnects, verify the newly presented host fingerprint before
accepting it; do not disable SSH host-key checking.

### Check provider availability and logs

Check whether the configured Gitea SSH port is accepting connections:

```sh
source .env
nc -vz localhost "$GITEA_SSH_PORT"
```

Inspect provider status and recent logs if Gitea or CI does not start. For
shared providers, run these commands from the provider-owning checkout:

```sh
source .env
docker compose -p "${STACK_NAME}-providers" \
  -f stack/docker-compose.yaml \
  -f stack/registry/provider/local/docker-compose.yaml \
  -f stack/source-control/provider/gitea/docker-compose.yaml \
  -f stack/ci/provider/woodpecker/docker-compose.yaml \
  ps
docker compose -p "${STACK_NAME}-providers" \
  -f stack/docker-compose.yaml \
  -f stack/registry/provider/local/docker-compose.yaml \
  -f stack/source-control/provider/gitea/docker-compose.yaml \
  -f stack/ci/provider/woodpecker/docker-compose.yaml \
  logs --tail=100 scm ci-server registry
```

To confirm Gitea is responding over HTTP:

```sh
source .env
curl --fail --show-error "http://localhost:${GITEA_HTTP_PORT}/"
```

After correcting configuration or starting a stopped provider, rerun
`./scripts/up.sh`.

## Extendability

The framework is organised around providers so infrastructure implementations
can be replaced or added as the lab grows. The current template-rendering
workflow includes the example app, GitOps repository, and Kubernetes
observability manifests. Edit the source templates and provider manifests in
this repository, then render them into the Gitea repositories; Flux applies
the rendered Kubernetes state from GitOps.

Useful extension points include:

- Add app dependencies such as a database or cache, with separate resources
  and configuration for staging and production.
- Add CI steps, deployment environments, or approval gates to the example
  pipeline and GitOps flow.
- Add or replace infrastructure providers and their configuration while
  preserving the end-to-end workflow.
- Extend dashboards, telemetry, event collection, and alert rules for the
  services added to the lab.

Before using the stack beyond a trusted local lab, define provider-selection
interfaces and review authentication, network exposure, availability, and
persistent storage. Add backup and migration procedures for any data that
must survive container or cluster recreation.

## Planned improvements

- Define provider interfaces and configuration so components can be selected
  or replaced without rewriting the end-to-end workflow.
- Define a durable, portable backup and restore workflow for the Compose
  provider volumes and k3d cluster storage.
- Consider running the Python-based setup and Kubernetes helper scripts in a
  container, removing the host Python 3 prerequisite while accounting for the
  additional image, bind mounts, and generated-file ownership.

## Project layout

- `stack/` — runtime components and shared Docker Compose network configuration
  - `stack/source-control/provider/gitea/` — Gitea
  - `stack/ci/provider/woodpecker/` — Woodpecker server and agent
  - `stack/registry/provider/local/` — local container registry
  - `stack/cluster/provider/k3d/` — k3d cluster and registry configuration
  - `stack/ingress/provider/nginx/` — ingress-nginx install, readiness, and teardown
  - `stack/gitops/provider/flux/` — Flux bootstrap and teardown
  - `stack/monitoring/provider/kubernetes/` — observability provider configuration
    and manifests, rendered into GitOps for Flux to apply
- `scripts/copy-templates.sh` — render app and/or GitOps templates from `.env`
  into empty initial clones or clean existing clones for a single-target refresh
- `templates/app-go/`, `templates/app-laravel/`, and `templates/app-vue/` —
  application templates
- `templates/gitops/` — GitOps repository template rendered into Gitea
