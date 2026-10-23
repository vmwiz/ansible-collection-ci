# shellcheck shell=bash
# help:   importer        galaxy-importer on the `aci build` artifact (Galaxy / Automation Hub checks)
main() {
  aci_venv import >/dev/null
  local tarball; tarball=$(aci_tarball)
  [ -f "$tarball" ] || die "$tarball missing: run 'aci build' first"
  mkdir -p "$ACI_REPORTS/galaxy-importer"
  # galaxy-importer writes importer_result.json to the current directory
  (cd "$ACI_REPORTS/galaxy-importer" && GALAXY_IMPORTER_CONFIG=${ACI_IMPORTER_CFG:-$ACI_SHARE/galaxy-importer.cfg} \
      run python -m galaxy_importer.main "$tarball" "$@")
}
