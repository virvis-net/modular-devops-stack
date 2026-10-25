# k3d Provider (Cluster Layer)

This folder contains the k3d implementation of the cluster provider.

## Components
- cluster.yaml — declarative cluster definition
- registries.yaml — configures k3d nodes to pull from the local HTTP registry
- data/ — persistent storage for k3s runtime state

The registry mirror points to `http://registry:5000`, the registry service
name and port on the shared Docker network. k3d copies this configuration into
the nodes when it creates the cluster. If the registry config changes later,
existing nodes need to be updated or recreated before they use the new setting.

The ingress controller is installed by `scripts/up.sh`. Its host-port bindings
are removed because k3s LoadBalancer pods use the cluster node ports in this
setup; the k3d load balancer maps host ports 80 and 443 into the cluster.
