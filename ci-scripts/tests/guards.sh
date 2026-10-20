#!/usr/bin/env bash
# Tests des garde-fous de certification (cert_guards.py) et du controle de fragment de changelog,
# sur des copies modifiees de exemple-collection/corp.demo. Prerequis : python3 avec PyYAML, git.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd); demo=$(cd "$here/../exemple-collection/corp.demo" && pwd)
aci=${ACI_BIN:-$here/bin/aci}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0; ok() { echo "ok   $*"; }; ko() { echo "FAIL $*"; fail=1; }
set -a; # shellcheck source=/dev/null
. "$here/share/aci/certification.env"; set +a
py=${PYTHON:-python3}

cp -r "$demo" "$tmp/good"
if $py "$here/lib/aci/py/cert_guards.py" "$tmp/good" >/dev/null; then ok "collection exemple conforme"; else ko "collection exemple"; fi

cp -r "$demo" "$tmp/bad"; mkdir -p "$tmp/bad/tests/sanity"
printf 'plugins/modules/hello.py validate-modules:parameter-state-invalid-choice\nplugins/modules/hello.py pylint:disallowed-name # aci-derogation: OPS-42\nplugins/modules/hello.py shebang\n' > "$tmp/bad/tests/sanity/ignore-2.16.txt"
printf 'profile: moderate\nskip_list: [no-changed-when]\nexclude_paths: [roles/, extensions/molecule/]\n' > "$tmp/bad/.ansible-lint"
echo "roles/motd/tasks/main.yml unnamed-task" > "$tmp/bad/.ansible-lint-ignore"
sed -i "s/^requires_ansible:.*/requires_ansible: '>=2.19.0'/" "$tmp/bad/meta/runtime.yml"
out=$($py "$here/lib/aci/py/cert_guards.py" "$tmp/bad" || true)
for pat in "parameter-state-invalid-choice" "derogation : OPS-42" "profile 'moderate'" "'no-changed-when' dans skip_list" \
           "exclude_paths 'roles/'" "'unnamed-task' ignoree" "borne basse 2.19" "6 erreur"; do
  if grep -q -- "$pat" <<<"$out"; then ok "garde-fou : $pat"; else ko "garde-fou : $pat"; fi
done
if grep -q "shebang" <<<"$out"; then ko "shebang (autorise) signale"; else ok "ignore autorise (shebang) accepte"; fi

# fragment de changelog : depot avec branche main + branche de PR
cp -r "$demo" "$tmp/repo"; cd "$tmp/repo"
git init -q -b main && git add -A && git -c user.name=t -c user.email=t@t commit -qm init
git clone -q --bare . "$tmp/origin.git" && git remote add origin "$tmp/origin.git" && git fetch -q origin
git checkout -q -b feature && echo "# x" >> plugins/modules/hello.py && git -c user.name=t -c user.email=t@t commit -qam change
export ACI_CACHE=${ACI_CACHE:-$tmp/cache}
if CHANGE_ID=1 CHANGE_TARGET=main ACI_SRC=$PWD "$aci" changelog-check >/dev/null 2>&1; then ko "PR sans fragment acceptee"; else ok "PR sans fragment refusee"; fi
if CHANGE_ID=1 CHANGE_TARGET=main CHANGE_TITLE="fix [skip-changelog]" ACI_SRC=$PWD "$aci" changelog-check >/dev/null 2>&1; then ok "exemption skip-changelog"; else ko "exemption"; fi
if ACI_SRC=$PWD "$aci" changelog-check >/dev/null 2>&1; then ok "hors PR : ignore"; else ko "hors PR"; fi
printf 'minor_changes:\n  - hello - message.\n' > changelogs/fragments/1-hello.yml
git add -A && git -c user.name=t -c user.email=t@t commit -qm frag
if CI_MERGE_REQUEST_IID=1 CI_MERGE_REQUEST_TARGET_BRANCH_NAME=main ACI_SRC=$PWD "$aci" changelog-check >/dev/null 2>&1; then ok "MR avec fragment (+ antsibull-changelog lint)"; else ko "MR avec fragment"; fi
exit $fail
