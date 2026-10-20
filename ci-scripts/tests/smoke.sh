#!/usr/bin/env bash
# Tests rapides de `aci` sans reseau : aide, resolution serie/Python, specificateurs, erreurs.
# shellcheck disable=SC2015
set -euo pipefail
aci=${ACI_BIN:-$(cd "$(dirname "$0")/.." && pwd)/bin/aci}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/c" && printf 'namespace: corp\nname: demo\nversion: 1.0.0\n' > "$tmp/c/galaxy.yml"
cd "$tmp/c"; export ACI_CACHE=$tmp/cache
has() { local out; out=$("${@:2}" 2>/dev/null) || return 1; grep -Eq -- "$1" <<<"$out"; }
fail=0; ok() { echo "ok   $*"; }; ko() { echo "FAIL $*"; fail=1; }
has '^  sanity ' "$aci" help && ok help || ko help
has '^aci [0-9]+\.[0-9]+\.[0-9]+$' "$aci" version && ok version || ko version
has 'ansible-core   2\.18 \(ansible-core>=2\.18,<2\.19\)' "$aci" info && ok "serie par defaut 2.18 (AAP 2.6)" || ko "serie par defaut"
has '>=2\.22\.0a0,<2\.23' env ACI_CORE=2.22 ACI_PRERELEASE=2.22 "$aci" info && ok "pre-version 2.22" || ko "pre-version"
has '>=2\.22,<2\.23' env ACI_CORE=2.22 ACI_PRERELEASE= "$aci" info && ok "2.22 GA" || ko "2.22 GA"
ACI_CORE=9.9 "$aci" info >/dev/null 2>&1 && ko "serie inconnue acceptee" || ok "serie inconnue refusee"
"$aci" nope >/dev/null 2>&1 && ko "commande inconnue acceptee" || ok "commande inconnue refusee"
has 'ansible-core   2\.20 ' env ACI_CORE_VERSIONS='["2.19", "2.20", "2.22"]' ACI_PRERELEASE=2.22 "$aci" info && ok "defaut d'apres ACI_CORE_VERSIONS (forme GitLab)" || ko "ACI_CORE_VERSIONS"
has 'ansible-core==2\.16\.19' env ACI_CORE=2.16 ACI_CORE_PIN=2.16.19 "$aci" info && ok "ACI_CORE_PIN" || ko "ACI_CORE_PIN"
if command -v python3.12 >/dev/null; then
  has '^python         python3\.12$' env ACI_CORE=2.16 "$aci" info && ok "2.16 -> python3.12" || ko "2.16 -> python3.12"
else echo "skip 2.16 -> python3.12 (python3.12 absent de cet hote)"; fi
rc=0; ACI_CORE=2.22 ACI_PRERELEASE=2.22 ACI_PRERELEASE_EXIT_CODE=3 "$aci" publish >/dev/null 2>&1 || rc=$?
[ $rc -eq 3 ] && ok "pre-version : code 3" || ko "pre-version : code $rc"
rc=0; ACI_CORE=2.21 ACI_PRERELEASE_EXIT_CODE=3 "$aci" publish >/dev/null 2>&1 || rc=$?
[ $rc -eq 2 ] && ok "serie stable : code d'origine" || ko "serie stable : code $rc"
exit $fail
