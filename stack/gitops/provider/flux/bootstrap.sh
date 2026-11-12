#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../../../.." && pwd)"

# --- Configurable values (override with env vars) ---
GIT_URL="${GITOPS_REPO_URL:-ssh://git@host.docker.internal:2222/mds/gitops.git}"
GIT_BRANCH="${GITOPS_BRANCH:-main}"
GIT_PATH="${GITOPS_PATH:-clusters/mds-cluster}"
STACK_NAME="${STACK_NAME:-mds}"
NETWORK_NAME="${NETWORK_NAME:-${STACK_NAME}-network}"
SSH_DOMAIN="${GITEA_SSH_DOMAIN:-host.docker.internal}"
SSH_PORT="${GITEA_SSH_PORT:-2222}"
SSH_STATE_DIR="$ROOT_DIR/stack/.state/ssh"
SSH_KEY="${FLUX_PRIVATE_KEY:-$SSH_STATE_DIR/flux_deploy_key}"
KNOWN_HOSTS="$SSH_STATE_DIR/known_hosts.flux"
FLUX_IMAGE="${FLUX_IMAGE:-ghcr.io/fluxcd/flux-cli:v2.3.0}"
FLUX_BOOTSTRAP_TIMEOUT="${FLUX_BOOTSTRAP_TIMEOUT:-15m}"
KUBE_CONFIG_SRC="${KUBE_DIR:-$HOME/.kube}/config"
FLUX_KUBECONFIG="$HOME/.kube/config.flux"

