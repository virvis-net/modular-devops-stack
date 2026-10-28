# Kubernetes monitoring provider

This provider owns the Kubernetes deployment configuration for Prometheus and
Grafana. Its manifests are rendered by `scripts/copy-templates.sh` into the
GitOps repository at `clusters/<K3D_CLUSTER_NAME>/monitoring/`. The cluster
Kustomization includes that directory, and Flux applies the rendered resources.

The provider deploys Prometheus, Grafana, kube-state-metrics, and an
OpenTelemetry Collector as separate workloads in the `monitoring` namespace.
Prometheus discovers app metrics endpoints in staging and production,
Kubernetes state from a least-privilege kube-state-metrics deployment,
ingress-nginx metrics, and kubelet resource metrics. The app metrics
include HTTP request counts, durations, and selected Go runtime data:
goroutine count, heap and stack memory, and garbage-collection cycles. Grafana
queries Prometheus through its in-cluster Service and is exposed at
`http://monitoring.localhost:<K3D_CLUSTER_PORT>/` through ingress-nginx. Its
anonymous viewer access is intended only for the trusted local lab.

Prometheus also scrapes kubelet resource metrics through the Kubernetes API
server's node proxy. The Prometheus service account can discover nodes and
`get` the `nodes/proxy` subresource; this permission is required for the proxy
path and should be considered when adapting the setup beyond this trusted
local lab.

The dashboard adds pod phases, desired versus available app replicas,
container restarts, configured CPU and memory requests, live node CPU and
memory working set, staging/production container CPU and memory working set,
and ingress request rate, status, and p95 latency. Resource requests show
configured capacity; kubelet resource metrics show observed usage.

The Collector accepts OTLP over gRPC and HTTP on internal ClusterIP Service
ports 4317 and 4318. Its debug exporter writes received traces and metrics to
the Collector pod logs for this demonstration; no telemetry backend or
persistent storage is configured yet. Inspect received telemetry with
`kubectl logs -n monitoring deployment/otel-collector`.

The ingress controller's metrics endpoint is enabled by
`ingress/provider/nginx/enable-metrics.sh`; the provider includes a separate
internal Service for scraping it. Prometheus scrape configuration is generated
from `prometheus/config/prometheus.yml`, so changing scrape jobs updates its
ConfigMap hash and rolls out Prometheus automatically.

Grafana provisioning files are managed with Kustomize's ConfigMap generator.
Their content hash is included in the generated ConfigMap name and referenced
by the Deployment, so changing a dashboard or provisioning file changes the
pod template and automatically rolls out Grafana when Flux reconciles. No
manual pod restart or external reloader is required.

Monitoring is included by the current template-rendering workflow. Provider
selection and alternative implementations are intentionally deferred until
provider configuration is generalized across the stack.
