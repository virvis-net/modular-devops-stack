#!/bin/bash
set -e

# Load environment variables from .env
if [ -f .env ]; then
  set -a && source .env && set +a
fi

# Tear down Flux (idempotent)
./gitops/provider/flux/teardown.sh

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
