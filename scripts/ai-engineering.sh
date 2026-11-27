#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  printf 'Usage: %s <up|down|logs|status>\n' "$0"
  printf 'Start or manage OpenHands and the optional containerized Ollama service.\n'
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
OPENHANDS_UID="${OPENHANDS_UID:-$(id -u)}"
OPENHANDS_GID="${OPENHANDS_GID:-$(id -g)}"
OLLAMA_PROVIDER="${OLLAMA_PROVIDER:-container}"
OLLAMA_IMAGE="${OLLAMA_IMAGE:-ollama/ollama:latest}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen3.6:latest}"
OLLAMA_CONTEXT_LENGTH="${OLLAMA_CONTEXT_LENGTH:-32768}"
GITEA_HTTP_PORT="${GITEA_HTTP_PORT:-3000}"
OPENHANDS_GITEA_TOKEN="${OPENHANDS_GITEA_TOKEN:-}"
case "$OLLAMA_PROVIDER" in
  native|container) ;;
  *) error "OLLAMA_PROVIDER must be native or container." ;;
esac

export OPENHANDS_PORT OPENHANDS_IMAGE OPENHANDS_UID OPENHANDS_GID
export OLLAMA_PROVIDER OLLAMA_IMAGE OLLAMA_MODEL OLLAMA_CONTEXT_LENGTH
export GITEA_HTTP_PORT OPENHANDS_GITEA_TOKEN

compose() {
  local profile_args=()
  if [[ "$OLLAMA_PROVIDER" == container ]]; then
    profile_args+=(--profile container-model)
  fi

  docker compose -p "${STACK_NAME}-ai-engineering" \
    "${profile_args[@]}" \
    -f ./stack/docker-compose.yaml \
    -f ./stack/model-host/provider/ollama/docker-compose.yaml \
    -f ./stack/ai-engineering/provider/openhands/docker-compose.yaml \
    -f ./stack/orchestration/provider/n8n/docker-compose.yaml \
    "$@"
}

wait_for_model_host() {
  local attempt
  for attempt in {1..60}; do
    if compose exec -T model-host ollama list >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  error "The model host did not become ready. Check its logs with '$0 logs'."
}

wait_for_workspace() {
  local attempt
  for attempt in {1..30}; do
    if compose exec -T coding-agent test -d ${WORKSPACE_DIRECTORY}/app/.git >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  error "OpenHands cannot see the Git checkout at ${WORKSPACE_DIRECTORY}/app. Check the Docker Desktop/WSL bind mount, then recreate the coding-agent container."
}

up() {
  if ! git -C ./workspace/app rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    error "workspace/app must be a Git clone before starting OpenHands."
  fi

  mkdir -p ./workspace/openhands
  if [[ ! -w ./workspace/openhands ]]; then
    error "workspace/openhands must be writable by the user running this script."
  fi

  docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 ||
    docker network create "$NETWORK_NAME" >/dev/null

  if [[ "$OLLAMA_PROVIDER" == native ]]; then
    docker compose -p "${STACK_NAME}-ai-engineering" \
      --profile container-model \
      -f ./stack/docker-compose.yaml \
      -f ./stack/model-host/provider/ollama/docker-compose.yaml \
      -f ./stack/ai-engineering/provider/openhands/docker-compose.yaml \
      -f ./stack/orchestration/provider/n8n/docker-compose.yaml \
      rm --stop --force model-host
  fi

  compose up -d

  if [[ "$OLLAMA_PROVIDER" == container ]]; then
    wait_for_model_host

    if ! compose exec -T model-host ollama list |
      awk -v model="$OLLAMA_MODEL" '$1 == model { found = 1 } END { exit !found }'; then
      compose exec -T model-host ollama pull "$OLLAMA_MODEL"
    fi
  else
    printf 'Using native Ollama. Configure OpenHands with http://host.docker.internal:11434\n'
  fi

  wait_for_workspace

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
    if [[ "$OLLAMA_PROVIDER" == native ]]; then
      docker compose -p "${STACK_NAME}-ai-engineering" \
        --profile container-model \
        -f ./stack/docker-compose.yaml \
        -f ./stack/model-host/provider/ollama/docker-compose.yaml \
        -f ./stack/ai-engineering/provider/openhands/docker-compose.yaml \
        -f ./stack/orchestration/provider/n8n/docker-compose.yaml \
        rm --stop --force model-host
    fi
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
