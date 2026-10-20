# shellcheck shell=bash
# aide:   spotter         Steampunk Spotter vers l'instance privee (SPOTTER_ENDPOINT, SPOTTER_TOKEN, SPOTTER_CACERT)
main() {
  aci_venv security >/dev/null
  local out=$ACI_REPORTS/spotter; mkdir -p "$out"
  local -a scan=(spotter --no-color scan --origin ci --no-progress --no-docs-url
                 --ansible-version "${ACI_SPOTTER_ANSIBLE_VERSION:-2.20}"
                 --exclude-paths dist --exclude-paths reports --exclude-paths tests/output)
  if [ "${ACI_SPOTTER_EXPORT_ONLY:-false}" = true ]; then
    run "${scan[@]}" --export-payload "$out/spotter-payload.json" "$@" "$ACI_SRC"   # aucun appel reseau
    return
  fi
  [ -n "${SPOTTER_ENDPOINT:-}" ] || die "SPOTTER_ENDPOINT non defini : sans lui la CLI vise le SaaS https://spotter.steampunk.si/api"
  [ -n "${SPOTTER_TOKEN:-}${SPOTTER_API_TOKEN:-}" ] || die "SPOTTER_TOKEN absent (credential CI)"
  run "${scan[@]}" --display-level "${ACI_SPOTTER_DISPLAY_LEVEL:-error}" \
      --junit-xml "$out/spotter.xml" --sarif "$out/spotter.sarif" "$@" "$ACI_SRC"
}
