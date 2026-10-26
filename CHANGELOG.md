# Changelog

## 0.4.0 - Staging and Production environments
- CD deploys to staging environment on main branch
- Optional image promotion to deploy on production environment

## 0.3.0 - CI test step
- Added test step to CI pipeline
- Container image is built if tests pass

## 0.2.2 - Bug fixes
- Fix hard coded network reference
- Connect Woodpecker as Gitea admin
- Improved first run experience

## 0.2.1 - Ingress provider
- Separate provider for nginx ingress
- Script idempotency improvements

## 0.2.0 – Basic working devops stack
- Added a working local CI/CD and GitOps flow using Gitea, Woodpecker, a local container registry, k3d, Flux, and ingress-nginx.
- Added example Go app and GitOps repository templates, with CI image publishing and Flux-based deployment.

## 0.1.0 – Project initialized
- Repository created
- Added README and .gitignore
