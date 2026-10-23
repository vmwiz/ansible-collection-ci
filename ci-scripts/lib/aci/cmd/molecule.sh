# shellcheck shell=bash
# help:   molecule        molecule test --all (extensions/molecule, ansible-native) - agent with podman
main() {
  if [ ! -d "$ACI_SRC/extensions/molecule" ]; then log "no extensions/molecule: nothing to do"; return 0; fi
  command -v "$ACI_CONTAINER_ENGINE" >/dev/null || die "molecule needs $ACI_CONTAINER_ENGINE (ansible-builder VM agent)"
  aci_venv molecule >/dev/null
  # shellcheck disable=SC2086
  aci_prime ${ACI_MOLECULE_IMAGES:-ubuntu2404 fedora40}
  aci_prepare_tree molecule
  local -a args=("$@"); [ ${#args[@]} -gt 0 ] || args=(--all)
  (cd "$ACI_TREE_DEST" && ANSIBLE_COLLECTIONS_PATH=$ACI_TREE_BASE run molecule test "${args[@]}")
}
