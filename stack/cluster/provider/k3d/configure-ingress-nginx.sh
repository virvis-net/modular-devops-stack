#!/usr/bin/env bash
set -euo pipefail

echo "Configuring ingress-nginx for k3d..."
kubectl patch deployment ingress-nginx-controller --namespace ingress-nginx \
  --type=strategic \
  --patch='{"spec":{"template":{"spec":{"containers":[{"name":"controller","ports":[{"containerPort":80,"hostPort":null},{"containerPort":443,"hostPort":null}]}]}}}}'
