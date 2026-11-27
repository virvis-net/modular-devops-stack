#!/usr/bin/env bash
# Create and verify the pull request.
# Usage: bash /opt/agent/create-pr.sh <issue-number> <branch> <issue-title> "<CI result>"
set -euo pipefail

ISSUE_NUMBER="${1:?usage: create-pr.sh <issue-number> <branch> <title> <ci-result>}"
BRANCH="${2:?missing branch}"
TITLE="${3:?missing title}"
CI_RESULT="${4:?missing CI result}"

: "${GITEA_API_URL:?}" "${GITEA_OWNER:?}" "${GITEA_REPOSITORY:?}" "${GITEA_ACCESS_TOKEN:?}"
API="$GITEA_API_URL/repos/$GITEA_OWNER/$GITEA_REPOSITORY"

CREATED="$(
  jq -n \
    --arg h "$BRANCH" \
    --arg t "$TITLE" \
    --arg n "$ISSUE_NUMBER" \
    --arg ci "$CI_RESULT" \
    '{head:$h, base:"main", title:("Issue #"+$n+": "+$t), body:("Closes #"+$n+"\n\nCI: "+$ci)}' \
  | curl -fsS -X POST \
      -H "Authorization: Bearer $GITEA_ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d @- "$API/pulls"
)"

echo "$CREATED" | jq '{number, html_url, state, head: .head.ref}'

PR_NUMBER="$(echo "$CREATED" | jq -r '.number')"

echo "--- verification ---"
curl -fsS -H "Authorization: Bearer $GITEA_ACCESS_TOKEN" "$API/pulls/$PR_NUMBER" \
  | jq '{number, html_url, state, head: .head.ref, base: .base.ref}'
