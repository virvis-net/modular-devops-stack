# GitOps Template Repository

This repository contains the desired Kubernetes state for the example
`__K3D_CLUSTER_NAME__`. Flux watches the configured cluster path and reconciles
it into the cluster.

The cluster Kustomization initially includes only the `staging` environment.
Staging and production use separate namespaces, app overlays, and Ingress
hosts, while sharing the same local k3d cluster and registry. This provides
logical separation for namespaced services, configuration, and secrets; it is
not a strong security boundary.

Flux bootstrap files are generated dynamically by `flux bootstrap` and should
not be copied from this template.

The framework's Kubernetes monitoring provider supplies the Prometheus,
Grafana, Loki, Tempo, event-exporter, Alertmanager, and Mailpit manifests.
`scripts/copy-templates.sh` renders them into this
repository's `clusters/__K3D_CLUSTER_NAME__/monitoring/` directory, where the
cluster Kustomization includes them and Flux applies them. Prometheus discovers
app metrics by Kubernetes Service and port, Kubernetes object state through
kube-state-metrics, and ingress-nginx metrics. Grafana provisions a dashboard
from the provider configuration. The dashboard includes workload state,
ingress metrics, live node and container utilization, and OpenTelemetry
request latency. The Collector sends logs to Loki, traces to Tempo, and
metrics to Prometheus; the event exporter also sends Kubernetes events to
Loki. Prometheus evaluates target-health, application 5xx-rate, image-pull,
and crash-loop alerts. Alertmanager sends notifications to the local Mailpit
inbox for testing. Prometheus has read-only discovery permissions; its app
scrape is restricted to staging and production. Grafana queries Prometheus
through an internal Service. The framework's ingress provider enables
ingress-nginx metrics, while the monitoring provider adds its internal scrape
Service. Grafana and the Mailpit web inbox are available at
`http://monitoring.localhost:__K3D_CLUSTER_PORT__/` through ingress-nginx;
`http://notifications.localhost:__K3D_CLUSTER_PORT__/` serves the inbox.
Prometheus remains internal and can be accessed with `kubectl port-forward`.
Grafana and the Mailpit inbox have no login in this local demo; do not expose
their hosts outside a trusted development environment.

The Woodpecker app pipeline tests changes and, on pushes to `main`, builds and
pushes an image tagged with the commit SHA. It records the pushed image digest
in `apps/app/overlays/staging/kustomization.yaml`;
Flux then deploys that exact image to staging.

To promote a release, use a GitOps pull request: copy the staging `digest`
value from `apps/app/overlays/staging/kustomization.yaml` into the production
overlay's `digest` field, then add `environments/production` to
the cluster Kustomization. Merging that reviewed change makes Flux deploy the
same image digest to production. Do not rebuild the image for promotion.

For the initial setup, push this template's contents to the Gitea
`__GITEA_ORG__/gitops` repository on branch `main` before allowing Flux
bootstrap to continue.
