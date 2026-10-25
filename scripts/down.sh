#!/bin/bash
set -e

# Load environment variables from .env
if [ -f .env ]; then
  set -a && source .env && set +a
fi

# Tear down Flux (idempotent)
./gitops/provider/flux/teardown.sh

# Remove ingress-nginx (idempotent)
echo "Removing ingress-nginx..."
kubectl delete namespace ingress-nginx --ignore-not-found=true
kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml --ignore-not-found=true || true

# Delete k3d cluster
k3d cluster delete "$K3D_CLUSTER_NAME"

# Stop the whole stack
docker compose -p "$STACK_NAME-providers" \
  -f ./stack/docker-compose.yaml \
  -f ./registry/provider/local/docker-compose.yaml \
  -f ./source-control/provider/gitea/docker-compose.yaml \
  -f ./ci/provider/woodpecker/docker-compose.yaml \
  down

# Remove shared network
docker network rm "$NETWORK_NAME"
