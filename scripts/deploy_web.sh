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

# Exclude nested .gitignore files: wasm-pack writes one containing "*" into
# pkg/, which would silently drop the Rust WebAssembly from the deploy.
rsync -a --delete --exclude .git --exclude .gitignore --exclude .DS_Store \
  --exclude .last_build_id build/web/ "$WORKTREE"/
rm -f "$WORKTREE/.DS_Store" "$WORKTREE/.last_build_id"  # left by older deploys
touch "$WORKTREE/.nojekyll"   # serve files as-is, no Jekyll processing

git -C "$WORKTREE" add -A
if [[ -z "$(git -C "$WORKTREE" ls-files pkg/*.wasm)" ]]; then
  echo "error: pkg/*.wasm missing from the deploy; aborting." >&2
  exit 1
fi
if git -C "$WORKTREE" diff --cached --quiet; then
  echo "==> Nothing changed; not deploying."
  exit 0
fi
git -C "$WORKTREE" commit -q -m "Deploy web demo from $SOURCE_REV"
git -C "$WORKTREE" push -q origin gh-pages

url=$(git remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)([^/]+)/([^/.]+)(\.git)?#https://\2.github.io/\3/#')
echo "==> Deployed. Live in a minute or two at: $url"
