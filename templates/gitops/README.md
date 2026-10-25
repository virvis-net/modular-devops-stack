# GitOps Template Repository

This repository contains the desired Kubernetes state for the example
`mds-cluster`. Flux watches the configured cluster path and reconciles it into
the cluster.

The top-level `clusters/mds-cluster/kustomization.yaml` sets the application
namespace and includes the cluster's app resources. Those resources use the
reusable manifests under `apps/app/base/` and add a cluster-specific Ingress.

Flux bootstrap files are generated dynamically by `flux bootstrap` and should
not be copied from this template.

The Woodpecker app pipeline updates the `newTag` value in
`clusters/mds-cluster/apps/app/kustomization.yaml`. Flux then deploys the
referenced image from the local registry.

For the initial setup, push this template's contents to the Gitea `mds/gitops`
repository on branch `main` before allowing Flux bootstrap to continue.