# --- Helpers ---
info(){ printf "\033[1;34m[info]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
err(){ printf "\033[1;31m[error]\033[0m %s\n" "$*"; exit 1; }

# Basic prechecks
if ! command -v kubectl >/dev/null 2>&1; then
  err "kubectl not found in PATH. Install kubectl before bootstrapping Flux."
fi
if ! command -v docker >/dev/null 2>&1; then
  # Fallback: apply pre-generated Flux manifests
  if [ -d "./clusters/mds-cluster/flux-manifests" ]; then
    info "Docker not available. Applying pre-generated Flux manifests"
    kubectl apply -k clusters/mds-cluster/flux-manifests
    kubectl get pods -n flux-system || true
    exit 0
  fi
  err "Cannot bootstrap Flux: docker not found and no flux-manifests present."
fi

# Wait for k8s cluster to be ready (best effort)
info "Waiting for Kubernetes nodes to be Ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s >/dev/null 2>&1 || true

# Wait for Source Control SSH to be reachable
info "Waiting for Source Control SSH on localhost:${SSH_PORT}..."
for i in $(seq 1 30); do
  if nc -z localhost "$SSH_PORT" >/dev/null 2>&1; then
    info "Source Control SSH reachable"
    break
  fi
  sleep 2
done

# Pods cannot always reach Docker-published host ports. When the Git URL points
# to this stack's Gitea, use its address on the shared Docker network instead.
GITEA_CONTAINER_IP=""
FLUX_DOCKER_NETWORK=bridge
if [[ "$GIT_URL" == "ssh://git@${SSH_DOMAIN}:${SSH_PORT}/"* ]]; then
  mapfile -t gitea_containers < <(docker ps -q \
    --filter "network=${NETWORK_NAME}" \
    --filter "label=com.docker.compose.service=scm")
  if [[ "${#gitea_containers[@]}" -ne 1 ]]; then
    err "Expected exactly one running Gitea container on Docker network $NETWORK_NAME; found ${#gitea_containers[@]}."
  fi
  if ! GITEA_CONTAINER_IP="$(docker inspect --format \
    "{{with index .NetworkSettings.Networks \"$NETWORK_NAME\"}}{{.IPAddress}}{{end}}" \
    "${gitea_containers[0]}")"; then
    err "Could not inspect the Gitea container's address on Docker network $NETWORK_NAME."
  fi
  if [[ -z "$GITEA_CONTAINER_IP" ]]; then
    err "Gitea is not attached to Docker network $NETWORK_NAME."
  fi

  GIT_URL="ssh://git@${GITEA_CONTAINER_IP}${GIT_URL#ssh://git@${SSH_DOMAIN}:${SSH_PORT}}"
  FLUX_DOCKER_NETWORK="$NETWORK_NAME"
  info "Using Gitea's Docker network address for Flux: ${GITEA_CONTAINER_IP}:22"
fi

# Ensure SSH key exists (generate if missing)
if [ ! -f "$SSH_KEY" ]; then
  info "Generating Flux deploy key at $SSH_KEY"
  mkdir -p "$(dirname "$SSH_KEY")"
  ssh-keygen -t ed25519 -N "" -f "$SSH_KEY" >/dev/null
  info "Public key (add this as a deploy key with write access to $GIT_URL):"
  cat "${SSH_KEY}.pub"
  read -p "Press Enter after adding the key to Gitea..." || true
  chmod 644 ${SSH_KEY}
fi

# If the Flux-specific known_hosts does not contain the Gitea entry, add it
KNOWN_HOSTS_ENTRY="[${SSH_DOMAIN}]:${SSH_PORT}"
if [[ -n "$GITEA_CONTAINER_IP" ]]; then
  KNOWN_HOSTS_ENTRY="$GITEA_CONTAINER_IP"
fi
if [ ! -f "$KNOWN_HOSTS" ] || ! ssh-keygen -F "$KNOWN_HOSTS_ENTRY" -f "$KNOWN_HOSTS" >/dev/null 2>&1; then
  mkdir -p "$(dirname "$KNOWN_HOSTS")"
  info "Adding Gitea host key to Flux-specific known_hosts at $KNOWN_HOSTS"
  TMP_KEYSCAN=$(ssh-keyscan -p "$SSH_PORT" localhost 2>/dev/null || true)
  if [ -n "$TMP_KEYSCAN" ]; then
    if [[ -n "$GITEA_CONTAINER_IP" ]]; then
      echo "$TMP_KEYSCAN" | sed "s/\[localhost\]:${SSH_PORT}/${GITEA_CONTAINER_IP}/" > "$KNOWN_HOSTS"
    else
      echo "$TMP_KEYSCAN" | sed "s/\[localhost\]:${SSH_PORT}/\[${SSH_DOMAIN}\]:${SSH_PORT}/" > "$KNOWN_HOSTS"
    fi
  else
    if [[ -n "$GITEA_CONTAINER_IP" ]]; then
      err "Could not retrieve Gitea's SSH host key from localhost:${SSH_PORT}."
    fi
    warn "Could not retrieve SSH key from localhost:${SSH_PORT}; Flux SSH may fail."
  fi
  chmod 644 "$KNOWN_HOSTS"
fi

# Create readable kubeconfig copy for Flux
if [ -f "$KUBE_CONFIG_SRC" ]; then
  info "Preparing readable kubeconfig copy for Flux at $FLUX_KUBECONFIG"
  # Rewrite server host to host.docker.internal
  sed -E 's@(server: https?://)(0\.0\.0\.0|127\.0\.0\.1|localhost)@\1host.docker.internal@g' "$KUBE_CONFIG_SRC" \
    | sed '/certificate-authority-data/d' \
    | sed '/certificate-authority:/d' \
    | sed '/insecure-skip-tls-verify/d' \
    | sed '/cluster:/a\    insecure-skip-tls-verify: true' \
    > "$FLUX_KUBECONFIG"
  # Fix permissions so root inside container can read it
  chmod 644 "$FLUX_KUBECONFIG"
  info "Flux kubeconfig server: $(grep 'server:' -m1 "$FLUX_KUBECONFIG" | awk '{print $2}')"
else
  warn "No kubeconfig found at $KUBE_CONFIG_SRC; containerized bootstrap will likely fail."
fi

# Containerized flux CLI
info "Bootstrapping Flux using containerized CLI image $FLUX_IMAGE"
bootstrap_output="$(mktemp)"
trap 'rm -f "$bootstrap_output"' EXIT

for attempt in 1 2 3; do
  if docker run --rm --network "$FLUX_DOCKER_NETWORK" \
    --add-host="${GITEA_SSH_DOMAIN}:host-gateway" \
    -v "$FLUX_KUBECONFIG:/flux-conf/kube-config:ro" \
    -v "$SSH_KEY:/flux-conf/ssh-private_key:ro" \
    -v "$KNOWN_HOSTS:/flux-conf/ssh-known_hosts:ro" \
    -e KUBECONFIG=/flux-conf/kube-config \
    -e GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/flux-conf/ssh-known_hosts" \
    -e SSH_KNOWN_HOSTS=/flux-conf/ssh-known_hosts \
    "$FLUX_IMAGE" \
    bootstrap git \
      --timeout="$FLUX_BOOTSTRAP_TIMEOUT" \
      --url="$GIT_URL" \
      --branch="$GIT_BRANCH" \
      --path="$GIT_PATH" \
      --private-key-file=/flux-conf/ssh-private_key \
      --components-extra=image-reflector-controller,image-automation-controller \
      --silent 2>&1 | tee "$bootstrap_output"; then
    break
  else
    status=$?
    if [[ "$attempt" -eq 3 ]] ||
      ! grep -Eqi 'connection refused|no route to host|network is unreachable' "$bootstrap_output"; then
      exit "$status"
    fi
    warn "Git is temporarily unreachable from the cluster; retrying Flux bootstrap in 10 seconds (attempt $((attempt + 1))/3)."
    sleep 10
  fi
done

info "Flux bootstrap (container) finished. Verify controllers in namespace flux-system."
kubectl get pods -n flux-system

exit 0
