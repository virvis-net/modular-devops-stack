# GitOps Template Repository

This repository contains the desired Kubernetes state for the example
`__K3D_CLUSTER_NAME__`. Flux watches the configured cluster path and reconciles
it into the cluster.

The cluster Kustomization initially includes only the `staging` environment.
Staging and production use separate namespaces, app overlays, and Ingress
hosts, while sharing the same local k3d cluster and registry. This provides
logical separation for namespaced services, configuration, and secrets; it is
not a strong security boundary.

Flux bootstrap files are generated dynamically by `flux bootstrap` and should
not be copied from this template.

The Woodpecker app pipeline tests changes and, on pushes to `main`, builds and
pushes an image tagged with the commit SHA. It records the pushed image digest
in `apps/app/overlays/staging/kustomization.yaml`;
Flux then deploys that exact image to staging.

To promote a release, use a GitOps pull request: copy the staging `digest`
value from `apps/app/overlays/staging/kustomization.yaml` into the production
overlay's `digest` field, then add `environments/production` to
the cluster Kustomization. Merging that reviewed change makes Flux deploy the
same image digest to production. Do not rebuild the image for promotion.

For the initial setup, push this template's contents to the Gitea
`__STACK_NAME__/gitops` repository on branch `main` before allowing Flux
bootstrap to continue.
