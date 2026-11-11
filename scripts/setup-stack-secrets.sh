#!/usr/bin/env bash
set -euo pipefail
set +x

usage() {
  cat <<'USAGE'
Create the Laravel database Secret and the cross-stack Collector auth Secrets.

Collector auth requires the central context, one or more forwarder contexts,
and an explicit scheme. For example:
  scripts/setup-stack-secrets.sh \
    --central-context KUBECTL_CONTEXT \
    --forwarder-context KUBECTL_CONTEXT [--forwarder-context KUBECTL_CONTEXT ...] \
    --collector-scheme http|https [--central-port PORT] \
    [--database-context KUBECTL_CONTEXT ...] [--database-namespace NAMESPACE ...]

Database-only setup needs an explicit context:
  scripts/setup-stack-secrets.sh --database-only \
    --database-context KUBECTL_CONTEXT [--database-namespace NAMESPACE]

Options:
  --central-context       Context containing the central Collector receiver.
                          --frontend-context is accepted as an alias.
  --forwarder-context     Context containing a forwarding Collector. Repeat
                          for each application stack. --backend-context is
                          accepted as an alias for one forwarder.
  --collector-scheme      HTTP or HTTPS for forwarder-to-central Collector traffic.
  --central-port          Central stack's published port (default: 80 for
                          HTTP, 443 for HTTPS).
  --database-context      Context in which to create app-database Secrets.
                          Repeat for multiple Laravel stacks. With exactly
                          one forwarder, it defaults to that context.
  --database-namespace    Namespace for an app-database Secret. Repeat to
                          apply the namespace to every database context
                          (default: staging).
  --database-only         Create missing database Secrets; skip Collector auth.
  --collector-only        Set up Collector auth; skip database Secrets.
  -h, --help              Show this help.

The Collector setup uses Docker's httpd:2.4-alpine image to run htpasswd, so
htpasswd does not need to be installed on the host. HTTPS mode builds a small
mkcert helper image from the upstream mkcert release, so mkcert does not need
to be installed on the host either. Its CA is stored under the ignored
stack/.state/ directory. This script manages Kubernetes Secrets and restarts
each forwarding Collector so it reloads client auth. Configure and push the
OTEL_CENTRAL_* GitOps settings separately. Collector auth is updated each
run; use the existing shared password to preserve other forwarding clients,
or update each client's Secret if rotating it.
USAGE
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '[info] %s\n' "$*"
}

CENTRAL_CONTEXT=''
FORWARDER_CONTEXTS=()
FORWARDER_CONTEXT_SET=false
FORWARDER_CONTEXT_COUNT=0
DATABASE_CONTEXTS=()
DATABASE_CONTEXT_SET=false
COLLECTOR_SCHEME=''
CENTRAL_PORT=''
DATABASE_NAMESPACES=()
DATABASE_NAMESPACE_SET=false
DO_DATABASE=true
DO_COLLECTOR=true
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MKCERT_IMAGE='modular-devops/mkcert:1.4.4'

