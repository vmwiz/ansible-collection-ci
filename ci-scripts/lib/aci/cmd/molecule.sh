# shellcheck shell=bash
# aide:   molecule        molecule test --all (extensions/molecule, ansible-native) - agent avec podman
main() {
  if [ ! -d "$ACI_SRC/extensions/molecule" ]; then log "pas de extensions/molecule : rien a faire"; return 0; fi
  command -v "$ACI_CONTAINER_ENGINE" >/dev/null || die "molecule exige $ACI_CONTAINER_ENGINE (agent VM ansible-builder)"
  aci_venv molecule >/dev/null
  # shellcheck disable=SC2086
  aci_prime ${ACI_MOLECULE_IMAGES:-ubuntu2404 fedora40}
  aci_prepare_tree molecule
  local -a args=("$@"); [ ${#args[@]} -gt 0 ] || args=(--all)
  (cd "$ACI_TREE_DEST" && ANSIBLE_COLLECTIONS_PATH=$ACI_TREE_BASE run molecule test "${args[@]}")
}
