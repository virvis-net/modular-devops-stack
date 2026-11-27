#!/usr/bin/env bash
# Post a "stopped before opening a PR" comment on the issue.
# Usage: bash /opt/agent/comment-stop.sh <issue-number> <branch> "<reason>"
set -euo pipefail

ISSUE_NUMBER="${1:?usage: comment-stop.sh <issue-number> <branch> <reason>}"
BRANCH="${2:?missing branch}"
REASON="${3:?missing reason}"

: "${GITEA_API_URL:?}" "${GITEA_OWNER:?}" "${GITEA_REPOSITORY:?}" "${GITEA_ACCESS_TOKEN:?}"
API="$GITEA_API_URL/repos/$GITEA_OWNER/$GITEA_REPOSITORY"

jq -n --arg b "$BRANCH" --arg r "$REASON" \
  '{body:("Stopped before opening a PR.\nBranch: "+$b+"\nReason: "+$r)}' \
| curl -fsS -X POST \
    -H "Authorization: Bearer $GITEA_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d @- "$API/issues/$ISSUE_NUMBER/comments" \
| jq '{id, html_url}'
