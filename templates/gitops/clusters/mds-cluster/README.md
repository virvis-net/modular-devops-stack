# __K3D_CLUSTER_NAME__

This folder defines the desired state for the `__K3D_CLUSTER_NAME__` Kubernetes
cluster. Its root Kustomization initially includes the staging environment;
production is added when an image is promoted.

Each environment has a dedicated namespace, app overlay, and Ingress. They
share one local k3d cluster, so this is logical rather than strong security
isolation. Monitoring uses a separate `monitoring` namespace.

## Accessing the environments

After Flux has reconciled the GitOps repository and the app Pod is Ready,
staging is available through ingress-nginx:

http://staging.localhost:__K3D_CLUSTER_PORT__/

After a production promotion PR is merged, production is available at:

http://production.localhost:__K3D_CLUSTER_PORT__/

### How it works

- The app container listens internally on port **8080**.
- The Kubernetes Service exposes the app on port **80** inside the cluster.
- Each environment has its own namespace, Service, and Ingress hostname.
- K3d’s load balancer maps host port **__K3D_CLUSTER_PORT__** to the cluster’s
  Ingress controller.

### Verifying the deployment

You can confirm the app is running with:

```bash
kubectl get all,ingress -n staging
kubectl get all,ingress -n production
```

The production namespace remains unused until the first promotion.

## Application metrics

Prometheus discovers the app Service's `metrics` port in the `staging` and
`production` namespaces. The production target appears after production is
enabled. The dashboard also shows Kubernetes pod/deployment state, requested
CPU and memory, and ingress traffic/latency. CPU and memory are configured
requests, not live utilization. Grafana has a provisioned application and
infrastructure dashboard available at
`http://monitoring.localhost:__K3D_CLUSTER_PORT__/` through ingress-nginx.
The alert notification inbox is available at
`http://notifications.localhost:__K3D_CLUSTER_PORT__/`. Prometheus remains
internal to the cluster; use `kubectl port-forward` when you need its UI.
Grafana and the notification inbox have no login in this local demo, so keep
these ingresses limited to the trusted local lab.
Generate requests to the staging or production app to populate the dashboard.
Prometheus stores metrics in ephemeral pod storage, so its history is lost if
the pod is recreated.

### Expected response

Opening
http://staging.localhost:__K3D_CLUSTER_PORT__/
in your browser should display:

> Hello from Modular DevOps Stack App!

This confirms that the app, Service, Flux reconciliation, and Ingress routing
are working. To verify an image promotion, compare the `digest` values in the
staging and production app overlays after the promotion has reconciled.
