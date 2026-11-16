#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  printf 'Usage: %s <up|down|logs|status|gpu-info>\n' "$0"
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
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen3.5:latest}"
OLLAMA_CONTEXT_LENGTH="${OLLAMA_CONTEXT_LENGTH:-32768}"
OLLAMA_WSL_VULKAN="${OLLAMA_WSL_VULKAN:-false}"
GITEA_HTTP_PORT="${GITEA_HTTP_PORT:-3000}"
OPENHANDS_GITEA_TOKEN="${OPENHANDS_GITEA_TOKEN:-}"
export OPENHANDS_PORT OPENHANDS_IMAGE OLLAMA_IMAGE OLLAMA_MODEL
export OLLAMA_CONTEXT_LENGTH OLLAMA_WSL_VULKAN GITEA_HTTP_PORT OPENHANDS_GITEA_TOKEN

case "$OLLAMA_WSL_VULKAN" in
  true|false) ;;
  *) error "OLLAMA_WSL_VULKAN must be true or false." ;;
esac

if [[ "$OLLAMA_WSL_VULKAN" == true ]]; then
  [[ -c /dev/dxg ]] || error "WSL Vulkan is enabled, but /dev/dxg is not available."
  [[ -d /dev/dri ]] || error "WSL Vulkan is enabled, but /dev/dri is not available."
  [[ -d /usr/lib/wsl ]] || error "WSL Vulkan is enabled, but /usr/lib/wsl is not available."

  video_device="$(find /dev/dri -maxdepth 1 -type c -name 'card*' -print -quit)"
  render_device="$(find /dev/dri -maxdepth 1 -type c -name 'renderD*' -print -quit)"
  [[ -n "$video_device" ]] || error "No WSL /dev/dri card device was found."
  [[ -n "$render_device" ]] || error "No WSL /dev/dri render device was found."
  OLLAMA_VIDEO_GID="$(stat -c '%g' "$video_device")"
  OLLAMA_RENDER_GID="$(stat -c '%g' "$render_device")"
  OLLAMA_DXG_GID="$(stat -c '%g' /dev/dxg)"
  export OLLAMA_VIDEO_GID OLLAMA_RENDER_GID OLLAMA_DXG_GID
fi

COMPOSE_FILES=(
  -f ./stack/docker-compose.yaml
  -f ./stack/model-host/provider/ollama/docker-compose.yaml
  -f ./stack/ai-engineering/provider/openhands/docker-compose.yaml
)
if [[ "$OLLAMA_WSL_VULKAN" == true ]]; then
  COMPOSE_FILES+=(-f ./stack/model-host/provider/ollama/docker-compose.wsl-vulkan.yaml)
fi

compose() {
  docker compose -p "${STACK_NAME}-ai-engineering" "${COMPOSE_FILES[@]}" "$@"
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

up() {
  if ! git -C ./workspace/app rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    error "workspace/app must be a Git clone before starting OpenHands."
  fi

  docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 ||
    docker network create "$NETWORK_NAME" >/dev/null

  compose up -d --build
  wait_for_model_host

  if ! compose exec -T model-host ollama list |
    awk -v model="$OLLAMA_MODEL" '$1 == model { found = 1 } END { exit !found }'; then
    compose exec -T model-host ollama pull "$OLLAMA_MODEL"
  fi

  printf 'OpenHands is available at http://localhost:%s/canvas\n' "$OPENHANDS_PORT"
  if [[ -z "$OPENHANDS_GITEA_TOKEN" ]]; then
    printf 'Set OPENHANDS_GITEA_TOKEN in .env to let the agent push branches and open Gitea PRs.\n'
  fi
  if [[ "$OLLAMA_WSL_VULKAN" == true ]]; then
    printf 'WSL Vulkan is enabled. Check it with: %s gpu-info\n' "$0"
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
  gpu-info)
    compose exec -T model-host vulkaninfo --summary
    printf '\nOllama model processing:\n'
    compose exec -T model-host ollama ps
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
