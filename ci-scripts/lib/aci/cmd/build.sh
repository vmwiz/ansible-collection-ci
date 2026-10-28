# shellcheck shell=bash
# help:   build           ansible-galaxy collection build -> dist/<ns>-<name>-<version>.tar.gz
main() {
  aci_venv core >/dev/null
  mkdir -p "$ACI_DIST"
  run ansible-galaxy collection build --force --output-path "$ACI_DIST" "$ACI_SRC" "$@"
  aci_dist_tarball >/dev/null   # logs the sha256 of the artifact the next steps (importer, certification, publish) use
}
