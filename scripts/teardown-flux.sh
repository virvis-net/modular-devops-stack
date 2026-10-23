#!/usr/bin/env bash
set -euo pipefail

# Optional flags
FLUX_REMOVE_LOCAL_KEYS="${FLUX_REMOVE_LOCAL_KEYS:-0}"
GITEA_KEY_TITLE="${GITEA_KEY_TITLE:-flux-deploy-key}"
DRY_RUN="${DRY_RUN:-0}"

info(){ printf "\033[1;34m[info]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }

info "Removing Flux GitOps resources and namespace (if present)..."

# If namespace exists, attempt best-effort cleanup
if kubectl get ns flux-system >/dev/null 2>&1; then
  info "flux-system namespace found; performing best-effort cleanup of Flux CRs"

  # Explicitly delete the flux-system secret first (clear intent)
  if kubectl -n flux-system get secret flux-system >/dev/null 2>&1; then
    info "Deleting flux-system secret in cluster"
    kubectl -n flux-system delete secret flux-system --ignore-not-found=true || true
  fi

  # Best-effort delete of common Flux CR types in the namespace
  kubectl -n flux-system delete imageupdateautomation --all --ignore-not-found=true || true
  kubectl -n flux-system delete imagepolicy --all --ignore-not-found=true || true
  kubectl -n flux-system delete imagerepository --all --ignore-not-found=true || true
  kubectl -n flux-system delete kustomization --all --ignore-not-found=true || true
  kubectl -n flux-system delete gitrepository --all --ignore-not-found=true || true

  # Delete the namespace (this removes controllers and remaining CRs)
  if [ "${DRY_RUN}" = "1" ]; then
    info "DRY_RUN=1; would delete namespace flux-system"
  else
    info "Deleting namespace flux-system"
    kubectl delete namespace flux-system --ignore-not-found=true || true

    # Wait briefly for namespace to terminate
    for i in $(seq 1 60); do
      if ! kubectl get ns flux-system >/dev/null 2>&1; then
        info "Namespace flux-system removed"
        break
      fi
      sleep 1
    done
  fi
else
  info "Namespace flux-system not present; skipping namespace cleanup"
fi

# Remove buildx builder if present
info "Removing buildx builder (if present)..."
docker buildx rm mds-builder >/dev/null 2>&1 || true

# Remove buildkit container if still present (best-effort)
BK=$(docker ps --filter "name=buildx_buildkit" --format "{{.Names}}" | head -n1)
[ -n "$BK" ] && docker rm -f "$BK" >/dev/null 2>&1 || true

# Optionally remove Flux deploy key from Gitea (requires GITEA_API_TOKEN, GITEA_OWNER, GITEA_REPO)
if [ -n "${GITEA_API_TOKEN:-}" ] && [ -n "${GITEA_OWNER:-}" ] && [ -n "${GITEA_REPO:-}" ]; then
  info "Attempting to remove Flux deploy key from Gitea (title ${GITEA_KEY_TITLE})"
  KEY_ID=$(curl -s -H "Authorization: token ${GITEA_API_TOKEN}" \
    "http://localhost:3000/api/v1/repos/${GITEA_OWNER}/${GITEA_REPO}/keys" | \
    jq -r --arg title "$GITEA_KEY_TITLE" '.[] | select(.title==$title) | .id' 2>/dev/null || true)
  if [ -n "$KEY_ID" ] && [ "$KEY_ID" != "null" ]; then
    curl -s -X DELETE -H "Authorization: token ${GITEA_API_TOKEN}" \
      "http://localhost:3000/api/v1/repos/${GITEA_OWNER}/${GITEA_REPO}/keys/${KEY_ID}" >/dev/null 2>&1 || true
    info "Removed deploy key id ${KEY_ID} from Gitea repo ${GITEA_OWNER}/${GITEA_REPO}."
  else
    warn "No deploy key named '${GITEA_KEY_TITLE}' found or Gitea unreachable; skipping key removal."
  fi
fi

# Optionally remove local SSH key and known_hosts used by bootstrap
if [ "${FLUX_REMOVE_LOCAL_KEYS}" = "1" ]; then
  if [ -f "$HOME/.ssh/flux_deploy_key" ]; then
    info "Removing local Flux private key $HOME/.ssh/flux_deploy_key"
    rm -f "$HOME/.ssh/flux_deploy_key" "$HOME/.ssh/flux_deploy_key.pub" || true
  fi
  if [ -f "$HOME/.ssh/known_hosts.flux" ]; then
    info "Removing Flux known_hosts $HOME/.ssh/known_hosts.flux"
    rm -f "$HOME/.ssh/known_hosts.flux" || true
  fi
else
  info "FLUX_REMOVE_LOCAL_KEYS not set; leaving local SSH key and known_hosts in place"
fi

# Remove readable kubeconfig copy created for Flux bootstrap
FLUX_KUBECONFIG="$HOME/.kube/config.flux"
if [ -f "$FLUX_KUBECONFIG" ]; then
  info "Removing Flux kubeconfig copy at $FLUX_KUBECONFIG"
  rm -f "$FLUX_KUBECONFIG" || true
fi

info "Teardown complete"
