# shellcheck shell=bash
# help:   certification   Red Hat certification checks (partner-certification-checker, share/aci/certification.env)
# Usage: aci certification [static]       guards + galaxy-importer + ansible-lint --profile=production
#        aci certification sanity-cores   sanity series to test (ACI_CERT_SANITY_CORES filtered by requires_ansible)
# The sanity part then runs per series: ACI_CORE=<series> ACI_PYTHON=3.12 aci sanity
cert_sanity_cores() {
  local min out="" c; min=$(aci_requires_minor)
  for c in $ACI_CERT_SANITY_CORES; do
    if [ -z "$min" ] || [ "${c#*.}" -ge "${min#*.}" ]; then out="$out $c"; fi
  done
  [ -n "$out" ] || die "all certification series ($ACI_CERT_SANITY_CORES) are excluded by requires_ansible >= $min"
  echo "$out" | xargs
}

main() {
  aci_cert_env
  case ${1:-static} in
    sanity-cores) cert_sanity_cores; return ;;
    static) ;;
    *) die "aci certification [static|sanity-cores]" ;;
  esac
  local out=$ACI_REPORTS/certification; rm -rf "$out"; mkdir -p "$out"
  log "reference: partner-certification-checker $ACI_CERT_CHECKER_VERSION (galaxy-importer $ACI_CERT_GALAXY_IMPORTER, ansible-lint $ACI_CERT_ANSIBLE_LINT, ansible-core $ACI_CERT_ANSIBLE_CORE, Python $ACI_CERT_PYTHON)"

  # dedicated venv, EXACT versions of the checker (not the general aci constraints)
  local py="python$ACI_CERT_PYTHON" key dir
  command -v "$py" >/dev/null || die "$py not found: certification runs on Python $ACI_CERT_PYTHON (AAP EEs)"
  # shellcheck disable=SC2086
  key=$( { "$py" -VV; echo "$ACI_CERT_ANSIBLE_CORE $ACI_CERT_GALAXY_IMPORTER $ACI_CERT_ANSIBLE_LINT $ACI_CERT_EXTRA_PIP"; } | sha256sum | cut -c1-12)
  dir=$ACI_CACHE/venv/certification-$key
  mkdir -p "$ACI_CACHE/venv"
  if command -v flock >/dev/null; then exec 9>"$dir.lock"; flock 9; fi
  if [ ! -f "$dir/.aci-ok" ]; then
    log "venv certification -> $dir"
    rm -rf "$dir"; "$py" -m venv "$dir" >&2
    # shellcheck disable=SC2086
    "$dir/bin/python" -m pip install -q "ansible-core==$ACI_CERT_ANSIBLE_CORE" "galaxy-importer==$ACI_CERT_GALAXY_IMPORTER" \
        "ansible-lint==$ACI_CERT_ANSIBLE_LINT" $ACI_CERT_EXTRA_PIP >&2
    touch "$dir/.aci-ok"
  fi
  export VIRTUAL_ENV=$dir PATH=$dir/bin:$PATH

  local rc=0
  # 1) explicit guards (sanity ignores, .ansible-lint, requires_ansible)
  run python "$ACI_PY/cert_guards.py" "$ACI_SRC" | tee "$out/guards.txt" || rc=1

  # 2) galaxy-importer, with the checker configuration (CHECK_REQUIRED_TAGS=True, RUN_ANSIBLE_LINT=False)
  local cfg=$ACI_WORK/cert-galaxy-importer.cfg; mkdir -p "$ACI_WORK"
  printf '[galaxy-importer]\nCHECK_REQUIRED_TAGS=%s\nRUN_ANSIBLE_LINT=%s\n' \
    "$ACI_CERT_IMPORTER_CHECK_REQUIRED_TAGS" "$ACI_CERT_IMPORTER_RUN_ANSIBLE_LINT" > "$cfg"
  aci_prepare_tree lint
  log "galaxy-importer $ACI_CERT_GALAXY_IMPORTER (CHECK_REQUIRED_TAGS=$ACI_CERT_IMPORTER_CHECK_REQUIRED_TAGS, RUN_ANSIBLE_LINT=$ACI_CERT_IMPORTER_RUN_ANSIBLE_LINT) -> $out/galaxy-importer.log"
  (cd "$out" && GALAXY_IMPORTER_CONFIG=$cfg run python -m galaxy_importer.main \
      --git-clone-path "$ACI_TREE_DEST" --output-path "$out" > "$out/galaxy-importer.log" 2>&1) || rc=1
  tail -n 5 "$out/galaxy-importer.log" >&2

  # 3) ansible-lint --profile=production (Galaxy dependencies already installed next to it: --offline)
  (cd "$ACI_SRC" && ANSIBLE_COLLECTIONS_PATH=$ACI_TREE_BASE run ansible-lint --offline --profile=production \
      --exclude dist --exclude reports --exclude tests/output "$@") || rc=1

  [ $rc -eq 0 ] || die "certification: at least one check failed (see $out)"
  log "static certification: OK; sanity to run on: $(cert_sanity_cores)"
}
