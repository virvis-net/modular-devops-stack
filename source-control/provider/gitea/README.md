# Gitea Provider (Source Control Layer)

This folder contains the Gitea implementation of the source-control provider.

## Components
- docker-compose.yaml — runs the Gitea service
- data/ — persistent storage for repositories and configuration

## Neutral Architecture
The top-level folder `source-control/` represents the domain.
The `provider/` folder contains the current implementation.
This allows swapping Gitea for GitLab, Forgejo, or any other provider without changing the domain structure.
