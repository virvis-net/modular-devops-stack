# Gitea Provider (Source Control Layer)

This folder contains the Gitea service used by the current local stack.

## Components
- docker-compose.yaml — runs the Gitea service
- data/ — persistent storage for repositories and configuration

The stack uses Gitea to host the `app` and `gitops` repositories. Woodpecker
uses Gitea OAuth for sign-in, while Flux and the app pipeline use SSH deploy
keys to read and update the GitOps repository.
