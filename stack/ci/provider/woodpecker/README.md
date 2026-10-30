# Woodpecker CI Provider (CI layer)

This folder contains the Woodpecker CI implementation of the CI layer.

## Components
- docker-compose.yaml — starts server + agent
- data/ — persistent storage for CI state

## Integration
- Gitea is used as the source-control provider
- Registry is used for image storage
- The sample pipeline builds and pushes the app image, then commits the new tag
  to the GitOps repository for Flux to deploy.

The example agent mounts the host Docker socket. Only enable trusted
repositories whose pipeline code you control. The app pipeline also needs a
Woodpecker repository secret named `GIT_SSH_KEY`. Use the private key created
for Flux bootstrap (by default `~/.ssh/flux_deploy_key`); its public key must
have write access to the GitOps repository. Keep the private key out of Git.
