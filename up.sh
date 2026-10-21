#!/bin/bash

# Ensure shared network exists
docker network inspect mds-network >/dev/null 2>&1 || docker network create mds-network

# Start the whole stack
docker compose -p mds-providers \
  -f stack/docker-compose.yaml \
  -f registry/provider/local/docker-compose.yaml \
  -f source-control/provider/gitea/docker-compose.yaml \
  -f ci/provider/woodpecker/docker-compose.yaml \
  up -d

# Create k3d cluster using your config
if ! k3d cluster list | grep -q mds-cluster; then
  k3d cluster create --config cluster/provider/k3d/cluster.yaml
fi
