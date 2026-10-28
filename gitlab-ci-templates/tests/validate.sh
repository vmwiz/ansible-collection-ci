#!/usr/bin/env bash
# Off-GitLab validation of the component: input rendering (render.py) then the official GitLab schema
# (app/assets/javascripts/editor/schema/ci.json), valid/invalid input sets, job simulation per
# context, user examples, version consistency with ci-scripts/VERSION.
# Usage: validate.sh [schema.json]   (default: $GITLAB_CI_SCHEMA or download from gitlab.com)
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
for i in tests/inputs/minimal.yml tests/inputs/complete.yml; do
  n=$(basename "$i" .yml)
  if python3 tests/render.py "$T" -i "$i" --out "$out/$n.yml" &&
     check-jsonschema -q --schemafile "$schema" "$out/$n.yml" "$out/$n.spec.yml"; then ok "render + schema: $n"; else ko "render + schema: $n"; fi
done
if python3 tests/render.py "$T" -i tests/inputs/invalid.yml > "$out/inv.txt" 2>&1; then ko "invalid inputs accepted"
else grep -q "unknown input 'ansible-core-version'" "$out/inv.txt" && ok "invalid inputs refused"; fi
if check-jsonschema -q --schemafile "$schema" examples/*.gitlab-ci.yml; then ok "user examples (schema)"; else ko "examples"; fi
# job simulation: context -> expected jobs
# shellcheck disable=SC2016  # literal messages
expect() {  # inputs context present-pattern [absent-pattern]
  local l; l=$(python3 tests/render.py "$T" -i "tests/inputs/$1.yml" --jobs "$2")
  if grep -q -- "$3" <<<"$l" && { [ -z "${4:-}" ] || ! grep -q -- "$4" <<<"$l"; }; then ok "jobs $1/$2: '$3'${4:+ without '$4'}"; else ko "jobs $1/$2: '$3' ${4:-}"; echo "$l"; fi
}
expect minimal branch 'aci-sanity-venv \[ACI_CORE=2.16\]' 'aci-sanity-docker'
expect minimal default 'aci-sanity-docker \[ACI_CORE=2.18\]' 'aci-sanity-venv'
expect minimal mr 'aci-changelog'
expect minimal branch 'aci-certification-sanity' 'aci-changelog'
expect minimal tag 'aci-publish'
expect minimal branch 'aci-units-venv' 'aci-publish'
expect complete branch 'aci-ee-introspect'
expect complete branch 'aci-optional-cores .*allow_failure=true'
expect complete branch 'aci-spotter .*allow_failure=true'
expect complete branch 'aci-integration \[ACI_INTEGRATION_IMAGE=ubuntu2404\]'
# block order (needs / stages): static analysis < ansible-test < container tests < build < certification < publish
chain() {  # inputs context job1 job2 ... : each job runs strictly after the previous one
  local o lv prev=-1 j ok=1; o=$(python3 tests/render.py "$T" -i "tests/inputs/$1.yml" --order "$2") || { ko "order $1/$2: $o"; return; }
  for j in "${@:3}"; do
    lv=$(awk -v j="$j" '$2 == j {print $1}' <<<"$o"); [ -n "$lv" ] && [ "$lv" -gt "$prev" ] || ok=0; prev=${lv:-99}
  done
  if [ $ok = 1 ]; then ok "order $1/$2: ${*:3}"; else ko "order $1/$2: ${*:3}"; echo "$o"; fi
}
chain complete tag aci-lint aci-sanity-docker aci-integration aci-build aci-certification aci-publish
chain complete tag aci-spotter aci-units-docker aci-molecule aci-build
chain complete mr aci-changelog aci-sanity-venv aci-integration aci-build aci-certification
chain minimal tag aci-security aci-sanity-docker aci-build aci-certification aci-publish
chain minimal branch aci-docs aci-certification-sanity aci-build aci-certification
if python3 tests/render.py "$T" -i tests/inputs/minimal.yml --job aci-publish --context tag --emit /dev/null &&
   [ "$(python3 - "$T" <<'PY'
import sys, yaml
body = list(yaml.safe_load_all(open(sys.argv[1]).read().replace("!reference", "")))[1]
print(body["aci-publish"].get("dependencies"), "needs" in body["aci-publish"], body["aci-certification"]["needs"][0])
PY
)" = "['aci-build'] False {'job': 'aci-build', 'optional': True}" ]; then ok "publish/certification use the aci-build dist/ artifact"
else ko "publish/certification artifact"; fi
# expected scripts version = ci-scripts/VERSION
v=$(cat ../ci-scripts/VERSION 2>/dev/null || true)
if [ -z "$v" ] || grep -q "ACI_EXPECTED_VERSION: \"$v\"" "$T"; then ok "ACI_EXPECTED_VERSION = ${v:-?}"; else ko "ACI_EXPECTED_VERSION differs from ci-scripts/VERSION ($v)"; fi
rm -rf "$out"; exit $fail
