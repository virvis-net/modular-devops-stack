# Woodpecker CI Provider (CI layer)

This folder contains the Woodpecker CI implementation of the CI layer.

## Components
- docker-compose.yaml — starts server + agent
- `mds-woodpecker-data` Docker volume — persistent storage for CI state (the
  prefix follows `STACK_NAME`)
- The Compose file includes a commented bind-mount alternative under
  `data/` for users who prefer to inspect files directly.

## Integration
- Gitea is used as the source-control provider
- Registry is used for image storage
- The sample pipeline builds and pushes the app image, then commits the
  immutable image digest to the GitOps repository for Flux to deploy.

The example agent mounts the host Docker socket. Only enable trusted
repositories whose pipeline code you control. The app pipeline also needs a
Woodpecker repository secret named `GIT_SSH_KEY`. Use the private key created
for Flux bootstrap (by default `~/.ssh/flux_deploy_key`); its public key must
have write access to the GitOps repository. Keep the private key out of Git.
