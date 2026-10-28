#!/usr/bin/env bash
set -euo pipefail

deployment_json="$(kubectl get deployment ingress-nginx-controller -n ingress-nginx -o json)"
patch="$(printf '%s' "$deployment_json" | python3 -c '
import json
import sys

deployment = json.load(sys.stdin)
containers = deployment["spec"]["template"]["spec"]["containers"]
controller = next((container for container in containers if container["name"] == "controller"), None)
if controller is None:
    raise SystemExit("ingress-nginx controller container was not found")

args = controller.get("args") or []
if "--enable-metrics" in args:
    print("{}")
else:
    args.append("--enable-metrics")
    print(json.dumps({"spec": {"template": {"spec": {"containers": [
        {"name": "controller", "args": args}
    ]}}}}))
')"

if [[ "$patch" != "{}" ]]; then
  kubectl patch deployment ingress-nginx-controller -n ingress-nginx \
    --type=strategic --patch "$patch"
fi

kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=120s
