#!/usr/bin/env bash
# Keeps the GitLab component's test collection in sync with the example collection:
#   example-collection/corp.demo -> gitlab-ci-templates/tests/collection (without Jenkinsfile or .gitlab-ci.yml).
# The copy is deliberate: gitlab-ci-templates/ is published as its own repository (git subtree split).
# Usage: tools/sync.sh          regenerates the copy
#        tools/sync.sh --check  fails if the copy has diverged (run in CI and before every tag)
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
src=$root/example-collection/corp.demo
dst=$root/gitlab-ci-templates/tests/collection
files() { (cd "$1" && find . -type f ! -path './Jenkinsfile' ! -path './.gitlab-ci.yml' ! -path '*__pycache__*' \
             ! -path './reports/*' ! -path './dist/*' ! -path './tests/output/*' | sed 's#^\./##' | LC_ALL=C sort); }
if [ "${1:-}" = --check ]; then
  d=$( { diff <(files "$src") <(files "$dst") || true
         files "$src" | while read -r f; do cmp -s "$src/$f" "$dst/$f" 2>/dev/null || echo "diverged: $f"; done; } )
  [ -z "$d" ] || { echo "GitLab test collection out of date (run tools/sync.sh):" >&2; echo "$d" >&2; exit 1; }
  echo "GitLab test collection up to date"; exit 0
fi
rm -rf "$dst"; files "$src" | while read -r f; do install -D -m 0644 "$src/$f" "$dst/$f"; done
echo "corp.demo -> $dst"
