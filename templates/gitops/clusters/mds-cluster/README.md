# mds-cluster

This folder defines the desired state for the `mds-cluster` Kubernetes
cluster. The root Kustomization applies resources to the `default` namespace
and includes the cluster-specific app resources.

Flux reconciles the `kustomization.yaml` here, which includes the app overlay.

## Accessing the App

Once Flux has reconciled the GitOps repository and the app Pod is Ready, the
application is reachable through ingress-nginx.

### URL
You can access the app at:

http://localhost/

### How it works

- The app container listens internally on port **8080**.
- The Kubernetes Service exposes the app on port **80** inside the cluster.
- The Ingress routes external traffic from `http://localhost/` to the Service.
- K3d’s load balancer maps host port **80** to the cluster’s Ingress controller.

### Verifying the deployment

You can confirm the app is running with:

```bash
kubectl get deployments -n default
kubectl get svc -n default
kubectl get ingress -n default
kubectl get pods -n default
```

You should see:
- A Deployment named app
- A Service named app exposing port 80
- An Ingress named app routing / to the Service

### Expected response

Opening http://localhost/ in your browser should display:

> Hello from Modular DevOps Stack App!

This confirms that the app, Service, Flux reconciliation, and Ingress routing
are working. To verify a code-to-deployment update, push a commit to the app
repository and check that Woodpecker updates the GitOps image tag.
