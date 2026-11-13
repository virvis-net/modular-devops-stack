#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f .env ]]; then
  printf 'Missing .env; copy .env.example to .env first.\n' >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

: "${STACK_NAME:?STACK_NAME must be set in .env}"
: "${K3D_CLUSTER_NAME:?K3D_CLUSTER_NAME must be set in .env}"
: "${NETWORK_NAME:?NETWORK_NAME must be set in .env}"
START_LOCAL_PROVIDERS="${START_LOCAL_PROVIDERS:-true}"
case "$START_LOCAL_PROVIDERS" in
  true|false) ;;
  *)
    printf 'START_LOCAL_PROVIDERS must be true or false.\n' >&2
    exit 1
    ;;
esac

if k3d cluster list "$K3D_CLUSTER_NAME" >/dev/null 2>&1; then
  printf 'Stopping k3d cluster "%s" without deleting it...\n' "$K3D_CLUSTER_NAME"
  k3d cluster stop "$K3D_CLUSTER_NAME"
else
  printf 'Cluster "%s" does not exist; skipping cluster stop.\n' "$K3D_CLUSTER_NAME"
fi

if [[ "$START_LOCAL_PROVIDERS" == true ]]; then
  docker compose -p "$STACK_NAME-providers" \
    -f ./stack/docker-compose.yaml \
    -f ./stack/registry/provider/local/docker-compose.yaml \
    -f ./stack/source-control/provider/gitea/docker-compose.yaml \
    -f ./stack/ci/provider/woodpecker/docker-compose.yaml \
    stop
else
  printf 'Leaving shared Gitea, Woodpecker, registry, and Docker network running.\n'
fi
