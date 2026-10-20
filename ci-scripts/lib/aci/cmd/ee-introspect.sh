# shellcheck shell=bash
# aide:   ee-introspect   EE cibles -> matrice serie/Python/version exacte ; echec si requires_ansible ou Python incoherent
# Usage : aci ee-introspect <image EE> [...]     (moteur : ACI_CONTAINER_ENGINE, agent ansible-builder)
# Sortie : reports/ee/matrix.txt, lignes "serie python version image" (lue par Jenkins / GitLab).
main() {
  [ $# -gt 0 ] || die "aci ee-introspect <image> [...] : aucune EE"
  command -v "$ACI_CONTAINER_ENGINE" >/dev/null || die "ee-introspect exige $ACI_CONTAINER_ENGINE (agent VM ansible-builder)"
  aci_venv core >/dev/null   # PyYAML + packaging pour ee_matrix.py
  local out=$ACI_REPORTS/ee work=$ACI_WORK/ee n=0 image
  rm -rf "$out" "$work"; mkdir -p "$out" "$work"
  for image in "$@"; do
    n=$((n + 1)); echo "$image" > "$work/$n.image"
    # --entrypoint : ignore l'entrypoint des EE (dumb-init / entrypoint AAP) ; aucune modification de l'image
    if ! run "$ACI_CONTAINER_ENGINE" run --rm --pull=missing --network none -e HOME=/tmp --entrypoint ansible "$image" --version \
         > "$work/$n.out" 2>&1; then
      cat "$work/$n.out" >&2; die "EE $image : 'ansible --version' impossible (image absente du miroir ? pas d'ansible-core ?)"
    fi
  done
  python "$ACI_PY/ee_matrix.py" "$work" "$ACI_PYTHON_MAP" "$ACI_SRC" > "$out/matrix.txt" \
    || die "EE incompatibles avec la collection (voir ci-dessus)"
  log "matrice derivee des EE :"; sed 's/^/    /' "$out/matrix.txt" >&2
  # GitLab (matrice statique) : ACI_EE_EXPECT_CORES = series de la matrice ; elles doivent etre
  # exactement celles des EE, sinon on indique la valeur a mettre dans l'input ansible-core-versions.
  if [ -n "${ACI_EE_EXPECT_CORES:-}" ]; then
    local want got
    want=$(echo "$ACI_EE_EXPECT_CORES" | grep -oE '[0-9]+\.[0-9]+' | sort -uV | xargs)
    got=$(awk '{print $1}' "$out/matrix.txt" | sort -uV | xargs)
    [ "$want" = "$got" ] || die "matrice ($want) differente des series des EE ($got) : ansible-core-versions: [\"${got// /\", \"}\"]"
  fi
}
