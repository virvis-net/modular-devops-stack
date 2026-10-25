# Example App Repository

This repository is a minimal Go application and Woodpecker pipeline for the
Modular DevOps Stack lab.

## Delivery flow

On each push to the `app` repository, `.woodpecker.yml`:

1. Builds the container image and pushes it to the local registry.
2. Updates the image tag in `clusters/mds-cluster/apps/app/kustomization.yaml`
   in the GitOps repository.
3. Flux observes that Git change and deploys the new image.

## Setup

1. Push the contents of this directory to the Gitea `mds/app` repository.
2. In Woodpecker, activate `mds/app` and mark it as trusted because the build
   mounts the Docker socket.
3. Add the contents of the Flux deploy key's private key file (by default
   `~/.ssh/flux_deploy_key`) to the `mds/app` repository secrets in Woodpecker
   as `GIT_SSH_KEY`. Its public key must already be configured with write
   access to `mds/gitops`. Do not commit the private key.
4. Push an app change and confirm that the pipeline pushes the image and
   updates the GitOps repository.

The sample pipeline uses the local registry and default Gitea SSH address from
the stack configuration. Update `.woodpecker.yml` if those endpoints change.
