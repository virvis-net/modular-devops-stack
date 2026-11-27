#!/usr/bin/env bash
# Preflight checks, then create the issue branch and prepare the stack.
# Usage: bash /opt/agent/prepare.sh <branch-name>   (run from workspace/app)
# Non-destructive: refuses to start on a dirty tree instead of cleaning it.
set -euo pipefail

BRANCH="${1:?usage: prepare.sh <branch-name>}"
CONTAINER="${DEV_CONTAINER:-mds-app-laravel-dev-app-1}"
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)/hooks"

ok()   { echo "OK   $*"; }
warn() { echo "WARN $*"; }
fail() { echo "ERROR: $1" >&2; exit "${2:-1}"; }
run()  { bash /opt/dev/run.sh "$@"; }

# 1. Input and repository state (nothing is changed yet)
[[ "$BRANCH" =~ ^[A-Za-z0-9._/-]+$ ]] || fail "unsafe branch name" 2
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "not inside a git repository" 2

STATUS="$(git status --short)"
if [ -n "$STATUS" ]; then
  echo "ERROR: working tree is not clean:" >&2
  echo "$STATUS" >&2
  exit 3
fi
ok "working tree clean"

# 2. Dev container and its dependencies, as defined by devcontainer.json
DC_JSON=".devcontainer/devcontainer.json"
[ -f "$DC_JSON" ] || fail "no $DC_JSON in this repository" 4

SERVICE="$(jq -r '.service' "$DC_JSON" 2>/dev/null)" \
  || fail "cannot parse $DC_JSON (comments in the file? jq needs plain JSON)" 4
FILES_RAW="$(jq -r '.dockerComposeFile | if type=="array" then .[] else . end' "$DC_JSON")" \
  || fail "no dockerComposeFile in $DC_JSON" 4
SERVICES_RAW="$(jq -r '(.runServices // [.service]) | .[]' "$DC_JSON")"

COMPOSE=(docker compose)
while IFS= read -r f; do COMPOSE+=(-f ".devcontainer/$f"); done <<< "$FILES_RAW"
mapfile -t SERVICES <<< "$SERVICES_RAW"

# depends_on pulls in mariadb and redis; --wait blocks until healthchecks pass.
# --no-build fails fast if the image is missing: build it once on the host.
if ! OUT="$("${COMPOSE[@]}" up -d --wait --wait-timeout 120 --no-build "${SERVICES[@]}" 2>&1)"; then
  echo "$OUT" | tail -15 >&2
  fail "could not bring up the dev container stack from $DC_JSON" 4
fi
ok "dev stack up: $("${COMPOSE[@]}" ps --format '{{.Service}}={{.State}}' | tr '\n' ' ')"

# The container run.sh targets must be the one compose just started
ACTUAL_ID="$("${COMPOSE[@]}" ps -q "$SERVICE" | head -1)"
ACTUAL_NAME="$(docker inspect -f '{{.Name}}' "$ACTUAL_ID" | tr -d '/')"
[ "$ACTUAL_NAME" = "$CONTAINER" ] \
  || fail "compose started $ACTUAL_NAME but run.sh targets $CONTAINER; set DEV_CONTAINER" 4
ok "dev container $CONTAINER running"

# 3. Host and container share the working tree, and the agent user can write it
MARK=".git/agent-mount-check-$$"
touch "$MARK"
if ! run test -f "$MARK"; then
  rm -f "$MARK"
  fail "a file created on the host is not visible in the dev container (mount problem)" 5
fi
rm -f "$MARK"
ok "host and container share the working tree"

UNWRITABLE="$(find . \( -path ./.git -o -path ./vendor -o -path ./node_modules \) -prune -o ! -writable -print 2>/dev/null | head -5 || true)"
[ -z "$UNWRITABLE" ] || fail "paths not writable by the agent user, fix ownership on the host: $(echo "$UNWRITABLE" | tr '\n' ' ')" 6
ok "working tree writable"

# 4. Branch
git fetch origin
git show-ref --verify --quiet "refs/heads/$BRANCH" && fail "branch $BRANCH already exists locally" 7
git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1 && fail "branch $BRANCH already exists on origin" 7
git checkout main
git merge --ff-only origin/main
git checkout -b "$BRANCH"
ok "branch $(git branch --show-current) created from $(git rev-parse --short HEAD)"

# 5. Stack-specific preparation (hooks are optional)
if   [ -f artisan ];      then STACK=laravel
elif [ -f go.mod ];       then STACK=go
elif [ -f package.json ]; then STACK=vue
else STACK=unknown; fi

if [ -f "$HOOK_DIR/$STACK.sh" ]; then
  # shellcheck disable=SC1090
  source "$HOOK_DIR/$STACK.sh"
  stack_prepare
fi

echo "READY STACK=$STACK BRANCH=$(git branch --show-current) BASE=$(git rev-parse --short HEAD)"
