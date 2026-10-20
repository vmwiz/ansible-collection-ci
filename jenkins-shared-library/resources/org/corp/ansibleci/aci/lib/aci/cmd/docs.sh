# shellcheck shell=bash
# aide:   docs            antsibull-docs lint-collection-docs (documentation des plugins et roles)
main() {
  aci_venv docs >/dev/null
  aci_prepare_tree docs
  ANSIBLE_COLLECTIONS_PATH=$ACI_TREE_BASE run antsibull-docs lint-collection-docs --plugin-docs "$ACI_TREE_DEST" "$@"
}
