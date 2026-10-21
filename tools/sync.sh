#!/usr/bin/env bash
# Copies VOLONTAIRES du depot (les livrables sont publies dans des depots separes) :
#   1. ci-scripts/ (source canonique de `aci`) -> ressources de la bibliotheque Jenkins + MANIFEST lu par
#      aciInstall (la bibliotheque est chargee par Jenkins depuis SCM : la copie doit etre committee) ;
#   2. exemple-collection/corp.demo -> gitlab-ci-templates/tests/collection (collection d'essai du
#      pipeline du projet composant), sans Jenkinsfile ni .gitlab-ci.yml.
# Usage : tools/sync.sh          regenere les deux copies
#         tools/sync.sh --check  echoue si une copie a diverge (a lancer en CI et avant chaque tag)
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
src=$root/ci-scripts
dst=$root/jenkins-shared-library/resources/org/corp/ansibleci/aci
col_src=$root/exemple-collection/corp.demo
col_dst=$root/gitlab-ci-templates/tests/collection
files() { (cd "$1" && find VERSION bin lib share -type f ! -name '*.pyc' ! -path '*__pycache__*' | LC_ALL=C sort); }
colfiles() { (cd "$1" && find . -type f ! -path './Jenkinsfile' ! -path './.gitlab-ci.yml' ! -path '*__pycache__*' \
                ! -path './reports/*' ! -path './dist/*' ! -path './tests/output/*' | sed 's#^\./##' | LC_ALL=C sort); }
col_diff() {   # sortie vide = copies identiques
  diff <(colfiles "$col_src") <(colfiles "$col_dst") || true
  colfiles "$col_src" | while read -r f; do cmp -s "$col_src/$f" "$col_dst/$f" 2>/dev/null || echo "diverge : $f"; done
}
if [ "${1:-}" = --check ]; then
  diff <(files "$src") "$dst/MANIFEST" >/dev/null || { echo "MANIFEST obsolete : lancer tools/sync.sh" >&2; exit 1; }
  while read -r f; do cmp -s "$src/$f" "$dst/$f" || { echo "diverge : $f (lancer tools/sync.sh)" >&2; exit 1; }; done < "$dst/MANIFEST"
  extra=$(comm -13 "$dst/MANIFEST" <(cd "$dst" && find . -type f ! -name MANIFEST | sed 's#^\./##' | LC_ALL=C sort))
  [ -z "$extra" ] || { echo "fichiers en trop dans la copie Jenkins : $extra" >&2; exit 1; }
  d=$(col_diff)
  [ -z "$d" ] || { echo "collection d'essai GitLab divergente (lancer tools/sync.sh) :" >&2; echo "$d" >&2; exit 1; }
  echo "copies a jour : aci $(cat "$src/VERSION") (bibliotheque Jenkins) + collection d'essai GitLab"; exit 0
fi
rm -rf "$dst"; mkdir -p "$dst"
files "$src" | while read -r f; do install -D -m 0644 "$src/$f" "$dst/$f"; done
files "$src" > "$dst/MANIFEST"
rm -rf "$col_dst"; colfiles "$col_src" | while read -r f; do install -D -m 0644 "$col_src/$f" "$col_dst/$f"; done
echo "aci $(cat "$src/VERSION") -> $dst ($(wc -l < "$dst/MANIFEST") fichiers) ; corp.demo -> $col_dst"
