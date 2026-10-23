# shellcheck shell=bash
# help:   lint            yamllint + antsibull-changelog lint + ansible-lint --offline
main() {
  aci_venv lint >/dev/null
  local cfg=$ACI_SHARE/yamllint.yml; [ -f "$ACI_SRC/.yamllint" ] && cfg=$ACI_SRC/.yamllint
  local -a files
  mapfile -t files < <(cd "$ACI_SRC" && find . \( -path ./.git -o -path ./reports -o -path ./dist -o -path ./tests/output \
      -o -name .nox -o -name .tox -o -name .venv \) -prune -o -type f \( -name '*.yml' -o -name '*.yaml' \) -print | sort)
  (cd "$ACI_SRC" && run yamllint --strict -c "$cfg" "${files[@]}")
  if [ -f "$ACI_SRC/changelogs/config.yaml" ]; then (cd "$ACI_SRC" && run antsibull-changelog lint); fi
  aci_prepare_tree lint
  # --offline: neither installs requirements.yml nor refreshes schemas (Internet)
  (cd "$ACI_SRC" && ANSIBLE_COLLECTIONS_PATH=$ACI_TREE_BASE run ansible-lint --offline \
      --exclude dist --exclude reports --exclude tests/output "$@")
}
