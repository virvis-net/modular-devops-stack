# Modular DevOps Stack

A modular, local-first CI/CD and GitOps scaffold designed for:
- local development
- staging environments
- scalable production simulation

Technologies:
- Gitea (source control)
- Docker Desktop
- k3d (local Kubernetes cluster)
- FluxCD or ArgoCD (GitOps CD)
- Woodpecker CI or Jenkins (CI)
- Local container registry
- Helm / Kustomize (infra-as-code)

This repository will evolve step-by-step into a reusable DevOps foundation.

## Setup

1. Run script `./up.sh`
1. Install Gitea, add SSH key and set up repositories `http://localhost:3000`
    - create an Organisation named "mds"
    - set up repositories named "app", "gitops" and "infrastructure"
1. Add new OAuths application in Gitea Settings>Applications:
    - Application Name: woodpecker
    - Redirect URIs:
        http://localhost:8000/authorize
        http://host.docker.internal:8000/authorize
        http://ci-server:8000/authorize
1. Add the generated Client ID and Secret to the Woodpecker docker-compose.yaml (TODO: move these values to .env or similar)
1. Restart the stack by running scripts `./down.sh` and `./up.sh`
1. Log in to Woodpecker and connect the "app" repository created earlier `http://localhost:8000/login`
    - Then go into Settings of the "app" repo and select the checkbox next to "Volumes" under "Trusted" and save the changes
