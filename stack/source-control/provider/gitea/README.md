# Gitea Provider (Source Control Layer)

This folder contains the Gitea service used by the current local stack.

## Components
- docker-compose.yaml — runs the Gitea service
- `mds-gitea-data` Docker volume — persistent storage for repositories and
  configuration (the prefix follows `STACK_NAME`)
- The Compose file includes a commented bind-mount alternative under
  `data/` for users who prefer to inspect files directly.

The stack uses Gitea to host the `app` and `gitops` repositories. Woodpecker
uses Gitea OAuth for sign-in, while Flux and the app pipeline use SSH deploy
keys to read and update the GitOps repository.
