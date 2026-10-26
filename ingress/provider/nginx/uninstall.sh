#!/usr/bin/env bash
set -euo pipefail

echo "Removing ingress-nginx..."
kubectl delete \
  -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml \
  --ignore-not-found=true
