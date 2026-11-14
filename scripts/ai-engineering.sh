#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  printf 'Usage: %s <up|down|logs|status>\n' "$0"
  printf 'Start or manage the optional local Ollama and OpenHands services.\n'
}

error() {
  printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2
  exit 1
}

if (($# == 1)) && [[ "$1" == "--help" || "$1" == "-h" ]]; then
  usage
  exit 0
fi

if (($# != 1)); then
  usage >&2
  exit 2
fi

if [[ ! -f .env ]]; then
  error ".env not found. Copy .env.example to .env and configure it first."
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

: "${STACK_NAME:?STACK_NAME must be set in .env}"
: "${NETWORK_NAME:?NETWORK_NAME must be set in .env}"

OPENHANDS_PORT="${OPENHANDS_PORT:-8001}"
OPENHANDS_IMAGE="${OPENHANDS_IMAGE:-ghcr.io/openhands/agent-canvas:latest}"
OLLAMA_IMAGE="${OLLAMA_IMAGE:-ollama/ollama:latest}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5-coder:7b}"
OLLAMA_CONTEXT_LENGTH="${OLLAMA_CONTEXT_LENGTH:-32768}"
GITEA_HTTP_PORT="${GITEA_HTTP_PORT:-3000}"
OPENHANDS_GITEA_USER="${OPENHANDS_GITEA_USER:-}"
OPENHANDS_GITEA_TOKEN="${OPENHANDS_GITEA_TOKEN:-}"
export OPENHANDS_PORT OPENHANDS_IMAGE OLLAMA_IMAGE OLLAMA_MODEL
export OLLAMA_CONTEXT_LENGTH GITEA_HTTP_PORT OPENHANDS_GITEA_USER OPENHANDS_GITEA_TOKEN

compose() {
  docker compose -p "${STACK_NAME}-ai-engineering" \
    -f ./stack/docker-compose.yaml \
    -f ./stack/model-host/provider/ollama/docker-compose.yaml \
    -f ./stack/ai-engineering/provider/openhands/docker-compose.yaml "$@"
}

wait_for_ollama() {
  local attempt
  for attempt in {1..60}; do
    if compose exec -T ollama ollama list >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  error "Ollama did not become ready. Check its logs with '$0 logs'."
}

up() {
  if [[ -n "$OPENHANDS_GITEA_TOKEN" && -z "$OPENHANDS_GITEA_USER" ]]; then
    error "Set OPENHANDS_GITEA_USER in .env to the account that owns OPENHANDS_GITEA_TOKEN."
  fi

  if ! git -C ./workspace/app rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    error "workspace/app must be a Git clone before starting OpenHands."
  fi

  docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 ||
    docker network create "$NETWORK_NAME" >/dev/null

  compose up -d
  wait_for_ollama

  if ! compose exec -T ollama ollama list |
    awk -v model="$OLLAMA_MODEL" '$1 == model { found = 1 } END { exit !found }'; then
    compose exec -T ollama ollama pull "$OLLAMA_MODEL"
  fi

  printf 'OpenHands is available at http://localhost:%s/canvas\n' "$OPENHANDS_PORT"
  if [[ -z "$OPENHANDS_GITEA_TOKEN" ]]; then
    printf 'Set OPENHANDS_GITEA_TOKEN in .env to let the agent push branches and open Gitea PRs.\n'
  fi
}

case "$1" in
  up)
    up
    ;;
  down)
    compose down
    ;;
  logs)
    compose logs -f
    ;;
  status)
    compose ps
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
