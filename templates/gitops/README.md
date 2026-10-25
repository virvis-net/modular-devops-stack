# GitOps Template Repository

This repository defines the desired state for the Modular DevOps Stack cluster.

Flux bootstrap files (`flux-system/`) are intentionally excluded because they
are generated dynamically by `flux bootstrap`.

Structure:
- clusters/mds-cluster: cluster-specific desired state
- apps/app: reusable application manifests (base + overlays)

The CI pipeline updates the image tag in:
clusters/mds-cluster/apps/app/kustomization.yaml

Flux then reconciles the new desired state automatically.
