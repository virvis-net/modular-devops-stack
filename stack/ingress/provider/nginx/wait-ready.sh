#!/usr/bin/env bash
set -euo pipefail

echo "Waiting for ingress admission endpoint to be created..."
kubectl wait --namespace ingress-nginx \
  --for=create \
  endpoints/ingress-nginx-controller-admission \
  --timeout=120s

echo "Waiting for ingress admission endpoint to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=jsonpath='{.subsets[0].addresses[0].ip}' \
  endpoints/ingress-nginx-controller-admission \
  --timeout=120s

echo "Waiting for ingress admission webhook certificate to be configured..."
kubectl wait \
  --for=jsonpath='{.webhooks[0].clientConfig.caBundle}' \
  validatingwebhookconfiguration/ingress-nginx-admission \
  --timeout=120s
