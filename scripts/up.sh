#!/bin/bash
set -e

# Load environment variables from .env
if [ -f .env ]; then
  set -a && source .env && set +a
fi

# Ensure shared network exists
docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 || docker network create "$NETWORK_NAME"

# Start the whole stack
docker compose -p "$STACK_NAME-providers" \
  -f ./stack/docker-compose.yaml \
  -f ./registry/provider/local/docker-compose.yaml \
  -f ./source-control/provider/gitea/docker-compose.yaml \
  -f ./ci/provider/woodpecker/docker-compose.yaml \
  up -d

# Create k3d cluster using your config
if ! k3d cluster list | grep -q "$K3D_CLUSTER_NAME"; then
  k3d cluster create --config ./cluster/provider/k3d/cluster.yaml
fi

# Install ingress-nginx (idempotent)
echo "Installing ingress-nginx..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

echo "Configuring ingress-nginx for k3d..."
kubectl patch deployment ingress-nginx-controller --namespace ingress-nginx \
  --type=strategic \
  --patch='{"spec":{"template":{"spec":{"containers":[{"name":"controller","ports":[{"containerPort":80,"hostPort":null},{"containerPort":443,"hostPort":null}]}]}}}}'

echo "Waiting for ingress admission jobs to complete..."
kubectl wait --namespace ingress-nginx \
  --for=condition=Complete \
  job/ingress-nginx-admission-create \
  job/ingress-nginx-admission-patch \
  --timeout=120s

echo "Waiting for ingress admission endpoint to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=jsonpath='{.subsets[0].addresses[0].ip}' \
  endpoints/ingress-nginx-controller-admission \
  --timeout=120s

# Bootstrap Flux (idempotent)
./gitops/provider/flux/bootstrap.sh
