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
Application desired state lives in the GitOps repository, seeded from
`templates/gitops/`.

The script expects the GitOps repository and its cluster path to exist and
requires the write-enabled Flux deploy key for the bootstrap commits. By
default, the private key and Flux-specific `known_hosts` file are stored in
the ignored `stack/.state/ssh/` directory; set `FLUX_PRIVATE_KEY` in `.env` to
use a key at another path. Newly generated keys are set to `0644` so the
bootstrap container can read them; this also makes them readable to other
users on the host. Use the key only on a trusted machine and do not reuse it
for unrelated access. Set `FLUX_BOOTSTRAP_TIMEOUT` to change the CLI timeout
(default: `15m`).
