# shellcheck shell=bash
# help:   ee-introspect   target EEs -> series/Python/exact version matrix; fails if requires_ansible or Python mismatch
# Usage: aci ee-introspect <EE image> [...]     (engine: ACI_CONTAINER_ENGINE, ansible-builder agent)
# Output: reports/ee/matrix.txt, lines "series python version image" (read by the GitLab component).
main() {
  [ $# -gt 0 ] || die "aci ee-introspect <image> [...]: no EE given"
  command -v "$ACI_CONTAINER_ENGINE" >/dev/null || die "ee-introspect needs $ACI_CONTAINER_ENGINE (ansible-builder VM agent)"
  aci_venv core >/dev/null   # PyYAML + packaging for ee_matrix.py
  local out=$ACI_REPORTS/ee work=$ACI_WORK/ee n=0 image
  rm -rf "$out" "$work"; mkdir -p "$out" "$work"
  for image in "$@"; do
    n=$((n + 1)); echo "$image" > "$work/$n.image"
    # --entrypoint: bypasses the EE entrypoint (dumb-init / AAP entrypoint); the image is not modified
    if ! run "$ACI_CONTAINER_ENGINE" run --rm --pull=missing --network none -e HOME=/tmp --entrypoint ansible "$image" --version \
         > "$work/$n.out" 2>&1; then
      cat "$work/$n.out" >&2; die "EE $image: 'ansible --version' failed (image missing from the mirror? no ansible-core?)"
    fi
  done
  python "$ACI_PY/ee_matrix.py" "$work" "$ACI_PYTHON_MAP" "$ACI_SRC" > "$out/matrix.txt" \
    || die "EEs incompatible with the collection (see above)"
  log "matrix derived from the EEs:"; sed 's/^/    /' "$out/matrix.txt" >&2
  # GitLab (static matrix): ACI_EE_EXPECT_CORES = matrix series; they must be exactly the series of
  # the EEs, otherwise the message gives the value to put in the ansible-core-versions input.
  if [ -n "${ACI_EE_EXPECT_CORES:-}" ]; then
    local want got
    want=$(echo "$ACI_EE_EXPECT_CORES" | grep -oE '[0-9]+\.[0-9]+' | sort -uV | xargs)
    got=$(awk '{print $1}' "$out/matrix.txt" | sort -uV | xargs)
    [ "$want" = "$got" ] || die "matrix ($want) differs from the EE series ($got): ansible-core-versions: [\"${got// /\", \"}\"]"
  fi
}
