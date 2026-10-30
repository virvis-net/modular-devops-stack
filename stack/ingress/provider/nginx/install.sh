#!/usr/bin/env bash
set -euo pipefail

echo "Installing ingress-nginx..."
kubectl apply \
  -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
