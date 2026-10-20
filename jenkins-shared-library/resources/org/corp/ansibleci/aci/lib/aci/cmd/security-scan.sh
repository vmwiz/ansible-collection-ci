# shellcheck shell=bash
# aide:   security-scan   ansible-security-scanner (100 % local) ; echec selon ACI_SECURITY_FAIL_ON=high|critical|none
main() {
  aci_venv security >/dev/null
  local out=$ACI_REPORTS/security src=$ACI_WORK/security-src rc=0
  mkdir -p "$out"; rm -rf "$src"; mkdir -p "$src"
  # pas d'option d'exclusion dans le scanner : on analyse une copie propre
  tar -C "$ACI_SRC" --exclude=./.git --exclude=./reports --exclude=./dist --exclude=./tests/output -cf - . | tar -C "$src" -xf -
  local -a common=(ansible-security-scanner --directory "$src" --jobs 4)
  [ -n "${ACI_SECURITY_SEVERITY:-}" ] && common+=(--severity "$ACI_SECURITY_SEVERITY")   # filtre d'affichage
  run "${common[@]}" --format sarif --output "$out/ansible-security-scanner.sarif" --exit-zero
  [ -n "${GITLAB_CI:-}" ] && run "${common[@]}" --format gitlab-sast --output "$out/gl-sast-report.json" --exit-zero
  run "${common[@]}" --format junit --output "$out/ansible-security-scanner.xml" "$@" || rc=$?
  # codes retour du scanner : 0 rien >= HIGH ; 1 HIGH ; 2 CRITICAL (ou erreur d'usage)
  case ${ACI_SECURITY_FAIL_ON:-high} in
    high)     [ $rc -eq 0 ] || die "ansible-security-scanner : constats HIGH/CRITICAL (code $rc)" ;;
    critical) [ $rc -le 1 ] || die "ansible-security-scanner : constats CRITICAL (code $rc)" ;;
    none)     [ $rc -eq 0 ] || warn "ansible-security-scanner : constats (code $rc), non bloquant" ;;
    *)        die "ACI_SECURITY_FAIL_ON='${ACI_SECURITY_FAIL_ON}' : valeurs high|critical|none" ;;
  esac
}
