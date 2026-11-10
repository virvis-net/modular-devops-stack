#!/bin/bash
set -e

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Load environment variables from .env
if [ -f .env ]; then
  set -a && source .env && set +a
fi

: "${STACK_NAME:?STACK_NAME must be set in .env}"
: "${K3D_CLUSTER_NAME:?K3D_CLUSTER_NAME must be set in .env}"
: "${NETWORK_NAME:?NETWORK_NAME must be set in .env}"

# Tear down cluster resources only when the cluster exists
if k3d cluster list "$K3D_CLUSTER_NAME" >/dev/null 2>&1; then
  KUBECTL_CONTEXT="k3d-${K3D_CLUSTER_NAME}"

  # Use this checkout's cluster explicitly. Avoid changing the user's global
  # current context, which may point at the other stack.
  if kubectl --context "$KUBECTL_CONTEXT" get nodes --request-timeout=5s >/dev/null 2>&1; then
    # Tear down Flux (best effort; deleting the cluster below is authoritative).
    if ! KUBECTL_CONTEXT="$KUBECTL_CONTEXT" ./stack/gitops/provider/flux/teardown.sh; then
      echo "Warning: Flux cleanup failed for context $KUBECTL_CONTEXT; continuing with cluster deletion." >&2
    fi

    # Remove ingress-nginx (best effort; all resources go with the cluster).
    if ! KUBECTL_CONTEXT="$KUBECTL_CONTEXT" ./stack/ingress/provider/nginx/uninstall.sh; then
      echo "Warning: ingress-nginx cleanup failed for context $KUBECTL_CONTEXT; continuing with cluster deletion." >&2
    fi
  else
    echo "Warning: Kubernetes API for $KUBECTL_CONTEXT is unavailable; skipping resource cleanup and deleting the cluster directly." >&2
  fi

  # Cluster deletion does not depend on kubectl's current context or API health.
  k3d cluster delete "$K3D_CLUSTER_NAME"
else
  echo "Cluster \"$K3D_CLUSTER_NAME\" does not exist; skipping Kubernetes cleanup."
fi

# Stop the whole stack
docker compose -p "$STACK_NAME-providers" \
  -f ./stack/docker-compose.yaml \
  -f ./stack/registry/provider/local/docker-compose.yaml \
  -f ./stack/source-control/provider/gitea/docker-compose.yaml \
  -f ./stack/ci/provider/woodpecker/docker-compose.yaml \
  down

# Remove shared network if it exists
if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  docker network rm "$NETWORK_NAME"
fi
