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

The core steps below install one stack with the default Go app template and
default port values. Leave other optional settings unchanged unless a note
specifically asks you to configure them. Alternative app templates,
single-repository rendering, Laravel secrets, and multi-stack telemetry are
marked **Optional** and are not needed for this installation.

### 1. Configure the environment and start setup

```sh
cp .env.example .env
```

In `.env`, set `GITEA_ADMIN_USER` to the username you intend to create in
Gitea. The default `GITEA_ORG` follows this value, so no other account setting
needs to change when the repositories belong to that user. Keep the default
ports if they are available; change only a port that conflicts with another
service on your host.

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
and complete its initial configuration, keeping the default database and HTTP
server settings. Set the advertised SSH domain to `host.docker.internal` and
SSH port to `2222` (or your configured `GITEA_SSH_PORT`); Flux uses this
address from inside the Docker network.

Create the initial Gitea account and set its username and password. Once
signed in, create two empty repositories named `app` and `gitops`.

Add the public key printed by `up.sh` as a **write-enabled deploy key** on the
`gitops` repository (Settings > Deploy keys). Flux bootstrap needs write access
to commit its generated sync manifests.

> **Optional:** The default `GITEA_ORG` is the Gitea account named by
> `GITEA_ADMIN_USER`. If you create the repositories under a different user or
> organization, set `GITEA_ORG` to that owner in `.env` before rendering.

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

The single `copy-templates.sh` command selects the default Go template and
renders both repositories.

#### Optional: use SSH for host-side clones

Use these clone commands instead if you prefer SSH:

```sh
source .env
git clone "ssh://git@localhost:${GITEA_SSH_PORT}/${GITEA_ORG}/app.git" workspace/app
git clone "ssh://git@localhost:${GITEA_SSH_PORT}/${GITEA_ORG}/gitops.git" workspace/gitops
./scripts/copy-templates.sh
```

The commands above are for a host terminal, where the published Gitea port is
available on `localhost`.

#### Optional: use another app template or render one repository

The Go template is the default. Choose either Laravel or Vue by passing its
name:

```sh
# Laravel
./scripts/copy-templates.sh laravel

# Vue
./scripts/copy-templates.sh vue
```

The Go, Laravel, and Vue Dev Container configurations map
`host.docker.internal` to the Docker host gateway for container-side
development. To run the rendered app locally, open `workspace/app` in VS Code
and choose **Dev Containers: Reopen in Container**. See each template's README
for its runtime and development details. The Vue/Laravel two-stack example
also requires API URL and CORS changes; see the
[Vue template README](./templates/app-vue/README.md) and
[Laravel template README](./templates/app-laravel/README.md).

For an initial partial render, use `--app-only` or `--gitops-only` and clone
only that repository. Choose one command:

```sh
./scripts/copy-templates.sh --app-only
# or
./scripts/copy-templates.sh --gitops-only
```

Initial render destinations must be empty Git clones. Single-target rendering
can also refresh an existing clone, but it must be clean, including untracked
files. After a template or `.env` change, rendering overwrites generated files
without deleting files left by a previous template; review the resulting diff
before committing.

#### Continue the core setup

Commit and push the rendered GitOps files. Git may ask for your Gitea credentials:

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

