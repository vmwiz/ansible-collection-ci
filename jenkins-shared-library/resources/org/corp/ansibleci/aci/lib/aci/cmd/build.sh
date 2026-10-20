# shellcheck shell=bash
# aide:   build           ansible-galaxy collection build -> dist/<ns>-<nom>-<version>.tar.gz
main() {
  aci_venv core >/dev/null
  mkdir -p "$ACI_DIST"
  run ansible-galaxy collection build --force --output-path "$ACI_DIST" "$ACI_SRC" "$@"
}
