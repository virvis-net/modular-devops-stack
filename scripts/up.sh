#!/bin/bash
set -e

# Load environment variables from .env
if [ -f .env ]; then
  set -a && source .env && set +a
fi

# Ensure shared network exists
docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 || docker network create "$NETWORK_NAME"

# Start the whole stack
docker compose -p "$STACK_NAME-providers" \
  -f ./stack/docker-compose.yaml \
  -f ./registry/provider/local/docker-compose.yaml \
  -f ./source-control/provider/gitea/docker-compose.yaml \
  -f ./ci/provider/woodpecker/docker-compose.yaml \
  up -d

# Create k3d cluster using your config
if ! k3d cluster list | grep -q "$K3D_CLUSTER_NAME"; then
  k3d cluster create --config ./cluster/provider/k3d/cluster.yaml
fi

# Install and configure ingress-nginx for the k3d cluster
./ingress/provider/nginx/install.sh
./cluster/provider/k3d/configure-ingress-nginx.sh
./ingress/provider/nginx/wait-ready.sh

# Bootstrap Flux (idempotent)
./gitops/provider/flux/bootstrap.sh
