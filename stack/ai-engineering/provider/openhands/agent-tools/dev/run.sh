#!/usr/bin/env bash
# Run a command inside the Laravel dev container as the host user,
# in the repository mount. Usage: bash /opt/dev/run.sh php artisan test
set -euo pipefail

CONTAINER="${DEV_CONTAINER:-mds-app-laravel-dev-app-1}"
WORKDIR="/var/www/html"

if [ "$#" -eq 0 ]; then
  echo "usage: run.sh <command> [args...]" >&2
  exit 2
fi

if ! docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true; then
  echo "ERROR: dev container $CONTAINER is not running" >&2
  exit 3
fi

# -u 1000:1000 keeps files created by artisan owned by the host user.
exec docker exec -u 1000:1000 -w "$WORKDIR" "$CONTAINER" "$@"
