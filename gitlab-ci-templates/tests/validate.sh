#!/usr/bin/env bash
# Validation hors GitLab du composant : rendu des inputs (render.py) puis schema officiel GitLab
# (app/assets/javascripts/editor/schema/ci.json), jeux d'inputs valides/invalides, simulation des jobs
# par contexte, exemples utilisateur, coherence de version avec ci-scripts/VERSION.
# Usage : validate.sh [schema.json]   (defaut : $GITLAB_CI_SCHEMA ou telechargement depuis gitlab.com)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); cd "$here/.."
schema=${1:-${GITLAB_CI_SCHEMA:-}}
[ -n "$schema" ] && schema=$(readlink -f "$OLDPWD/$schema" 2>/dev/null || readlink -f "$schema")
if [ -z "$schema" ]; then
  schema=$(mktemp --suffix .json)
  curl -sfL -o "$schema" https://gitlab.com/gitlab-org/gitlab/-/raw/master/app/assets/javascripts/editor/schema/ci.json
fi
T=templates/ansible-collection/template.yml out=$(mktemp -d) fail=0
ok() { echo "ok   $*"; }; ko() { echo "KO   $*"; fail=1; }
for i in tests/inputs/minimal.yml tests/inputs/complet.yml; do
  n=$(basename "$i" .yml)
  if python3 tests/render.py "$T" -i "$i" --out "$out/$n.yml" &&
     check-jsonschema -q --schemafile "$schema" "$out/$n.yml" "$out/$n.spec.yml"; then ok "rendu + schema : $n"; else ko "rendu + schema : $n"; fi
done
if python3 tests/render.py "$T" -i tests/inputs/invalide.yml > "$out/inv.txt" 2>&1; then ko "inputs invalides acceptes"
else grep -q "input inconnu 'ansible-core-version'" "$out/inv.txt" && ok "inputs invalides refuses"; fi
if check-jsonschema -q --schemafile "$schema" examples/*.gitlab-ci.yml; then ok "exemples utilisateur (schema)"; else ko "exemples"; fi
# simulation des jobs : contexte -> jobs attendus
# shellcheck disable=SC2016  # messages litteraux
expect() {  # inputs contexte motif-present [motif-absent]
  local l; l=$(python3 tests/render.py "$T" -i "tests/inputs/$1.yml" --jobs "$2")
  if grep -q -- "$3" <<<"$l" && { [ -z "${4:-}" ] || ! grep -q -- "$4" <<<"$l"; }; then ok "jobs $1/$2 : '$3'${4:+ sans '$4'}"; else ko "jobs $1/$2 : '$3' ${4:-}"; echo "$l"; fi
}
expect minimal branch 'aci-sanity-venv \[ACI_CORE=2.16\]' 'aci-sanity-docker'
expect minimal default 'aci-sanity-docker \[ACI_CORE=2.18\]' 'aci-sanity-venv'
expect minimal mr 'aci-changelog'
expect minimal branch 'aci-certification-sanity' 'aci-changelog'
expect minimal tag 'aci-publish'
expect minimal branch 'aci-units-venv' 'aci-publish'
expect complet branch 'aci-ee-introspect'
expect complet branch 'aci-optional-cores .*allow_failure=true'
expect complet branch 'aci-spotter .*allow_failure=true'
expect complet branch 'aci-integration \[ACI_INTEGRATION_IMAGE=ubuntu2404\]'
# version des scripts attendue = ci-scripts/VERSION
v=$(cat ../ci-scripts/VERSION 2>/dev/null || true)
if [ -z "$v" ] || grep -q "ACI_EXPECTED_VERSION: \"$v\"" "$T"; then ok "ACI_EXPECTED_VERSION = ${v:-?}"; else ko "ACI_EXPECTED_VERSION different de ci-scripts/VERSION ($v)"; fi
rm -rf "$out"; exit $fail
