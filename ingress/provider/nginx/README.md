# ingress-nginx Provider

This provider installs and removes ingress-nginx using the upstream Kubernetes
manifest for the kind provider. `wait-ready.sh` waits for the admission
certificate Jobs and admission endpoint before Flux reconciles Ingress
resources.

The k3d-specific host-port adjustment lives in
`cluster/provider/k3d/configure-ingress-nginx.sh`, since it depends on the
cluster's LoadBalancer networking.
