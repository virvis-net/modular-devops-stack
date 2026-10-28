# Changelog

## 0.7.1 - Cluster and ingress metrics (live)
- Added live node and staging/production container CPU and memory utilization from kubelet resource metrics

## 0.7.0 - Cluster and ingress metrics
- Added kube-state-metrics for Kubernetes workload state and resource requests
- Enabled ingress-nginx metrics scraping and added infrastructure dashboard panels
- Made Prometheus configuration changes trigger an automatic rollout

## 0.6.1 - Application metrics (runtime)
- Added Go runtime metrics for goroutines, memory use, stack use, and GC cycles
- Configured Grafana provisioning changes to trigger automatic pod rollouts

## 0.6.0 - Application metrics
- Added monitoring deployment configuration to the framework as a provider which will be rendered it into the GitOps repository during init, ready for Flux to apply
- Exposed application request counters and duration histograms for Prometheus
- Added GitOps-managed Prometheus scraping and a provisioned Grafana dashboard
- Exposed the local Grafana dashboard through ingress-nginx

## 0.5.0 - Application health checks
- Added `/healthz` and `/readyz` endpoints to the example app
- Configured Kubernetes liveness and readiness probes for staging and production

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
