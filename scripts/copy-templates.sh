#!/usr/bin/env bash
set -euo pipefail

if [ ! -f .env ]; then
  printf 'Missing .env; copy .env.example to .env first.\n' >&2
  exit 1
fi

APP_TEMPLATE="${1:-go}"
if [ "$#" -gt 1 ]; then
  printf 'Usage: %s [go|laravel]\n' "$0" >&2
  exit 2
fi

case "$APP_TEMPLATE" in
  go|laravel) ;;
  *)
    printf 'Usage: %s [go|laravel]\n' "$0" >&2
    exit 2
    ;;
esac

# Load settings without exporting unrelated secrets to the renderer.
source .env

GITEA_ORG="${GITEA_ORG:-}"
REGISTRY_PORT="${REGISTRY_PORT:-}"
K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-}"
K3D_CLUSTER_PORT="${K3D_CLUSTER_PORT:-}"
GITOPS_REPO_URL="${GITOPS_REPO_URL:-}"

GITEA_ORG="$GITEA_ORG" \
REGISTRY_PORT="$REGISTRY_PORT" \
K3D_CLUSTER_NAME="$K3D_CLUSTER_NAME" \
K3D_CLUSTER_PORT="$K3D_CLUSTER_PORT" \
GITOPS_REPO_URL="$GITOPS_REPO_URL" \
python3 ./scripts/render-templates.py workspace/app workspace/gitops "$APP_TEMPLATE"
