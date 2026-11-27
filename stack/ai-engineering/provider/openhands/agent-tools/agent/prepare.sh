#!/usr/bin/env bash
# Verify a clean tree, update main, create the issue branch.
# Usage: bash /opt/agent/prepare.sh <branch-name>   (run from workspace/app)
set -euo pipefail

BRANCH="${1:?usage: prepare.sh <branch-name>}"

if ! [[ "$BRANCH" =~ ^[A-Za-z0-9._/-]+$ ]]; then
  echo "ERROR: unsafe branch name" >&2
  exit 2
fi

git rev-parse --is-inside-work-tree >/dev/null

STATUS="$(git status --short)"
if [ -n "$STATUS" ]; then
  echo "ERROR: working tree is not clean:" >&2
  echo "$STATUS" >&2
  exit 3
fi

git fetch origin
git checkout main
git merge --ff-only origin/main
git checkout -b "$BRANCH"

echo "BRANCH=$(git branch --show-current)"
