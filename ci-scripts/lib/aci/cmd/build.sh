# shellcheck shell=bash
# help:   build           ansible-galaxy collection build of ACI_SRC -> $ACI_DIST/<ns>-<name>-<version>.tar.gz
main() {
  aci_venv core >/dev/null
  mkdir -p "$ACI_DIST"; rm -f "$ACI_DIST"/*.tar.gz   # outside ACI_SRC; only this tarball is then archived/stashed
  run ansible-galaxy collection build --force --output-path "$ACI_DIST" "$ACI_SRC" "$@"
  aci_dist_tarball >/dev/null   # logs the sha256 of the artifact the next steps (importer, certification, publish) use
}
