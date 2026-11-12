# Flux Provider (GitOps layer)

## Overview

This folder contains the Flux bootstrap and teardown scripts used by the
current stack. Flux watches the GitOps repository and reconciles the configured
cluster path into Kubernetes.

`bootstrap.sh` runs the Flux CLI in a container, prepares a readable kubeconfig
copy from the local Kubernetes config, and connects Flux to the GitOps
repository configured by `.env`. During setup, watch the terminal for Flux CLI
progress. Bootstrap installs the controllers and commits its reconciliation
manifests to the configured GitOps path; you can verify the commits in Gitea.
When the GitOps URL points to this stack's Gitea, Flux uses Gitea's address on
the shared Docker network and its internal SSH port. This lets cluster pods
reach Gitea without depending on host-published port forwarding.
The default Flux CLI image is `ghcr.io/fluxcd/flux-cli:v2.3.0`, which supports
the stable `kustomize.toolkit.fluxcd.io/v1` API used by the GitOps templates.
The CLI skips its deploy-key confirmation prompt because bootstrap runs in a
non-interactive container and the public key was added during initial setup.
Application desired state lives in the GitOps repository, seeded from
`templates/gitops/`.

If bootstrap fails immediately because a connection to the Git host is refused
or unreachable from the cluster, the script retries up to two times with a
short delay. Timeouts and other failures are reported without retrying.

The script expects the GitOps repository and its cluster path to exist and
requires the write-enabled Flux deploy key for the bootstrap commits. By
default, the private key and Flux-specific `known_hosts` file are stored in
the ignored `stack/.state/ssh/` directory; set `FLUX_PRIVATE_KEY` in `.env` to
use a key at another path. Newly generated keys are set to `0644` so the
bootstrap container can read them; this also makes them readable to other
users on the host. Use the key only on a trusted machine and do not reuse it
for unrelated access. Set `FLUX_BOOTSTRAP_TIMEOUT` to change the CLI timeout
(default: `15m`).
