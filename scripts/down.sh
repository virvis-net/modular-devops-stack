#!/bin/bash
set -e

# Load environment variables from .env
if [ -f .env ]; then
  set -a && source .env && set +a
fi

# Tear down cluster resources only when the cluster exists
if k3d cluster list "$K3D_CLUSTER_NAME" >/dev/null 2>&1; then
  # Tear down Flux (idempotent)
  ./gitops/provider/flux/teardown.sh

  # Remove ingress-nginx (idempotent)
  ./ingress/provider/nginx/uninstall.sh

  # Delete k3d cluster
  k3d cluster delete "$K3D_CLUSTER_NAME"
else
  echo "Cluster \"$K3D_CLUSTER_NAME\" does not exist; skipping Kubernetes cleanup."
fi

# Stop the whole stack
docker compose -p "$STACK_NAME-providers" \
  -f ./stack/docker-compose.yaml \
  -f ./registry/provider/local/docker-compose.yaml \
  -f ./source-control/provider/gitea/docker-compose.yaml \
  -f ./ci/provider/woodpecker/docker-compose.yaml \
  down

# Remove shared network if it exists
if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  docker network rm "$NETWORK_NAME"
fi
