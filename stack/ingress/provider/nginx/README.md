# ingress-nginx Provider

This provider installs and removes ingress-nginx using the upstream Kubernetes
manifest for the kind provider. `wait-ready.sh` waits for the admission
certificate Jobs and admission endpoint before Flux reconciles Ingress
resources.

The k3d-specific host-port adjustment lives in
`stack/cluster/provider/k3d/configure-ingress-nginx.sh`, since it depends on the
cluster's LoadBalancer networking.

The stack enables the controller's `/metrics` endpoint after the controller is
ready. The monitoring provider supplies an internal ClusterIP Service for
Prometheus to scrape; the metrics endpoint is not exposed outside the cluster.
For an existing cluster, run `./stack/ingress/provider/nginx/enable-metrics.sh` once
from the framework repository root. `scripts/up.sh` runs it automatically.
