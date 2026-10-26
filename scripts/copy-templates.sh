#!/usr/bin/env bash
set -euo pipefail

if [ ! -f .env ]; then
  printf 'Missing .env; copy .env.example to .env first.\n' >&2
  exit 1
fi

# Load settings without exporting unrelated secrets to the renderer.
source .env

STACK_NAME="${STACK_NAME:-}"
REGISTRY_PORT="${REGISTRY_PORT:-}"
K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-}"
K3D_CLUSTER_PORT="${K3D_CLUSTER_PORT:-}"
GITOPS_REPO_URL="${GITOPS_REPO_URL:-}"

STACK_NAME="$STACK_NAME" \
REGISTRY_PORT="$REGISTRY_PORT" \
K3D_CLUSTER_NAME="$K3D_CLUSTER_NAME" \
K3D_CLUSTER_PORT="$K3D_CLUSTER_PORT" \
GITOPS_REPO_URL="$GITOPS_REPO_URL" \
python3 ./scripts/render-templates.py workspace/app workspace/gitops
