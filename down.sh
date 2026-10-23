#!/bin/bash

# Tear down Flux (idempotent)
./scripts/teardown-flux.sh

# Delete k3d cluster
k3d cluster delete mds-cluster

# Stop the whole stack
docker compose -p mds-providers \
  -f stack/docker-compose.yaml \
  -f registry/provider/local/docker-compose.yaml \
  -f source-control/provider/gitea/docker-compose.yaml \
  -f ci/provider/woodpecker/docker-compose.yaml \
  down

# Remove shared network
docker network rm mds-network
