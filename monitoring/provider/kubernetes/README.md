# Kubernetes monitoring provider

This provider owns the Kubernetes deployment configuration for Prometheus and
Grafana. Its manifests are rendered by `scripts/copy-templates.sh` into the
GitOps repository at `clusters/<K3D_CLUSTER_NAME>/monitoring/`. The cluster
Kustomization includes that directory, and Flux applies the rendered resources.

The provider deploys Prometheus and Grafana as separate workloads in the
`monitoring` namespace. Prometheus discovers only the app metrics endpoints
in staging and production. Grafana queries Prometheus through its in-cluster
Service and is exposed at `http://monitoring.localhost:<K3D_CLUSTER_PORT>/`
through ingress-nginx. Its anonymous viewer access is intended only for the
trusted local lab.

Monitoring is included by the current template-rendering workflow. Provider
selection and alternative implementations are intentionally deferred until
provider configuration is generalized across the stack.
