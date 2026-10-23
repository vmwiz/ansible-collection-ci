# shellcheck shell=bash
# help:   security-scan   ansible-security-scanner (fully local); fails according to ACI_SECURITY_FAIL_ON=high|critical|none
main() {
  aci_venv security >/dev/null
  local out=$ACI_REPORTS/security src=$ACI_WORK/security-src rc=0
  mkdir -p "$out"; rm -rf "$src"; mkdir -p "$src"
  # the scanner has no exclude option: scan a clean copy
  tar -C "$ACI_SRC" --exclude=./.git --exclude=./reports --exclude=./dist --exclude=./tests/output -cf - . | tar -C "$src" -xf -
  local -a common=(ansible-security-scanner --directory "$src" --jobs 4)
  [ -n "${ACI_SECURITY_SEVERITY:-}" ] && common+=(--severity "$ACI_SECURITY_SEVERITY")   # display filter
  run "${common[@]}" --format sarif --output "$out/ansible-security-scanner.sarif" --exit-zero
  [ -n "${GITLAB_CI:-}" ] && run "${common[@]}" --format gitlab-sast --output "$out/gl-sast-report.json" --exit-zero
  run "${common[@]}" --format junit --output "$out/ansible-security-scanner.xml" "$@" || rc=$?
  # scanner exit codes: 0 nothing >= HIGH; 1 HIGH; 2 CRITICAL (or usage error)
  case ${ACI_SECURITY_FAIL_ON:-high} in
    high)     [ $rc -eq 0 ] || die "ansible-security-scanner: HIGH/CRITICAL findings (code $rc)" ;;
    critical) [ $rc -le 1 ] || die "ansible-security-scanner: CRITICAL findings (code $rc)" ;;
    none)     [ $rc -eq 0 ] || warn "ansible-security-scanner: findings (code $rc), non-blocking" ;;
    *)        die "ACI_SECURITY_FAIL_ON='${ACI_SECURITY_FAIL_ON}': allowed values high|critical|none" ;;
  esac
}
