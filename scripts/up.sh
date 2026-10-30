#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="$ROOT_DIR/.env"
SETUP_MARKER="$ROOT_DIR/source-control/provider/gitea/data/.setup-complete"

info() {
  printf '\033[1;34m[info]\033[0m %s\n' "$*"
}

error() {
  printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2
  exit 1
}

load_environment() {
  if [[ ! -f "$ENV_FILE" ]]; then
    error ".env not found. Copy .env.example to .env and configure it first."
  fi

  set -a
  # shellcheck disable=SC1091
  source "$ENV_FILE"
  set +a

  SSH_KEY="${FLUX_PRIVATE_KEY:-$HOME/.ssh/flux_deploy_key}"
}

ensure_shared_network() {
  docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 ||
    docker network create "$NETWORK_NAME" >/dev/null
}

compose_gitea() {
  docker compose -p "$STACK_NAME-providers" \
    -f ./stack/docker-compose.yaml \
    -f ./source-control/provider/gitea/docker-compose.yaml "$@"
}

gitea_is_ready() {
  local url="http://localhost:${GITEA_HTTP_PORT}/"
  if command -v curl >/dev/null 2>&1; then
    curl --fail --silent --output /dev/null "$url"
  else
    python3 -c 'import sys, urllib.request; response = urllib.request.urlopen(sys.argv[1], timeout=3); sys.exit(0 if response.status < 400 else 1)' "$url" >/dev/null 2>&1
  fi
}

ensure_flux_key() {
  if [[ ! -f "$SSH_KEY" ]]; then
    info "Generating Flux deploy key at $SSH_KEY"
    mkdir -p "$(dirname "$SSH_KEY")"
    ssh-keygen -t ed25519 -N "" -f "$SSH_KEY" >/dev/null
    chmod 644 "$SSH_KEY"
  fi

  if [[ ! -s "$SSH_KEY" || ! -s "${SSH_KEY}.pub" ]]; then
    error "Flux deploy key is incomplete. Check $SSH_KEY and ${SSH_KEY}.pub."
  fi
}

validate_first_run_settings() {
  if [[ -z "${GITEA_ADMIN_USER:-}" || "$GITEA_ADMIN_USER" == "your_gitea_username" ]]; then
    info "Set GITEA_ADMIN_USER in .env to the Gitea account username."
    return 1
  fi
  if [[ -z "${GITEA_CLIENT:-}" || "$GITEA_CLIENT" == "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" ]]; then
    info "Set GITEA_CLIENT in .env to the OAuth client ID created in Gitea."
    return 1
  fi
  if [[ -z "${GITEA_SECRET:-}" || "$GITEA_SECRET" == "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" ]]; then
    info "Set GITEA_SECRET in .env to the OAuth client secret created in Gitea."
    return 1
  fi
  if [[ -z "${GITOPS_BRANCH:-}" || -z "${GITOPS_REPO_URL:-}" ]]; then
    info "Set GITOPS_BRANCH and GITOPS_REPO_URL in .env."
    return 1
  fi
}

wait_for_gitops_repository() {
  local known_hosts
  local host_key
  known_hosts="$(mktemp)"
  host_key="$(mktemp)"
  chmod 600 "$known_hosts"
  chmod 600 "$host_key"

  info "Checking the GitOps repository and Flux deploy-key access..."
  if ! cp "$SSH_KEY" "$host_key"; then
    rm -f "$known_hosts" "$host_key"
    return 1
  fi

  if ! ssh-keyscan -p "$GITEA_SSH_PORT" localhost >"$known_hosts" 2>/dev/null ||
    [[ ! -s "$known_hosts" ]]; then
    rm -f "$known_hosts" "$host_key"
    return 1
  fi

  local local_gitops_url="ssh://git@localhost:${GITEA_SSH_PORT}/${STACK_NAME}/gitops.git"
  local ssh_command
  printf -v ssh_command \
    'ssh -i "%s" -o IdentitiesOnly=yes -o UserKnownHostsFile="%s" -o StrictHostKeyChecking=yes -p %s' \
    "$host_key" "$known_hosts" "$GITEA_SSH_PORT"

  local result=0
  GIT_SSH_COMMAND="$ssh_command" git ls-remote --exit-code "$local_gitops_url" \
    "refs/heads/${GITOPS_BRANCH}" >/dev/null || result=$?
  rm -f "$known_hosts" "$host_key"
  return "$result"
}

first_run_setup() {
  info "First-run setup: starting Gitea only."
  ensure_shared_network
  compose_gitea up -d scm
  ensure_flux_key

  info "Waiting for Gitea at http://localhost:${GITEA_HTTP_PORT}..."
  local attempt
  for attempt in {1..60}; do
    if gitea_is_ready; then
      break
    fi
    if [[ "$attempt" -eq 60 ]]; then
      compose_gitea logs --tail=50 scm >&2 || true
      error "Gitea did not become ready. Check its container logs and try again."
    fi
    sleep 2
  done

  printf '\n'
  info "Gitea is ready."
  info "Configure the admin account, and add empty 'app' and 'gitops' repositories."
  info "Add the Gitea admin username in .env."
  info "Add this public key to the 'gitops' repository as a write-enabled deploy key:"
  cat "${SSH_KEY}.pub"
  info "Create a Woodpecker OAuth application in Gitea, and put its client ID and secret in .env."
  info "Render and push the initial GitOps files before continuing."

  while true; do
    printf '\n'
    if ! read -r -p "When Gitea, .env, and the GitOps repository are ready, press Enter to continue (Ctrl-C to stop): "; then
      error "Setup paused. Rerun ./scripts/up.sh when you are ready to continue."
    fi

    load_environment
    if ! validate_first_run_settings; then
      info "Update .env, then press Enter to retry."
      continue
    fi

    if wait_for_gitops_repository; then
      break
    fi
    info "The configured GitOps branch is not accessible yet. Confirm the repository, deploy key, and branch, then press Enter to retry."
  done

  touch "$SETUP_MARKER"
  info "First-run setup verified. Starting the remaining stack components."
}

load_environment

if [[ ! -f "$SETUP_MARKER" ]]; then
  first_run_setup
fi

ensure_shared_network

# Start the full stack after first-run Gitea setup is complete.
docker compose -p "$STACK_NAME-providers" \
  -f ./stack/docker-compose.yaml \
  -f ./registry/provider/local/docker-compose.yaml \
  -f ./source-control/provider/gitea/docker-compose.yaml \
  -f ./ci/provider/woodpecker/docker-compose.yaml \
  up -d

# Create k3d cluster using its configured definition
if ! k3d cluster list "$K3D_CLUSTER_NAME" >/dev/null 2>&1; then
  k3d cluster create --config ./cluster/provider/k3d/cluster.yaml
fi

# Install and configure ingress-nginx for the k3d cluster
./ingress/provider/nginx/install.sh
./cluster/provider/k3d/configure-ingress-nginx.sh
./ingress/provider/nginx/wait-ready.sh
./ingress/provider/nginx/enable-metrics.sh

# Bootstrap Flux (idempotent)
./gitops/provider/flux/bootstrap.sh
