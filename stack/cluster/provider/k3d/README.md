# k3d Provider (Cluster Layer)

This folder contains the k3d implementation of the cluster provider.

## Components
- cluster.yaml — declarative cluster definition
- registries.yaml — configures k3d nodes to pull from the local HTTP registry
- `<K3D_CLUSTER_NAME>-storage` Docker volume — persistent local-path storage
  mounted on every k3d node
- `cluster.yaml` includes a commented bind-mount alternative under `data/` for
  users who prefer to inspect files directly

The named volume persists after cluster deletion. Kubernetes metadata is not
restored with a new cluster, so data remaining in the volume is not
automatically reattached. Remove it with `docker volume rm` only when you
intend to delete its contents. The named-volume and bind-mount options are
independent; switching does not copy or migrate data, and the cluster must be
recreated to change its storage mount.

The registry mirror points to `http://registry:5000`, the registry service
name and port on the shared Docker network. k3d copies this configuration into
the nodes when it creates the cluster. If the registry config changes later,
existing nodes need to be updated or recreated before they use the new setting.

`configure-ingress-nginx.sh` applies the k3d-specific ingress adjustment. The
nginx provider installs and removes the controller; this script clears its
host-port bindings because k3s LoadBalancer pods use the cluster node ports in
this setup. The k3d load balancer maps host ports 80 and 443 into the cluster.
