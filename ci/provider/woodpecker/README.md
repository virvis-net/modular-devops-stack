# Woodpecker CI Provider (CI layer)

This folder contains the Woodpecker CI implementation of the CI layer.

## Components
- docker-compose.yaml — starts server + agent
- data/ — persistent storage for CI state

## Integration
- Gitea is used as the source-control provider
- Registry is used for image storage
- Flux (CD layer) will deploy images built by Woodpecker

## Neutral Architecture
The top-level folder `ci/` represents the domain.
The `provider/` folder contains the current implementation.
This allows swapping Woodpecker for GitHub Actions, GitLab CI, Jenkins, or Tekton without changing the domain structure.
