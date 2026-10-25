# k3d Provider (Cluster Layer)

This folder contains the k3d implementation of the cluster provider.

## Components
- cluster.yaml — declarative cluster definition
- registries.yaml — configures k3d nodes to pull from the local HTTP registry
- data/ — persistent storage for k3s runtime state

The registry mirror points to `http://registry:5000`, the registry's service
name and port on the shared Docker network. This file is consumed directly by
k3d, so its mirror endpoint must be a literal URL rather than an environment
variable reference.

## Neutral Architecture
The top-level folder `cluster/` represents the domain.
The `provider/` folder contains the current implementation.
This allows swapping k3d for kind, minikube, microk8s, or any other provider without changing the domain structure.