> **Laravel only:** Before pushing the app in step 4, create its staging
> database Secret using the [Laravel database Secret](#laravel-database-secret)
> instructions.

### 4. Push the app and verify the default delivery flow

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
Flux and staging in this checkout's cluster with:

```sh
source .env
KUBECTL_CONTEXT="k3d-${K3D_CLUSTER_NAME}"
kubectl --context "$KUBECTL_CONTEXT" get kustomizations -n flux-system
kubectl --context "$KUBECTL_CONTEXT" get pods,services,ingress -n staging
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

### Optional: Prepare Laravel or multi-stack secrets

#### Laravel database Secret

The default Go stack does not need an application Secret. If you selected the
Laravel template, create its `app-database` Secret after Flux has created the
`staging` namespace and before step 4 above. From the framework checkout, the
helper can generate it without putting credentials in Git. First run
`kubectl config get-contexts`, then replace
`k3d-your-cluster` below with the context for this stack:

```sh
./scripts/setup-stack-secrets.sh --database-only \
  --database-context k3d-your-cluster
```

The namespace defaults to `staging`. Create the production Secret only after
the production namespace exists, adding `--database-namespace production`.
The helper preserves an existing database Secret; if one is missing while a
MariaDB PVC exists, it asks before creating new credentials. See the
[Laravel template README](./templates/app-laravel/README.md) for manual secret
creation and database access.

#### Cross-stack Collector authentication

For multiple stacks, set the `OTEL_CENTRAL_*` values in each stack's `.env`
before rendering its GitOps repository. Once Flux has created the central
ingest Ingress and the Collector Deployments, run the helper with contexts from
`kubectl config get-contexts`. Replace only the sample context values; keep
the option names as shown:

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
`.env.example` endpoint and sends credentials and telemetry without
encryption, so use it only on a trusted local network. HTTPS is an
alternative; change the endpoint and `--collector-scheme` to `https` and use
the central HTTPS port.

This helper manages Kubernetes Secrets and restarts forwarding Collectors so
they reload client auth; it does not edit GitOps. See the [Collector setup
guide](stack/monitoring/provider/kubernetes/README.md) for per-stack settings,
the multi-stack flow, and manual commands. Re-render and push changed GitOps
settings separately. The central receiver Secret is updated on each run:
enter the existing shared forwarder password to keep other clients working,
or choose a new password and update every forwarder's client Secret. After
deleting and recreating a k3d cluster, local-path data may remain in the
Docker storage volume but its Kubernetes PVC metadata is not restored
automatically.

### Optional: Manual AI Engineering proof of concept (Phase 1)

Phase 1 adds a manually started OpenHands Agent Canvas and local Ollama model
host. It does not watch Gitea issues, schedule work, or deploy changes. The
agent works only in the mounted `workspace/app` checkout; normal CI and human
review remain the gates before a change is merged.

Before starting, configure `OPENHANDS_GITEA_TOKEN` in `.env` with a token for
a dedicated Gitea account that can write only to the `app` repository. Grant
that account access only to `app`, then create a token with repository
read/write access in its Settings > Applications. The token is exposed to the
local agent so it can push a branch and create a PR. Do not use a Gitea
administrator token. The token is optional if you only want to experiment
with local edits; without it the agent cannot push changes or open a PR.

By default, the AI Engineering stack uses Ollama installed on the host and
starts only OpenHands. Set `OLLAMA_PROVIDER=container` in `.env` if you want
the script to start a separate Ollama container and download the model named
by `OLLAMA_MODEL` on first use. That container keeps its model data in a
persistent Docker volume.

Start the services with:

```sh
./scripts/ai-engineering.sh up
```

OpenHands and the optional Ollama container are independent of
`./scripts/up.sh`; starting or stopping the main stack does not start or stop
them. OpenHands is available at
`http://localhost:<OPENHANDS_PORT>/canvas` (default port `8001`).

In OpenHands `Settings > LLM > Advanced`, configure the local model:

First add a Provider:
- **Provider:** `ollama_chat`
- **Base URL for native Windows Ollama:** `http://host.docker.internal:11434`
- **Base URL for containerized Ollama:** `http://model-host:11434`
- **API key:** any placeholder, such as `local-llm`

For native Windows Ollama, it must accept connections from Docker Desktop;
configure its `OLLAMA_HOST` to listen on `0.0.0.0:11434` and allow the
connection through Windows Firewall as needed. Limit access to trusted
networks, since this exposes the Ollama API beyond Windows localhost.
Select the matching Base URL for the provider you are using.

Then add a new LLM model:
- **Custom model:** `ollama_chat/<model-name>` using a model installed in
  that Ollama instance (for example, `ollama_chat/qwen3.5`)

For the OpenHands Agent profile, the settings that worked reliably for the
example prompt were:

- **Reasoning Effort:** `medium`
- **Temperature:** `0.1`
- **Timeout:** `900`
- **Stream Idle Timeout:** `900`
- **Max Input Tokens:** leave blank
- **Max Output Tokens:** `4096`

Open the `/projects/app` workspace. The agent can use the `GITEA_API_URL`,
`GITEA_OWNER`, `GITEA_REPOSITORY`, and `GITEA_ACCESS_TOKEN` environment
variables to interact with the app repository. Ask it to fetch the issue from
the Gitea API and verify its title and description before planning or changing
files; if the issue cannot be fetched, it should stop and report that rather
than infer the requirements. Have it prepare a fresh task branch before making
any code or test changes: fetch `origin`, fast-forward local `main` from
`origin/main`, then create and switch to the task branch. Alternatively, it can
create the task branch directly from the freshly fetched `origin/main`. It must
never make task commits on `main`; if the worktree is not clean or the branch
cannot be prepared safely, it should stop and report the problem rather than
discard or overwrite changes. For example (replace <NUMBER>):

```text
Implement Gitea issue #<NUMBER> in this Laravel application.

## Ground rules

- Credentials are already in the environment: $GITEA_API_URL, $GITEA_OWNER, $GITEA_REPOSITORY, $GITEA_ACCESS_TOKEN, $WOODPECKER_API_URL, $WOODPECKER_TOKEN. Never print them and never paste their values into a command.
- Run one command per tool call (chain with && if needed).
- Explore with `git ls-files` and `git grep`. Never search vendor/ or node_modules/.
- Change existing files with the edit tool. Do not rewrite whole files with heredocs.
- Once a result is established, do not run extra commands to re-verify it beyond what the steps below require.

## 1. Retrieve and verify the issue

GET $GITEA_API_URL/repos/$GITEA_OWNER/$GITEA_REPOSITORY/issues/<issue-number> with header `Authorization: Bearer $GITEA_ACCESS_TOKEN`. Verify the title and description. If the issue cannot be retrieved, stop and report. Do not guess issue contents.

## 2. Prepare the repository

Run `git status`. The worktree must be clean. If not, stop and report; do not reset, stash, discard, or modify anything.

Then run these three commands, one per tool call:

git fetch origin
git checkout main
git merge --ff-only origin/main

If any fails: stop and report. Do not try alternative Git commands.

## 3. Create the issue branch

Create and switch to `issue/<issue-number>-<kebab-case-issue-title>`: lowercase a-z, digits and hyphens only, built from the verified title. Verify with `git branch --show-current`. Never commit task changes to main.

## 4. Implement the change (test-first, but finish the job)

1. Find every reference: `git grep -n` for the endpoint path and for the current (old) value or behaviour the issue changes. Read each matching test file in full.
2. Update the existing tests that assert the old behaviour. Add a new test only if no existing test covers it. Never leave two tests covering the same behaviour. Do not add traits, setup or dependencies the existing tests don't use.
3. Implement the minimal production change.
4. Before committing, `git grep` for the old value again. Nothing left may contradict the issue.

Keep the diff small. Do not modify unrelated files. Do not push a branch containing only a failing test.

## 5. Run tests when possible

If the runtime is available, run the relevant tests and fix failures caused by your change. If not (for example `php` is missing): do not install anything, do not work around it, and continue. CI is authoritative.

## 6. Commit and push

Verify that test and implementation changes are committed and nothing intended is left uncommitted. Then:

git push -u origin <branch-name>

## 7. Validate CI

CI is Woodpecker. Use only the two helper scripts below. Do not use a browser, do not fetch `target_url`, and do not query any other service. Never report a CI status that did not come from the scripts' output.

**A. Get the status.** Run `/opt/ci/ci-status.sh` (checks HEAD). It polls Gitea for up to 5 minutes and prints `SHA=...`, `CI_STATUS=passed|failed|pending|unavailable`, and one JSON line per `ci/woodpecker/` context including its `target_url`. If the tool says the command is still running, wait for it; do not start a second poll.

- Statuses returned for a SHA belong to that SHA. Pipeline numbers are repo-wide counters, so a number like 17 is normal. Never speculate that a status comes from an earlier commit.

**B. Act on CI_STATUS.**
- passed: run `/opt/ci/ci-details.sh "<target_url>"` once to record the pipeline number and step states, then go to section 8.
- pending: stop. No PR. Report the pending contexts.
- unavailable: report the script output verbatim and state that no Woodpecker status was reported for the SHA (or the exact error). Do not guess a cause. Go to section 8.
- failed: go to C.

**C. Diagnose and fix.** Run `/opt/ci/ci-details.sh "<target_url of the failing context>"`. It prints the pipeline summary, the steps with states, and the last 80 log lines of each failing step. If the script itself fails, stop and report its error.

- Related failure (the log names a test, file or message touched by your change, or the old value you replaced): make the smallest fix, commit, push, and run `/opt/ci/ci-status.sh` again. Maximum 2 fix attempts.
- Unrelated or unclear failure: run `/opt/ci/ci-status.sh $(git rev-parse origin/main) 1` to see whether main fails too, then stop and report.
- Stop if the same step fails again with the same error, if multiple unrelated failures appear, or after 2 fix attempts.
- Never create a PR while CI is failed.

Record for the final report: commit SHA checked; each `ci/woodpecker/` context and status; pipeline number (from ci-details output); pipeline URL (`target_url` as returned); steps with states and the last completed step; for failures, the failing step, the failing test names and what you changed.

## 8. Create the pull request

Only if all intended changes are committed, the branch is pushed, and CI is passed, or unavailable with the reason reported. Never if CI is failed or pending.

POST $GITEA_API_URL/repos/$GITEA_OWNER/$GITEA_REPOSITORY/pulls with headers `Authorization: Bearer $GITEA_ACCESS_TOKEN` and `Content-Type: application/json`:

{ "head": "<branch-name>", "base": "main", "title": "<title>" }

Use the exact branch name that was pushed. Do not invent alternate branch formats or retry with modified names unless the API error names the required format.

## 9. Verify pull request creation

GET $GITEA_API_URL/repos/$GITEA_OWNER/$GITEA_REPOSITORY/pulls/<pr-number>. Verify it exists, is open, and its head is the pushed branch. Obtain the PR number and `html_url` exactly as returned. If this fails, report PR creation as failed.

## 10. Final report

Issue number, issue title, branch name, files changed, CI details (section 7), fix attempts made (if any), PR number, PR URL.

Do not merge. Do not deploy. Do not perform additional enhancements beyond the issue.
```

The OpenHands container trusts `/projects/app` as a Git working directory.
OpenHands and Gitea join the same external Docker network, so the Gitea API and
rewritten Git remotes use Gitea's `scm:3000` service address. Git uses the
configured token for those HTTP operations, so the coding-agent container does
not need an SSH client. `host.docker.internal` is available for host services
such as native Ollama. The launcher runs OpenHands with the invoking host user's
UID and GID, allowing it to modify the mounted checkout and `.git` directory
without changing file permissions. The launcher creates the ignored
`workspace/openhands` directory as the invoking user and mounts it at
`/projects`; the app checkout is mounted separately at `/projects/app`. A
one-shot initialization service aligns the private OpenHands state volume with
the mapped IDs. Set `OPENHANDS_UID` and `OPENHANDS_GID` in `.env` only if you
need to override the detected IDs. App-specific test commands should use that
app's own development environment; OpenHands does not receive Docker socket
access.

Review the plan and diff before merging; CI still runs through Woodpecker.

Smaller models favor lower hardware requirements, while larger models may
perform better but require more memory. For containerized Ollama, the context
window defaults to 32K; reduce `OLLAMA_CONTEXT_LENGTH` or change
`OLLAMA_MODEL` in `.env` if needed. Configure model and context settings
separately in native Ollama. The optional Ollama container and OpenHands each
have persistent data volumes. Stop the AI Engineering services without
removing their data using:

```sh
./scripts/ai-engineering.sh down
```

Use `./scripts/ai-engineering.sh logs` or `status` to inspect the AI services.

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

After reconciliation, verify production in this checkout's cluster:

```sh
source .env
kubectl --context "k3d-${K3D_CLUSTER_NAME}" \
  get pods,services,ingress -n production
```

Then open `http://production.localhost:<K3D_CLUSTER_PORT>/`.

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

#### Pausing or tearing down the stack

To pause the lab and resume it later with its Kubernetes resources intact, run:

```sh
./scripts/stop.sh
```

This stops the k3d cluster and, when this checkout owns them, the Gitea,
Woodpecker, and registry containers. It does not delete containers, the
cluster, volumes, or network. If `START_LOCAL_PROVIDERS=false`, shared
providers are left running. Run `./scripts/up.sh` to start the stopped
providers and cluster again.

Use `./scripts/down.sh` only when you intend to **delete and recreate the k3d
cluster**, for example to discard its Kubernetes configuration, rebuild it
from scratch, or apply a changed cluster definition. It prompts you to type
the configured cluster name. Use `./scripts/down.sh --yes` only when an
unattended teardown is intentional.
The script deletes the cluster and its Kubernetes metadata, then removes this
checkout's local provider containers. It does not delete Docker data volumes.
When using shared providers (`START_LOCAL_PROVIDERS=false`), it leaves those
providers and their network running.

After teardown, `./scripts/up.sh` creates a new cluster and Flux reapplies the
GitOps-managed resources. Kubernetes-only state, including manually created
Secrets, is deleted and must be recreated. The `<K3D_CLUSTER_NAME>-storage`
Docker volume remains, but Kubernetes PVC metadata is not restored and its
data is not automatically reattached to the new cluster. Do not treat that
leftover volume as a backup or assume its contents will be recovered.

Gitea, Woodpecker, and registry data are in the named volumes
`<STACK_NAME>-gitea-data`, `<STACK_NAME>-woodpecker-data`, and
`<STACK_NAME>-registry-data` (`mds` is the default stack name). The
`<K3D_CLUSTER_NAME>-storage` volume is mounted on every k3d node. These
volumes persist across both stop and teardown. Remove a volume with
`docker volume rm` only when you explicitly intend to delete its contents.

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
  forward its Service in this checkout's cluster:

  ```sh
  source .env
  kubectl --context "k3d-${K3D_CLUSTER_NAME}" \
    port-forward -n monitoring service/prometheus 9090:9090
  ```

  Then open `http://localhost:9090/alerts`. Use a different local port when
  forwarding Prometheus from multiple stacks at once.

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
source .env
KUBECTL_CONTEXT="k3d-${K3D_CLUSTER_NAME}"
kubectl --context "$KUBECTL_CONTEXT" run observability-alert-test -n staging \
  --image=example.invalid/observability-alert-test:missing --restart=Never
```

After the pod has been unable to pull its image for at least two minutes,
check Prometheus at `http://localhost:9090/alerts` (use the
`kubectl port-forward` command in the Observability section) and look for the
`KubernetesPodImagePullBackOff` alert. Check Mailpit for the firing
notification. Then remove the test pod:

