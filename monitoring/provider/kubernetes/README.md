# Kubernetes monitoring provider

This provider owns the Kubernetes deployment configuration for Prometheus and
Grafana. Its manifests are rendered by `scripts/copy-templates.sh` into the
GitOps repository at `clusters/<K3D_CLUSTER_NAME>/monitoring/`. The cluster
Kustomization includes that directory, and Flux applies the rendered resources.

The provider deploys Prometheus and Grafana as separate workloads in the
`monitoring` namespace. Prometheus discovers only the app metrics endpoints
in staging and production. The app metrics include HTTP request counts,
durations, and selected Go runtime data: goroutine count, heap and stack
memory, and garbage-collection cycles. Grafana queries Prometheus through its
in-cluster Service and is exposed at
`http://monitoring.localhost:<K3D_CLUSTER_PORT>/` through ingress-nginx. Its
anonymous viewer access is intended only for the trusted local lab.

Grafana provisioning files are managed with Kustomize's ConfigMap generator.
Their content hash is included in the generated ConfigMap name and referenced
by the Deployment, so changing a dashboard or provisioning file changes the
pod template and automatically rolls out Grafana when Flux reconciles. No
manual pod restart or external reloader is required.

Monitoring is included by the current template-rendering workflow. Provider
selection and alternative implementations are intentionally deferred until
provider configuration is generalized across the stack.
