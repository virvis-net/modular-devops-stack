#!/usr/bin/env bash
set -euo pipefail

echo "Removing ingress-nginx..."
KUBECTL_COMMAND=(kubectl)
if [ -n "${KUBECTL_CONTEXT:-}" ]; then
  KUBECTL_COMMAND+=(--context "$KUBECTL_CONTEXT")
fi

"${KUBECTL_COMMAND[@]}" delete \
  -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml \
  --ignore-not-found=true