```sh
kubectl --context "$KUBECTL_CONTEXT" delete pod observability-alert-test -n staging
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

### Diagnose a staging or production 503

`-n staging` selects a namespace, not a cluster. `kubectl` otherwise uses the
current context in the shared kubeconfig; starting another checkout with
`./scripts/up.sh` changes that context. Run these commands from the checkout
whose cluster you want to inspect. Its `.env` determines the k3d context:

```sh
source .env
KUBECTL_CONTEXT="k3d-${K3D_CLUSTER_NAME}"
NAMESPACE=staging

kubectl --context "$KUBECTL_CONTEXT" \
  get kustomizations -n flux-system
kubectl --context "$KUBECTL_CONTEXT" \
  describe kustomization "${NAMESPACE}-app-workload" -n flux-system
kubectl --context "$KUBECTL_CONTEXT" \
  get pods,services,ingress,endpoints -n "$NAMESPACE" -o wide
kubectl --context "$KUBECTL_CONTEXT" \
  get events -n "$NAMESPACE" --sort-by=.lastTimestamp
```

The `flux-system` Kustomization can be Ready while a child app Kustomization
is failing; check `${NAMESPACE}-app-workload` for the application-specific
reconciliation status. For production, set `NAMESPACE=production`. If the app
Service has no endpoints, check why its pod is not Ready; if the pod is
running, inspect its logs and the Ingress backend:

```sh
kubectl --context "$KUBECTL_CONTEXT" \
  describe service app -n "$NAMESPACE"
