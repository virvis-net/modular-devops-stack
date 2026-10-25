# App Repository — Modular DevOps Stack Template

This repository contains a minimal example application and CI pipeline
for the Modular DevOps Stack.

## Overview

- Builds a container image using Docker.
- Pushes the image to the local registry (`localhost:5000`).
- Updates the GitOps repository with the new image tag.
- Flux automatically deploys the new version.

## Folder Structure

src/          → application source code
Dockerfile    → container build definition
.woodpecker.yml → CI pipeline (build + update GitOps)


## Usage

1. Push this repository to Gitea.
2. Configure Woodpecker with a project secret named `GIT_SSH_KEY`.
3. Trigger a build by pushing a commit.
4. The pipeline will:
   - Build and push the image.
   - Update the GitOps repo.
   - Flux will deploy the new image automatically.
