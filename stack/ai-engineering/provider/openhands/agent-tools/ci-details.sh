#!/usr/bin/env bash
# usage: ci-details.sh <target_url from a ci/woodpecker status>
set -u
: "${WOODPECKER_API_URL:?not set}" "${WOODPECKER_TOKEN:?not set}"
read -r REPO N < <(echo "$1" | sed -E 's#.*/repos/([0-9]+)/pipeline/([0-9]+).*#\1 \2#')
case "$REPO$N" in ''|*[!0-9]*) echo "cannot parse repo id / pipeline number from: $1"; exit 2;; esac
H="Authorization: Bearer $WOODPECKER_TOKEN"; API="$WOODPECKER_API_URL/repos/$REPO"
P=$(curl -fsS -H "$H" "$API/pipelines/$N") || { echo "WOODPECKER_REQUEST_FAILED (check URL, token, repo access)"; exit 2; }
echo "$P" | jq -c '{number, status, event, branch, commit: (.commit // "" | tostring | .[0:12])}'
echo "$P" | jq -c '.errors // empty'
echo "$P" | jq -c '[.workflows[]?.children[]? | {id, name, state}]'
for ID in $(echo "$P" | jq -r '.workflows[]?.children[]? | select(.state=="failure" or .state=="error") | .id'); do
  echo "=== failing step id=$ID: last 80 log lines ==="
  curl -fsS -H "$H" "$API/logs/$N/$ID" | jq -r '.[]? | .data | @base64d' \
    | sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g' | tail -n 80
done
