#!/usr/bin/env bash
set -euo pipefail

# --- Configurable values (override with env vars) ---
GIT_URL="${GITOPS_REPO_URL:-ssh://git@host.docker.internal:2222/mds/gitops.git}"
GIT_BRANCH="${GITOPS_BRANCH:-main}"
GIT_PATH="${GITOPS_PATH:-clusters/mds-cluster}"
SSH_DOMAIN="${GITEA_SSH_DOMAIN:-host.docker.internal}"
SSH_PORT="${GITEA_SSH_PORT:-2222}"
SSH_KEY="${FLUX_PRIVATE_KEY:-$HOME/.ssh/flux_deploy_key}"
KNOWN_HOSTS="$HOME/.ssh/known_hosts.flux"
FLUX_IMAGE="${FLUX_IMAGE:-ghcr.io/fluxcd/flux-cli:v0.38.0}"
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
if [ ! -f "$KNOWN_HOSTS" ] || ! ssh-keygen -F "[${GITEA_SSH_DOMAIN}]:${GITEA_SSH_PORT}" -f "$KNOWN_HOSTS" >/dev/null 2>&1; then
  info "Adding Gitea host key to Flux-specific known_hosts at $KNOWN_HOSTS"
  TMP_KEYSCAN=$(ssh-keyscan -p "$GITEA_SSH_PORT" localhost 2>/dev/null || true)
  if [ -n "$TMP_KEYSCAN" ]; then
    # Rewrite the hostname from localhost → ${GITEA_SSH_DOMAIN} so that Flux can connect from inside the container
    echo "$TMP_KEYSCAN" | sed "s/\[localhost\]:${GITEA_SSH_PORT}/\[${GITEA_SSH_DOMAIN}\]:${GITEA_SSH_PORT}/" >> "$KNOWN_HOSTS"
  else
    warn "Could not retrieve SSH key from localhost:${GITEA_SSH_PORT}; Flux SSH may fail."
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
docker run --rm \
  --add-host=${GITEA_SSH_DOMAIN}:host-gateway \
  -v "$FLUX_KUBECONFIG:/flux-conf/kube-config:ro" \
  -v "$SSH_KEY:/flux-conf/ssh-private_key:ro" \
  -v "$KNOWN_HOSTS:/flux-conf/ssh-known_hosts:ro" \
  -e KUBECONFIG=/flux-conf/kube-config \
  -e GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/flux-conf/ssh-known_hosts" \
  -e SSH_KNOWN_HOSTS=/flux-conf/ssh-known_hosts \
  "$FLUX_IMAGE" \
  bootstrap git \
    --url="$GIT_URL" \
    --branch="$GIT_BRANCH" \
    --path="$GIT_PATH" \
    --private-key-file=/flux-conf/ssh-private_key \
    --components-extra=image-reflector-controller,image-automation-controller \
    --silent \
  || warn "flux bootstrap returned non-zero; continuing to fallback checks"

info "Flux bootstrap (container) finished. Verify controllers in namespace flux-system."
kubectl get pods -n flux-system || true

exit 0
