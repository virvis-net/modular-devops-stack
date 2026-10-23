#!/usr/bin/env bash
set -euo pipefail

# Optional flags
FLUX_REMOVE_LOCAL_KEYS="${FLUX_REMOVE_LOCAL_KEYS:-0}"
GITEA_KEY_TITLE="${GITEA_KEY_TITLE:-flux-deploy-key}"
DRY_RUN="${DRY_RUN:-0}"
# How many times to retry kubectl on transient failures
KUBECTL_RETRIES="${KUBECTL_RETRIES:-6}"
KUBECTL_RETRY_SLEEP="${KUBECTL_RETRY_SLEEP:-2}"
# How long to wait for namespace deletion (seconds)
NAMESPACE_WAIT_SECONDS="${NAMESPACE_WAIT_SECONDS:-120}"

info(){ printf "\033[1;34m[info]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
err(){ printf "\033[1;31m[error]\033[0m %s\n" "$*"; }

# Retry wrapper for kubectl to tolerate transient API unavailability
kubectl_retry(){
  local tries=0
  local rc=0
  while [ $tries -lt "$KUBECTL_RETRIES" ]; do
    if kubectl "$@" >/dev/null 2>&1; then
      return 0
    fi
    rc=$?
    tries=$((tries+1))
    sleep "$KUBECTL_RETRY_SLEEP"
  done
  return $rc
}

# Run kubectl and print output (non-silent) with retries
kubectl_retry_output(){
  local tries=0
  local rc=0
  while [ $tries -lt "$KUBECTL_RETRIES" ]; do
    if kubectl "$@" 2>&1; then
      return 0
    fi
    rc=$?
    tries=$((tries+1))
    sleep "$KUBECTL_RETRY_SLEEP"
  done
  return $rc
}

info "Removing Flux GitOps resources and namespace (if present)..."

# If namespace exists, attempt best-effort cleanup
if kubectl_retry get ns flux-system >/dev/null 2>&1; then
  info "flux-system namespace found; performing best-effort cleanup of Flux CRs"

  # Explicitly delete the flux-system secret first (clear intent)
  if kubectl_retry get secret flux-system -n flux-system >/dev/null 2>&1; then
    info "Deleting flux-system secret in cluster"
    if [ "${DRY_RUN}" = "1" ]; then
      info "DRY_RUN=1; would run: kubectl -n flux-system delete secret flux-system"
    else
      kubectl -n flux-system delete secret flux-system --ignore-not-found=true || true
    fi
  fi

  # Best-effort delete of common Flux CR types in the namespace
  for cr in imageupdateautomation imagepolicy imagerepository kustomization gitrepository; do
    if kubectl_retry get "$cr" -n flux-system --ignore-not-found >/dev/null 2>&1; then
      info "Deleting all $cr in flux-system (best-effort)"
      if [ "${DRY_RUN}" = "1" ]; then
        info "DRY_RUN=1; would run: kubectl -n flux-system delete $cr --all --ignore-not-found=true"
      else
        kubectl -n flux-system delete "$cr" --all --ignore-not-found=true || true
      fi
    fi
  done

  # Best-effort remove finalizers from common Flux CRs to avoid namespace hang
  info "Best-effort: remove finalizers from common Flux CRs"
  if [ "${DRY_RUN}" = "1" ]; then
    info "DRY_RUN=1; would attempt to patch finalizers on Flux CRs"
  else
    for cr in kustomization gitrepository imagepolicy imagerepository imageupdateautomation; do
      # patch all objects of this kind in the namespace
      if kubectl_retry get "$cr" -n flux-system --ignore-not-found >/dev/null 2>&1; then
        # attempt JSON patch remove; fallback to merge with empty array
        kubectl -n flux-system patch "$cr" --all --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || \
        kubectl -n flux-system patch "$cr" --all -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
      fi
    done
  fi

  # Delete the namespace (this removes controllers and remaining CRs)
  if [ "${DRY_RUN}" = "1" ]; then
    info "DRY_RUN=1; would delete namespace flux-system"
  else
    info "Deleting namespace flux-system"
    kubectl -n flux-system get ns >/dev/null 2>&1 || true
    kubectl delete namespace flux-system --ignore-not-found=true || true

    # Wait for namespace to terminate with bounded timeout
    info "Waiting up to ${NAMESPACE_WAIT_SECONDS}s for namespace flux-system to terminate"
    local_end=$((SECONDS + NAMESPACE_WAIT_SECONDS))
    while [ $SECONDS -lt $local_end ]; do
      if ! kubectl_retry get ns flux-system >/dev/null 2>&1; then
        info "Namespace flux-system removed"
        break
      fi
      sleep 1
    done
    if kubectl_retry get ns flux-system >/dev/null 2>&1; then
      warn "Namespace flux-system still present after ${NAMESPACE_WAIT_SECONDS}s; you may need to remove finalizers manually."
    fi
  fi
else
  info "Namespace flux-system not present; skipping namespace cleanup"
fi

# Remove buildx builder if present
info "Removing buildx builder (if present)..."
if [ "${DRY_RUN}" = "1" ]; then
  info "DRY_RUN=1; would run: docker buildx rm mds-builder"
else
  docker buildx rm mds-builder >/dev/null 2>&1 || true
fi

# Remove buildkit container if still present (best-effort)
BK=$(docker ps --filter "name=buildx_buildkit" --format "{{.Names}}" | head -n1 || true)
if [ -n "$BK" ]; then
  if [ "${DRY_RUN}" = "1" ]; then
    info "DRY_RUN=1; would remove buildkit container $BK"
  else
    docker rm -f "$BK" >/dev/null 2>&1 || true
  fi
fi

# Optionally remove Flux deploy key from Gitea (requires GITEA_API_TOKEN, GITEA_OWNER, GITEA_REPO)
if [ -n "${GITEA_API_TOKEN:-}" ] && [ -n "${GITEA_OWNER:-}" ] && [ -n "${GITEA_REPO:-}" ]; then
  info "Attempting to remove Flux deploy key from Gitea (title ${GITEA_KEY_TITLE})"
  if [ "${DRY_RUN}" = "1" ]; then
    info "DRY_RUN=1; would query Gitea for deploy keys and delete key titled ${GITEA_KEY_TITLE}"
  else
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
  if [ "${DRY_RUN}" = "1" ]; then
    info "DRY_RUN=1; would remove Flux kubeconfig copy at $FLUX_KUBECONFIG"
  else
    info "Removing Flux kubeconfig copy at $FLUX_KUBECONFIG"
    rm -f "$FLUX_KUBECONFIG" || true
  fi
fi

info "Teardown complete"
