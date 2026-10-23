# shellcheck shell=bash
# help:   build           ansible-galaxy collection build -> dist/<ns>-<name>-<version>.tar.gz
main() {
  aci_venv core >/dev/null
  mkdir -p "$ACI_DIST"
  run ansible-galaxy collection build --force --output-path "$ACI_DIST" "$ACI_SRC" "$@"
}
