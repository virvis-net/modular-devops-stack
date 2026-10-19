# k3d Provider (Cluster Layer)

This folder contains the k3d implementation of the cluster provider.

## Components
- cluster.yaml — declarative cluster definition
- data/ — persistent storage for k3s runtime state

## Neutral Architecture
The top-level folder `cluster/` represents the domain.
The `provider/` folder contains the current implementation.
This allows swapping k3d for kind, minikube, microk8s, or any other provider without changing the domain structure.
