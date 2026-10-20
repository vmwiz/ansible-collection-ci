#!/usr/bin/env bash
# Copie ci-scripts/ (source canonique de `aci`) dans les ressources de la bibliotheque Jenkins
# et regenere le MANIFEST lu par l'etape aciInstall.   --check : echoue si la copie a diverge (CI).
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
src=$root/ci-scripts
dst=$root/jenkins-shared-library/resources/org/corp/ansibleci/aci
files() { (cd "$1" && find VERSION bin lib share -type f ! -name '*.pyc' ! -path '*__pycache__*' | LC_ALL=C sort); }
if [ "${1:-}" = --check ]; then
  diff <(files "$src") "$dst/MANIFEST" >/dev/null || { echo "MANIFEST obsolete : lancer tools/sync-aci.sh" >&2; exit 1; }
  while read -r f; do cmp -s "$src/$f" "$dst/$f" || { echo "diverge : $f" >&2; exit 1; }; done < "$dst/MANIFEST"
  echo "copie aci de la bibliotheque Jenkins a jour ($(cat "$src/VERSION"))"; exit 0
fi
rm -rf "$dst"; mkdir -p "$dst"
files "$src" | while read -r f; do install -D -m 0644 "$src/$f" "$dst/$f"; done
files "$src" > "$dst/MANIFEST"
echo "aci $(cat "$src/VERSION") -> $dst ($(wc -l < "$dst/MANIFEST") fichiers)"
