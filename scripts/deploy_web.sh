#!/usr/bin/env bash
# Builds the web demo and publishes it to the gh-pages branch on origin.
# GitHub Pages must be set to "Deploy from a branch: gh-pages / (root)".
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
SOURCE_REV=$(git rev-parse --short HEAD)

scripts/build_web.sh

WORKTREE=$(mktemp -d)
cleanup() { git -C "$ROOT" worktree remove --force "$WORKTREE" 2>/dev/null || true; }
trap cleanup EXIT

git fetch -q origin gh-pages 2>/dev/null || true
if git show-ref --verify --quiet refs/remotes/origin/gh-pages; then
  git worktree add -q -B gh-pages "$WORKTREE" origin/gh-pages
else
  git worktree add -q --detach "$WORKTREE"
  git -C "$WORKTREE" checkout -q --orphan gh-pages
  git -C "$WORKTREE" rm -rqf .
fi

rsync -a --delete --exclude .git build/web/ "$WORKTREE"/
touch "$WORKTREE/.nojekyll"   # serve files as-is, no Jekyll processing

git -C "$WORKTREE" add -A
if git -C "$WORKTREE" diff --cached --quiet; then
  echo "==> Nothing changed; not deploying."
  exit 0
fi
git -C "$WORKTREE" commit -q -m "Deploy web demo from $SOURCE_REV"
git -C "$WORKTREE" push -q origin gh-pages

url=$(git remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)([^/]+)/([^/.]+)(\.git)?#https://\2.github.io/\3/#')
echo "==> Deployed. Live in a minute or two at: $url"
