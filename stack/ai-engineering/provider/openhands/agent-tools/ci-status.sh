#!/usr/bin/env bash
# usage: ci-status.sh [sha] [max_polls]   (defaults: HEAD, 20 polls x 15s)
set -u
SHA="${1:-$(git rev-parse HEAD)}"; MAX="${2:-20}"
URL="$GITEA_API_URL/repos/$GITEA_OWNER/$GITEA_REPOSITORY/commits/$SHA/status"
F='[.statuses[]? | select(.context|startswith("ci/woodpecker/")) | {context, status:(.status // .state), description, target_url}]'
for i in $(seq 1 "$MAX"); do
  R=$(curl -fsS -H "Authorization: Bearer $GITEA_ACCESS_TOKEN" "$URL") || { echo "CI_STATUS=unavailable (Gitea request failed)"; exit 2; }
  S=$(echo "$R" | jq -c "$F") || { echo "CI_STATUS=unavailable (bad JSON)"; exit 2; }
  V=$(echo "$S" | jq -r 'if length==0 then "unavailable"
    elif any(.[]; .status=="failure" or .status=="error") then "failed"
    elif any(.[]; .status=="pending") then "pending"
    elif all(.[]; .status=="success") then "passed" else "unavailable" end')
  echo "poll $i/$MAX: $V"
  case "$V" in
    passed|failed) break ;;
    unavailable) [ "$(echo "$S" | jq length)" -gt 0 ] && break ;;  # unknown status value
  esac
  [ "$i" -lt "$MAX" ] && sleep 15
done
echo "SHA=$SHA"; echo "CI_STATUS=$V"; echo "$S" | jq -c '.[]'
