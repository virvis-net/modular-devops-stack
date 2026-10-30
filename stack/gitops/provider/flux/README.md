# Flux Provider (GitOps layer)

## Overview

This folder contains the Flux bootstrap and teardown scripts used by the
current stack. Flux watches the GitOps repository and reconciles the configured
cluster path into Kubernetes.

`bootstrap.sh` runs the Flux CLI in a container, uses the local kubeconfig, and
connects Flux to the GitOps repository configured by `.env`. Flux generates and
commits its own sync manifests to that repository. Application desired state
lives in the GitOps repository, seeded from `templates/gitops/`.

The script expects the GitOps repository and its cluster path to exist and
requires a write-enabled deploy key for the initial bootstrap commit. Set
`FLUX_BOOTSTRAP_TIMEOUT` to change the CLI timeout (default: `15m`).
