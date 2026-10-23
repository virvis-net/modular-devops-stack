#!/usr/bin/env bash
set -euo pipefail

FLUX_REMOVE_LOCAL_KEYS="${FLUX_REMOVE_LOCAL_KEYS:-0}"
GITEA_KEY_TITLE="${GITEA_KEY_TITLE:-flux-deploy-key}"
DRY_RUN="${DRY_RUN:-0}"
KUBECTL_RETRIES="${KUBECTL_RETRIES:-6}"
KUBECTL_RETRY_SLEEP="${KUBECTL_RETRY_SLEEP:-2}"
NAMESPACE_WAIT_SECONDS="${NAMESPACE_WAIT_SECONDS:-120}"

info(){ printf "\033[1;34m[info]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }

kubectl_retry(){
  local tries=0 rc=0
  while [ $tries -lt "$KUBECTL_RETRIES" ]; do
    if kubectl "$@" >/dev/null 2>&1; then return 0; fi
    rc=$?
    tries=$((tries+1))
    sleep "$KUBECTL_RETRY_SLEEP"
  done
  return $rc
}

info "Removing Flux GitOps resources and namespace..."

if kubectl_retry get ns flux-system >/dev/null 2>&1; then
  info "Namespace flux-system exists"

  # ------------------------------------------------------------
  # 1. REMOVE FINALIZERS FIRST (the critical fix)
  # ------------------------------------------------------------
  info "Removing finalizers from Flux CRs (critical fix)"

  if [ "${DRY_RUN}" = "1" ]; then
    info "DRY_RUN=1; would remove finalizers"
  else
    kubectl -n flux-system get kustomization,gitrepository,imagepolicy,imagerepository,imageupdateautomation -o name \
      | xargs -r -I{} kubectl -n flux-system patch {} --type=json \
          -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true

    # Explicitly patch the flux-system Kustomization (the one that hangs)
    kubectl -n flux-system patch kustomization flux-system --type=json \
      -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
  fi

  # ------------------------------------------------------------
  # 2. DELETE CRs AFTER finalizers are gone
  # ------------------------------------------------------------
  info "Deleting Flux CRs"

  for cr in imageupdateautomation imagepolicy imagerepository kustomization gitrepository; do
    if kubectl_retry get "$cr" -n flux-system >/dev/null 2>&1; then
      info "Deleting $cr"
      [ "${DRY_RUN}" = "1" ] || kubectl -n flux-system delete "$cr" --all --ignore-not-found=true || true
    fi
  done

  # ------------------------------------------------------------
  # 3. DELETE NAMESPACE
  # ------------------------------------------------------------
  info "Deleting namespace flux-system"
  [ "${DRY_RUN}" = "1" ] || kubectl delete namespace flux-system --ignore-not-found=true || true

  # ------------------------------------------------------------
  # 4. WAIT FOR REMOVAL
  # ------------------------------------------------------------
  info "Waiting up to ${NAMESPACE_WAIT_SECONDS}s for namespace removal"
  local_end=$((SECONDS + NAMESPACE_WAIT_SECONDS))

  while [ $SECONDS -lt $local_end ]; do
    if ! kubectl_retry get ns flux-system >/dev/null 2>&1; then
      info "Namespace flux-system removed"
      break
    fi
    sleep 1
  done

  if kubectl_retry get ns flux-system >/dev/null 2>&1; then
    warn "Namespace still present; manual finalizer removal may be required"
  fi

else
  info "Namespace flux-system not present; skipping"
fi

info "Removing buildx builder..."
[ "${DRY_RUN}" = "1" ] || docker buildx rm mds-builder >/dev/null 2>&1 || true

BK=$(docker ps --filter "name=buildx_buildkit" --format "{{.Names}}" | head -n1 || true)
if [ -n "$BK" ]; then
  info "Removing buildkit container $BK"
  [ "${DRY_RUN}" = "1" ] || docker rm -f "$BK" >/dev/null 2>&1 || true
fi

info "Teardown complete"