while (($#)); do
  case "$1" in
    --central-context|--frontend-context)
      (($# >= 2)) || fail '--central-context requires a value'
      [[ -z "$CENTRAL_CONTEXT" ]] || fail 'specify the central context only once'
      CENTRAL_CONTEXT="$2"
      shift 2
      ;;
    --forwarder-context|--backend-context)
      (($# >= 2)) || fail '--forwarder-context requires a value'
      [[ -n "$2" ]] || fail '--forwarder-context cannot be empty'
      FORWARDER_CONTEXTS+=("$2")
      FORWARDER_CONTEXT_SET=true
      FORWARDER_CONTEXT_COUNT=$((FORWARDER_CONTEXT_COUNT + 1))
      shift 2
      ;;
    --database-context)
      (($# >= 2)) || fail '--database-context requires a value'
      [[ -n "$2" ]] || fail '--database-context cannot be empty'
      DATABASE_CONTEXTS+=("$2")
      DATABASE_CONTEXT_SET=true
      shift 2
      ;;
    --collector-scheme)
      (($# >= 2)) || fail '--collector-scheme requires http or https'
      COLLECTOR_SCHEME="${2,,}"
      shift 2
      ;;
    --central-port)
      (($# >= 2)) || fail '--central-port requires a port number'
      CENTRAL_PORT="$2"
      shift 2
      ;;
    --database-namespace)
      (($# >= 2)) || fail '--database-namespace requires a value'
      DATABASE_NAMESPACES+=("$2")
      DATABASE_NAMESPACE_SET=true
      shift 2
      ;;
    --database-only)
      DO_COLLECTOR=false
      shift
      ;;
    --collector-only)
      DO_DATABASE=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "unknown option: $1"
      ;;
  esac
done

if [[ "$DO_DATABASE" == false && "$DO_COLLECTOR" == false ]]; then
  fail 'choose at most one of --database-only and --collector-only'
fi
if [[ "$DO_DATABASE" == false && ( "$DATABASE_CONTEXT_SET" == true || "$DATABASE_NAMESPACE_SET" == true ) ]]; then
  fail 'database options cannot be used with --collector-only'
fi
if [[ "$DO_COLLECTOR" == true ]]; then
  [[ -n "$CENTRAL_CONTEXT" ]] || fail '--central-context is required for Collector setup'
  [[ "$FORWARDER_CONTEXT_SET" == true ]] || fail 'provide at least one --forwarder-context for Collector setup'
  [[ "$COLLECTOR_SCHEME" == http || "$COLLECTOR_SCHEME" == https ]] ||
    fail '--collector-scheme must be http or https'
  if [[ -z "$CENTRAL_PORT" ]]; then
    if [[ "$COLLECTOR_SCHEME" == https ]]; then
      CENTRAL_PORT=443
    else
      CENTRAL_PORT=80
    fi
  fi
  [[ "$CENTRAL_PORT" =~ ^[0-9]+$ ]] || fail '--central-port must be numeric'
  CENTRAL_PORT="$((10#$CENTRAL_PORT))"
  ((CENTRAL_PORT >= 1 && CENTRAL_PORT <= 65535)) || fail '--central-port is out of range'
  for context in "${FORWARDER_CONTEXTS[@]}"; do
    [[ "$context" != "$CENTRAL_CONTEXT" ]] ||
      fail "context '$context' cannot both receive and forward telemetry"
  done
fi

if [[ "$DO_DATABASE" == true ]]; then
  if [[ "$DATABASE_CONTEXT_SET" == false ]]; then
    if [[ "$DO_COLLECTOR" == true && "$FORWARDER_CONTEXT_COUNT" -eq 1 ]]; then
      DATABASE_CONTEXTS=("${FORWARDER_CONTEXTS[0]}")
    else
      fail 'provide --database-context (or use --collector-only) when setting up database Secrets'
    fi
  fi
  if [[ "$DATABASE_NAMESPACE_SET" == false ]]; then
    DATABASE_NAMESPACES=(staging)
  fi
fi

command -v kubectl >/dev/null 2>&1 || fail 'kubectl is required'
if [[ "$DO_DATABASE" == true ]]; then
  command -v python3 >/dev/null 2>&1 || fail 'python3 is required for database credential generation'
fi
if [[ "$DO_COLLECTOR" == true ]]; then
  command -v docker >/dev/null 2>&1 || fail 'docker is required for Collector auth generation'
fi

require_namespace() {
  local context="$1"
  local namespace="$2"
  kubectl --context "$context" get namespace "$namespace" >/dev/null 2>&1 ||
    fail "namespace '$namespace' is not available in context '$context'"
}

if [[ "$DO_DATABASE" == true ]]; then
  for context in "${DATABASE_CONTEXTS[@]}"; do
    for namespace in "${DATABASE_NAMESPACES[@]}"; do
      require_namespace "$context" "$namespace"
    done
  done
fi

if [[ "$DO_COLLECTOR" == true ]]; then
  require_namespace "$CENTRAL_CONTEXT" monitoring
  kubectl --context "$CENTRAL_CONTEXT" get ingress otel-collector-central-ingest \
    --namespace monitoring >/dev/null 2>&1 ||
    fail "central ingest Ingress is missing in '$CENTRAL_CONTEXT'; enable central ingest in that stack's GitOps config first"
  for context in "${FORWARDER_CONTEXTS[@]}"; do
    require_namespace "$context" monitoring
    kubectl --context "$context" get deployment otel-collector \
      --namespace monitoring >/dev/null 2>&1 ||
      fail "otel-collector Deployment is missing in '$context'"
  done
fi

TEMP_DIR="$(mktemp -d)"
chmod 700 "$TEMP_DIR"
cleanup() {
  unset COLLECTOR_PASSWORD 2>/dev/null || true
  if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
    rm -rf -- "$TEMP_DIR"
  fi
}
trap cleanup EXIT

apply_generic_secret() {
  local context="$1"
  local namespace="$2"
  local name="$3"
  shift 3

  kubectl --context "$context" create secret generic "$name" \
    --namespace "$namespace" "$@" --dry-run=client -o yaml |
    kubectl --context "$context" apply -f -
}

apply_tls_secret() {
  local context="$1"
  local cert_file="$2"
  local key_file="$3"

  kubectl --context "$context" create secret tls otel-central-ingest-tls \
    --namespace monitoring \
    --cert="$cert_file" \
    --key="$key_file" \
    --dry-run=client -o yaml |
    kubectl --context "$context" apply -f -
}

if [[ "$DO_DATABASE" == true ]]; then
  database_index=0
  for context in "${DATABASE_CONTEXTS[@]}"; do
    for namespace in "${DATABASE_NAMESPACES[@]}"; do
      database_index=$((database_index + 1))
      if kubectl --context "$context" get secret app-database \
        --namespace "$namespace" >/dev/null 2>&1; then
        info "app-database already exists in $context/$namespace; preserving its credentials"
        continue
      fi

      if kubectl --context "$context" get pvc data-mariadb-0 \
        --namespace "$namespace" >/dev/null 2>&1; then
        printf 'Warning: %s/%s has a MariaDB PVC but no app-database Secret.\n' "$context" "$namespace" >&2
        printf 'New credentials will not match an already-initialized database.\n' >&2
        if [[ ! -t 0 ]]; then
          fail "rerun interactively to confirm new credentials for '$context/$namespace'"
        fi
        read -r -p "Create a new app-database Secret in $context/$namespace anyway? [y/N] " confirmation
        case "${confirmation,,}" in
          y|yes) ;;
          *) fail "did not replace or create database credentials in '$context/$namespace'" ;;
        esac
      fi

      db_dir="$TEMP_DIR/database-$database_index"
      mkdir -m 700 "$db_dir"
      python3 - "$db_dir" <<'PY'
import pathlib
import secrets
import sys

directory = pathlib.Path(sys.argv[1])
for filename in ("root-password", "password"):
    path = directory / filename
    path.write_text(secrets.token_hex(32), encoding="ascii")
    path.chmod(0o600)
PY

      apply_generic_secret "$context" "$namespace" app-database \
        --from-file="root-password=$db_dir/root-password" \
        --from-file="password=$db_dir/password"
      info "created app-database in $context/$namespace with separate random credentials"
    done
  done
fi

if [[ "$DO_COLLECTOR" == true ]]; then
  if [[ "$COLLECTOR_SCHEME" == https ]]; then
    CA_DIR="$ROOT_DIR/stack/.state/otel-central-ca"
    mkdir -p "$CA_DIR"
    chmod 700 "$CA_DIR"
    if [[ -e "$CA_DIR/rootCA.pem" || -e "$CA_DIR/rootCA-key.pem" ]]; then
      [[ -s "$CA_DIR/rootCA.pem" && -s "$CA_DIR/rootCA-key.pem" ]] ||
        fail "mkcert CA state in '$CA_DIR' is incomplete; restore both CA files or remove the incomplete state before continuing"
    fi

    info 'Building the pinned mkcert helper image'
    docker build \
      --tag "$MKCERT_IMAGE" \
      --file "$ROOT_DIR/tools/mkcert/Dockerfile" \
      "$ROOT_DIR/tools/mkcert"

    info 'Generating a local HTTPS certificate for host.k3d.internal'
    docker run --rm \
      --user "$(id -u):$(id -g)" \
      --env CAROOT=/ca \
      --volume "$CA_DIR:/ca" \
      --volume "$TEMP_DIR:/out" \
      "$MKCERT_IMAGE" \
      -cert-file /out/host.k3d.internal.pem \
      -key-file /out/host.k3d.internal-key.pem \
      host.k3d.internal
    [[ -s "$CA_DIR/rootCA.pem" ]] || fail 'mkcert rootCA.pem was not generated'
    apply_tls_secret "$CENTRAL_CONTEXT" \
      "$TEMP_DIR/host.k3d.internal.pem" \
      "$TEMP_DIR/host.k3d.internal-key.pem"
  fi

  read -r -s -p 'Enter a shared password for the otel-forwarder account: ' COLLECTOR_PASSWORD
  printf '\n'
  [[ -n "$COLLECTOR_PASSWORD" ]] || fail 'Collector password cannot be empty'

  if ! printf '%s\n' "$COLLECTOR_PASSWORD" |
    docker run --rm -i httpd:2.4-alpine htpasswd -ni otel-forwarder \
      > "$TEMP_DIR/auth"; then
    fail 'could not generate the htpasswd file using the httpd container'
  fi

  apply_generic_secret "$CENTRAL_CONTEXT" monitoring otel-central-ingest-auth \
    --from-file="auth=$TEMP_DIR/auth"

  printf 'Basic %s' "$(printf '%s' "otel-forwarder:$COLLECTOR_PASSWORD" | base64 | tr -d '\n')" \
    > "$TEMP_DIR/authorization"
  unset COLLECTOR_PASSWORD

  for context in "${FORWARDER_CONTEXTS[@]}"; do
    if [[ "$COLLECTOR_SCHEME" == https ]]; then
      apply_generic_secret "$context" monitoring otel-central-client-auth \
        --from-file="authorization=$TEMP_DIR/authorization" \
        --from-file="ca.crt=$CA_DIR/rootCA.pem"
    else
      apply_generic_secret "$context" monitoring otel-central-client-auth \
        --from-file="authorization=$TEMP_DIR/authorization"
    fi

    kubectl --context "$context" rollout restart deployment/otel-collector \
      --namespace monitoring >/dev/null
    kubectl --context "$context" rollout status deployment/otel-collector \
      --namespace monitoring --timeout=120s
    info "Collector client auth configured in $context"
  done

  info "Forwarders are configured for $COLLECTOR_SCHEME://host.k3d.internal:$CENTRAL_PORT"
  if [[ "$COLLECTOR_SCHEME" == http ]]; then
    info 'HTTP does not encrypt Basic Auth credentials or telemetry; use it only on a trusted local network'
  fi
fi

info 'Kubernetes Secret setup complete'
