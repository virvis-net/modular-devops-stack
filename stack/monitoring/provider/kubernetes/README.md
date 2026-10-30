# Kubernetes monitoring provider

This provider owns the Kubernetes deployment configuration for Prometheus and
Grafana. Its manifests are rendered by `scripts/copy-templates.sh` into the
GitOps repository at `clusters/<K3D_CLUSTER_NAME>/monitoring/`. The cluster
Kustomization includes that directory, and Flux applies the rendered resources.

The provider deploys Prometheus, Grafana, kube-state-metrics, an
OpenTelemetry Collector, Loki, and Tempo as separate workloads in the
`monitoring` namespace. It also deploys a Kubernetes event exporter,
Alertmanager, and Mailpit as a local email sink.
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
ports 4317 and 4318. It exports traces to Tempo, logs to Loki, and metrics to
its Prometheus exporter, which Prometheus scrapes. Tempo's metrics generator
also remote-writes span and service-graph metrics to Prometheus.

Grafana provisions Prometheus, Loki, and Tempo data sources. Use Grafana
Explore with Loki and the query `{service_name="example-app"} | trace_id != ""`
to find correlated app request logs; the `TraceID` link opens the trace in
Tempo. Tempo's trace-to-logs link filters Loki by service and trace ID, and
Prometheus exemplars link applicable metric samples back to Tempo. The
dashboard includes the OTel HTTP request-duration p95 panel.

Loki retains logs for seven days and Tempo retains traces for 48 hours. Each
uses a 2Gi PVC, backed by the cluster's local-path storage in the local k3d
setup. These are single-replica local backends, not highly available; PVCs
provide persistence across pod restarts but are not backups.

The event exporter has read-only access to Kubernetes Events and pushes them
to Loki with the `job="kubernetes-events"` label. Query them in Grafana Explore
with `{job="kubernetes-events"}`. The event exporter uses a 60-second event
age cutoff, so it collects current events rather than serving as a durable
Kubernetes event archive.

Prometheus evaluates alerts for scrape targets that stay down, an elevated
application 5xx rate, pod image-pull failures, and crash-looping containers.
Alertmanager routes firing and resolved notifications to a local Mailpit SMTP
inbox; no external notification service is configured. To inspect alerts and
the test inbox, open `http://notifications.localhost:<K3D_CLUSTER_PORT>/` in
your browser. The neutral `notifications.localhost` host routes only the
Mailpit web UI; SMTP remains internal to the cluster. The inbox has no
authentication, so keep it within the trusted local lab. Prometheus remains
internal and is available for rule inspection with a port-forward:

```bash
kubectl port-forward -n monitoring service/prometheus 9090:9090
```

Open `http://localhost:9090/alerts` to see evaluated alert rules and
`http://notifications.localhost:<K3D_CLUSTER_PORT>/` to inspect email
notifications. To exercise event
collection and the image-pull alert, create a temporary pod using a deliberately
invalid image:

```bash
kubectl run observability-alert-test -n staging \
  --image=example.invalid/observability-alert-test:missing --restart=Never
```

Wait at least two minutes for `KubernetesPodImagePullBackOff` to fire. Query
Loki with `{job="kubernetes-events"} |= "observability-alert-test"` and check
the alert in Prometheus and its email in Mailpit. Then remove the test pod:

```bash
kubectl delete pod observability-alert-test -n staging
```

Alertmanager and Mailpit are for this trusted local lab only. Mailpit is
in-memory, receives no external mail, and loses messages when restarted.

The ingress controller's metrics endpoint is enabled by
`stack/ingress/provider/nginx/enable-metrics.sh`; the provider includes a
separate internal Service for scraping it. Prometheus scrape configuration is
generated from `prometheus/config/prometheus.yml`, so changing scrape jobs
updates its ConfigMap hash and rolls out Prometheus automatically.

Grafana provisioning files are managed with Kustomize's ConfigMap generator.
Their content hash is included in the generated ConfigMap name and referenced
by the Deployment, so changing a dashboard or provisioning file changes the
pod template and automatically rolls out Grafana when Flux reconciles. No
manual pod restart or external reloader is required.

Monitoring is included by the current template-rendering workflow. Provider
selection and alternative implementations are intentionally deferred until
provider configuration is generalized across the stack.
