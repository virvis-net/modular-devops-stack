#!/usr/bin/env bash
set -euo pipefail

php -S 0.0.0.0:8080 -t public public/index.php &
app_pid=$!
php -S 0.0.0.0:9090 -t public docker/metrics-router.php &
metrics_pid=$!

shutdown() {
    kill "$app_pid" "$metrics_pid" 2>/dev/null || true
}

trap shutdown INT TERM

set +e
wait -n "$app_pid" "$metrics_pid"
status=$?
set -e

shutdown
wait "$app_pid" 2>/dev/null || true
wait "$metrics_pid" 2>/dev/null || true
exit "$status"
