#!/usr/bin/env bash
# usage: [CI_EVENT=push|pr] ci-status.sh [sha] [max_polls]   (defaults: push, HEAD, 20 polls x 15s)
set -u
SHA="${1:-$(git -C /projects/app rev-parse HEAD)}"; MAX="${2:-20}"
PREFIX="ci/woodpecker/${CI_EVENT:-push}/"
URL="$GITEA_API_URL/repos/$GITEA_OWNER/$GITEA_REPOSITORY/commits/$SHA/status"
F='[.statuses[]? | select(.context|startswith($P)) | {context, status:(.status // .state), description, target_url}]'
for i in $(seq 1 "$MAX"); do
  R=$(curl -fsS -H "Authorization: Bearer $GITEA_ACCESS_TOKEN" "$URL") || { echo "CI_STATUS=unavailable (Gitea request failed)"; exit 2; }
  S=$(echo "$R" | jq -c --arg P "$PREFIX" "$F") || { echo "CI_STATUS=unavailable (bad JSON)"; exit 2; }
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
echo "SHA=$SHA"; echo "CI_STATUS=$V"; echo "CONTEXT_PREFIX=$PREFIX"; echo "$S" | jq -c '.[]'
if [ "$V" = "passed" ] || [ "$V" = "failed" ]; then
  echo "$S" | jq -r '.[].target_url' | sort -u | while read -r U; do
    echo "=== details for $U"
    bash "$(dirname "$0")/ci-details.sh" "$U" || echo "ci-details failed"
  done
fi
