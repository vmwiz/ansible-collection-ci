# shellcheck shell=bash
# aide:   ee-units        [POC] ansible-test units DANS une EE cible (Python et bibliotheques de l'EE) - podman
# Usage : aci ee-units <image EE> [args ansible-test]   NON VALIDE sans EE Red Hat reelle (voir PROPOSITION.md).
main() {
  local image=${1:-}; [ -n "$image" ] || die "aci ee-units <image EE>"; shift
  if [ ! -d "$ACI_SRC/tests/unit" ]; then log "pas de tests/unit : rien a faire"; return 0; fi
  command -v "$ACI_CONTAINER_ENGINE" >/dev/null || die "ee-units exige $ACI_CONTAINER_ENGINE (agent VM ansible-builder)"
  aci_venv core >/dev/null
  aci_prepare_tree units
  local ns name label rel rc=0
  read -r ns name _ < <(aci_meta)
  label=ee-units-$(basename "${image//:/-}")
  rel=ansible_collections/$ns/$name
  local -a extra=()
  [ -f /etc/pip.conf ] && extra+=(-v /etc/pip.conf:/etc/pip.conf:ro)   # pytest & co depuis Nexus
  [ "$ACI_CONTAINER_ENGINE" = podman ] && extra+=(--userns=keep-id)
  # shellcheck disable=SC2016  # le script est evalue dans l'EE
  run "$ACI_CONTAINER_ENGINE" run --rm --entrypoint sh -e HOME=/tmp --user "$(id -u):$(id -g)" "${extra[@]}" \
      -v "$ACI_TREE_BASE:/work:Z" -w "/work/$rel" "$image" -c '
        py=$(ansible --version | sed -n "s/^ *python version = \([0-9]*\.[0-9]*\).*/\1/p")
        exec ansible-test units --venv --venv-system-site-packages --python "$py" --requirements -v "$@"' ee-units "$@" || rc=$?
  if [ -d "$ACI_TREE_DEST/tests/output" ]; then
    rm -rf "${ACI_REPORTS:?}/$label"; mkdir -p "$ACI_REPORTS/$label"
    tar -C "$ACI_TREE_DEST/tests/output" --exclude=./.tmp -cf - . | tar -C "$ACI_REPORTS/$label" -xf -
  fi
  return "$rc"
}
