#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s [go|laravel|vue] [--app-only|--gitops-only]\n' "$0"
}

APP_TEMPLATE=go
RENDER_TARGET=both
APP_TEMPLATE_SET=false
RENDER_TARGET_SET=false

for argument in "$@"; do
  case "$argument" in
    go|laravel|vue)
      if [ "$APP_TEMPLATE_SET" = true ]; then
        usage >&2
        exit 2
      fi
      APP_TEMPLATE="$argument"
      APP_TEMPLATE_SET=true
      ;;
    --app-only|--gitops-only)
      if [ "$RENDER_TARGET_SET" = true ]; then
        usage >&2
        exit 2
      fi
      RENDER_TARGET="${argument#--}"
      RENDER_TARGET_SET=true
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

RENDER_ARGUMENTS=(workspace/app workspace/gitops "$APP_TEMPLATE")
if [ "$RENDER_TARGET" != both ]; then
  RENDER_ARGUMENTS+=("--$RENDER_TARGET")
fi

if [ ! -f .env ]; then
  printf 'Missing .env; copy .env.example to .env first.\n' >&2
  exit 1
fi

# Load settings without exporting unrelated secrets to the renderer.
source .env

GITEA_ORG="${GITEA_ORG:-}"
REGISTRY_PORT="${REGISTRY_PORT:-}"
K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-}"
K3D_CLUSTER_PORT="${K3D_CLUSTER_PORT:-}"
GITOPS_REPO_URL="${GITOPS_REPO_URL:-}"
OTEL_CENTRAL_INGEST_ENABLED="${OTEL_CENTRAL_INGEST_ENABLED:-false}"
OTEL_CENTRAL_EXPORT_MODE="${OTEL_CENTRAL_EXPORT_MODE:-local}"
OTEL_CENTRAL_COLLECTOR_ENDPOINT="${OTEL_CENTRAL_COLLECTOR_ENDPOINT:-}"

GITEA_ORG="$GITEA_ORG" \
REGISTRY_PORT="$REGISTRY_PORT" \
K3D_CLUSTER_NAME="$K3D_CLUSTER_NAME" \
K3D_CLUSTER_PORT="$K3D_CLUSTER_PORT" \
GITOPS_REPO_URL="$GITOPS_REPO_URL" \
OTEL_CENTRAL_INGEST_ENABLED="$OTEL_CENTRAL_INGEST_ENABLED" \
OTEL_CENTRAL_EXPORT_MODE="$OTEL_CENTRAL_EXPORT_MODE" \
OTEL_CENTRAL_COLLECTOR_ENDPOINT="$OTEL_CENTRAL_COLLECTOR_ENDPOINT" \
python3 ./scripts/render-templates.py \
  "${RENDER_ARGUMENTS[@]}"
