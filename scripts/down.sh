#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  printf 'Usage: %s [--yes]\n' "$0"
  printf "Delete this checkout's k3d cluster and stop its local providers.\n"
  printf 'Use --yes to skip the interactive cluster-name confirmation.\n'
}

SKIP_CONFIRMATION=false
while (($#)); do
  case "$1" in
    --yes|-y)
      SKIP_CONFIRMATION=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

# Load environment variables from .env
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
else
  printf 'Missing .env; copy .env.example to .env first.\n' >&2
  exit 1
fi

: "${STACK_NAME:?STACK_NAME must be set in .env}"
: "${K3D_CLUSTER_NAME:?K3D_CLUSTER_NAME must be set in .env}"
: "${NETWORK_NAME:?NETWORK_NAME must be set in .env}"
START_LOCAL_PROVIDERS="${START_LOCAL_PROVIDERS:-true}"
case "$START_LOCAL_PROVIDERS" in
  true|false) ;;
  *)
    echo "START_LOCAL_PROVIDERS must be true or false." >&2
    exit 1
    ;;
esac

printf 'This will delete k3d cluster "%s" and its Kubernetes metadata.\n' "$K3D_CLUSTER_NAME"
printf "It will stop and remove provider containers when this checkout owns them; named data volumes are kept.\n"
if [[ "$START_LOCAL_PROVIDERS" == false ]]; then
  printf 'Shared Gitea, Woodpecker, registry, and their network will be left running.\n'
else
  printf 'The local Docker network is removed only if no containers remain attached.\n'
fi
printf 'The k3d storage volume is kept, but its data is not automatically reattached to a recreated cluster.\n'
if [[ "$SKIP_CONFIRMATION" != true ]]; then
  if [[ ! -t 0 ]]; then
    printf 'Refusing non-interactive teardown. Rerun with --yes if this deletion is intentional.\n' >&2
    exit 1
  fi
  read -r -p "Type '$K3D_CLUSTER_NAME' to continue: " confirmation || {
    printf 'Teardown cancelled.\n' >&2
    exit 1
  }
  if [[ "$confirmation" != "$K3D_CLUSTER_NAME" ]]; then
    printf 'Cluster name did not match; teardown cancelled.\n' >&2
    exit 1
  fi
fi

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

# Stop local providers only when this stack owns them.
if [[ "$START_LOCAL_PROVIDERS" == true ]]; then
  docker compose -p "$STACK_NAME-providers" \
    -f ./stack/docker-compose.yaml \
    -f ./stack/registry/provider/local/docker-compose.yaml \
    -f ./stack/source-control/provider/gitea/docker-compose.yaml \
    -f ./stack/ci/provider/woodpecker/docker-compose.yaml \
    down
else
  echo "Leaving shared Gitea, Woodpecker, registry, and Docker network running."
fi

# Remove the local network only when this stack owns the providers and no other
# stack remains attached to it.
if [[ "$START_LOCAL_PROVIDERS" == true ]] &&
  docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  attached_containers="$(docker network inspect --format '{{len .Containers}}' "$NETWORK_NAME")"
  if [[ "$attached_containers" == 0 ]]; then
    docker network rm "$NETWORK_NAME"
  else
    echo "Leaving Docker network $NETWORK_NAME in place; other containers remain attached."
  fi
fi
