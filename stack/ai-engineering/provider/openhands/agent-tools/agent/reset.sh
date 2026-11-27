#!/usr/bin/env bash
# Usage: bash /opt/agent/reset.sh <repo-dir>
# Parks leftover work from a failed attempt in git stash, then returns to an up-to-date main.
set -euo pipefail

cd "${1:?usage: reset.sh <repo-dir>}"

CURRENT="$(git branch --show-current)"
case "$CURRENT" in
  main|issue/*) ;;
  *) echo "ERROR: refusing to reset '$CURRENT' (only main and issue/* are reset)" >&2; exit 2 ;;
esac

git merge --abort 2>/dev/null || true
git rebase --abort 2>/dev/null || true

# Step 1: tracked changes (this also restores a modified .gitignore)
if [ -n "$(git status --short --untracked-files=no)" ]; then
  git stash push -m "$CURRENT"
fi

# Step 2: untracked files, judged by the restored ignore rules.
# vendor, node_modules and .env stay put because they are ignored.
if [ -n "$(git status --short)" ]; then
  git stash push --include-untracked -m "$CURRENT (untracked)"
fi

git checkout main
git fetch origin
git merge --ff-only origin/main
echo "RESET ok. Parked work: $(git stash list | grep -c "$CURRENT" || true) stash entries for $CURRENT"