kubectl --context "$KUBECTL_CONTEXT" \
  describe ingress app -n "$NAMESPACE"
kubectl --context "$KUBECTL_CONTEXT" \
  logs deployment/app -n "$NAMESPACE" --all-containers=true --tail=100
```

Confirm the request is going to this stack's published ingress port:

```sh
curl -v "http://staging.localhost:${K3D_CLUSTER_PORT}/"
```

Use `production.localhost` if debugging production. In a multi-stack setup,
run the commands from that stack's checkout so both its `.env` context and
`K3D_CLUSTER_PORT` are used.

## Extendability

The framework is organised around providers so infrastructure implementations
can be replaced or added as the lab grows. The current template-rendering
workflow includes the example app, GitOps repository, and Kubernetes
observability manifests. Edit the source templates and provider manifests in
this repository, then render them into the Gitea repositories; Flux applies
the rendered Kubernetes state from GitOps.

Application-specific Kubernetes resources and workload configuration live in
each app template's `gitops/` directory. The renderer copies these into the
generated GitOps repository as a Kustomize Component, keeping optional app
dependencies and implementation-specific patches separate from the shared
delivery flow.

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
- Investigate NPU use in AI Engineering, for example in the planning stage,
  for duplicate issue detection, for repository understanding, for CI failure
  classification, as PR review agent, or to keep architectural memory. While
  coding models use GPU, planning models can use NPU, ie GPU for code
  generation and NPU for retrieval, embeddings, classification and
  summarisation.

## Project layout

- `scripts/stop.sh` — pause this stack without deleting the k3d cluster or
  provider containers
- `scripts/down.sh` — delete the k3d cluster after confirmation; use `--yes`
  only for intentional non-interactive teardown
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
