# shellcheck shell=bash
# aide:   importer        galaxy-importer sur l'artefact de `aci build` (controles Galaxy / Automation Hub)
main() {
  aci_venv import >/dev/null
  local tarball; tarball=$(aci_tarball)
  [ -f "$tarball" ] || die "$tarball absent : lancer d'abord 'aci build'"
  mkdir -p "$ACI_REPORTS/galaxy-importer"
  # galaxy-importer ecrit importer_result.json dans le repertoire courant
  (cd "$ACI_REPORTS/galaxy-importer" && GALAXY_IMPORTER_CONFIG=${ACI_IMPORTER_CFG:-$ACI_SHARE/galaxy-importer.cfg} \
      run python -m galaxy_importer.main "$tarball" "$@")
}
