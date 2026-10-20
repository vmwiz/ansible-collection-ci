# shellcheck shell=bash
# Fonctions communes de `aci` (charge par bin/aci). Aucune logique specifique a Jenkins ou GitLab.
set -euo pipefail

ACI_LIB=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ACI_HOME=$(cd "$ACI_LIB/../.." && pwd)
ACI_SHARE=$ACI_HOME/share/aci
ACI_PY=$ACI_LIB/py
export ACI_VERSION; ACI_VERSION=$(cat "$ACI_HOME/VERSION" 2>/dev/null || echo dev)

ACI_SRC=$(cd "${ACI_SRC:-$PWD}" && pwd)                # racine de la collection (checkout)
ACI_REPORTS=${ACI_REPORTS:-$ACI_SRC/reports}
ACI_DIST=${ACI_DIST:-$ACI_SRC/dist}
ACI_WORK=${ACI_WORK:-${TMPDIR:-/tmp}/aci-$(id -u)/$(basename "$ACI_SRC")}
ACI_CACHE=${ACI_CACHE:-${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/ansible-ci}
ACI_TEST_MODE=${ACI_TEST_MODE:-venv}
ACI_PRERELEASE=${ACI_PRERELEASE-}
# Matrice par defaut = ansible-core supportes par AAP 2.6 (EE Python 3.12) ; 2.20 = AAP 2.7 (optionnel)
ACI_CORE_VERSIONS_DEFAULT="2.16 2.18"
ACI_CONTAINER_ENGINE=${ACI_CONTAINER_ENGINE:-podman}
ACI_PYTHON_MAP=${ACI_PYTHON_MAP:-$ACI_SHARE/python-map.txt}   # table serie -> Pythons (surchargeable)
ACI_COLOR=${ACI_COLOR:-true}
export ACI_CONTAINER_ENGINE
[ -n "${ACI_PIP_INDEX_URL:-}" ] && export PIP_INDEX_URL=$ACI_PIP_INDEX_URL
export PIP_DISABLE_PIP_VERSION_CHECK=1

if [ "$ACI_COLOR" = true ]; then _c=$'\033[36m' _w=$'\033[33m' _e=$'\033[31m' _0=$'\033[0m'; else _c='' _w='' _e='' _0=''; fi
log()  { printf '%s[aci]%s %s\n' "$_c" "$_0" "$*" >&2; }
warn() { printf '%s[aci] ATTENTION :%s %s\n' "$_w" "$_0" "$*" >&2; }
die()  { printf '%s[aci] ERREUR :%s %s\n' "$_e" "$_0" "$*" >&2; exit 2; }
run()  { log "+ $*"; "$@"; }

# ---- series ansible-core et Python ------------------------------------------------------------
aci_map_line() { awk -v c="$1" '$1 == c' "$ACI_PYTHON_MAP"; }

# ACI_CORE_VERSIONS : series de la matrice ("2.20 2.21" ou '["2.20", "2.21"]', forme d'un input GitLab
# de type array insere dans une chaine) ; a defaut, toutes les series de la table.
aci_core_versions() {
  # tolere toute decoration autour des series (ex. 'series ["2.16", "2.18"]' produit par un input GitLab)
  if [ -n "${ACI_CORE_VERSIONS:-}" ]; then echo "$ACI_CORE_VERSIONS" | grep -oE '[0-9]+\.[0-9]+|devel|milestone' | xargs; return; fi
  echo "$ACI_CORE_VERSIONS_DEFAULT"
}

aci_default_core() {   # derniere serie de la matrice qui n'est ni pre-version ni devel/milestone
  if [ -n "${ACI_CORE_DEFAULT:-}" ]; then echo "$ACI_CORE_DEFAULT"; return; fi
  local core last=""
  for core in $(aci_core_versions); do
    case " $ACI_PRERELEASE devel milestone " in *" $core "*) continue ;; esac
    last=$core
  done
  echo "$last"
}

aci_is_prerelease() { case " $ACI_PRERELEASE " in *" $(aci_core 2>/dev/null) "*) return 0 ;; esac; return 1; }

aci_core() {   # serie a utiliser : ACI_CORE, sinon la serie par defaut
  local core=${ACI_CORE:-$(aci_default_core)}
  [ -n "$(aci_map_line "$core")" ] || die "serie ansible-core '$core' inconnue (voir $ACI_PYTHON_MAP)"
  echo "$core"
}

aci_python() {   # interpreteur controleur pour la serie $1
  local core=$1 v
  # en mode docker, ACI_PYTHON designe le Python CIBLE (--python, dans le conteneur ansible-test) :
  # le Python hote est choisi librement dans la plage de la serie.
  if [ -n "${ACI_PYTHON:-}" ] && [ "$ACI_TEST_MODE" != docker ]; then
    command -v "python$ACI_PYTHON" >/dev/null || die "ACI_PYTHON=$ACI_PYTHON : python$ACI_PYTHON introuvable sur l'agent"
    echo "python$ACI_PYTHON"; return
  fi
  for v in $(aci_map_line "$core" | cut -d' ' -f2- ); do
    if command -v "python$v" >/dev/null; then echo "python$v"; return; fi
  done
  die "aucun Python controleur pour ansible-core $core sur cet agent (attendu : $(aci_map_line "$core" | cut -d' ' -f2- | xargs))"
}

aci_core_spec() {
  local core=$1 major minor
  # version exacte (ex. celle d'une EE cible, `aci ee-introspect`) : ACI_CORE_PIN=2.16.19
  if [ -n "${ACI_CORE_PIN:-}" ]; then
    case $ACI_CORE_PIN in "$core".*) echo "ansible-core==$ACI_CORE_PIN"; return ;; esac
    die "ACI_CORE_PIN=$ACI_CORE_PIN ne correspond pas a la serie $core"
  fi
  case $core in
    devel|milestone)
      local var="ACI_CORE_SRC_${core^^}"
      [ -n "${!var:-}" ] || die "ansible-core '$core' n'est pas sur PyPI : definir $var (tarball interne, depot Nexus raw)"
      echo "${!var}"; return ;;
  esac
  major=${core%%.*}; minor=${core#*.}
  case " $ACI_PRERELEASE " in
    # specificateur a pre-version : seules les pre-versions d'ansible-core sont acceptees (pas de --pre global)
    *" $core "*) echo "ansible-core>=$major.$minor.0a0,<$major.$((minor + 1))" ;;
    *)           echo "ansible-core>=$major.$minor,<$major.$((minor + 1))" ;;
  esac
}

# ---- venvs en cache ---------------------------------------------------------------------------
# aci_venv <outillage> : core | lint | docs | import | molecule | security (sans ansible-core)
aci_venv() {
  local toolset=$1 core py spec key dir
  local -a pkgs=() reqs=()
  core=$(aci_core); py=$(aci_python "$core")
  if [ "$toolset" != security ]; then spec=$(aci_core_spec "$core"); pkgs=("$spec"); fi
  [ "$toolset" = core ] || reqs=(-r "$ACI_SHARE/requirements-$toolset.txt")
  key=$( { echo "$toolset $core ${pkgs[*]:-}"; "$py" -VV; cat "$ACI_SHARE/constraints.txt"; \
           [ "$toolset" = core ] || cat "$ACI_SHARE/requirements-$toolset.txt"; } | sha256sum | cut -c1-12)
  dir=$ACI_CACHE/venv/$toolset-$core-$key
  mkdir -p "$ACI_CACHE/venv"
  # verrou : deux builds paralleles sur le meme agent ne construisent pas le meme venv en meme temps
  if command -v flock >/dev/null; then exec 9>"$dir.lock"; flock 9; fi
  if [ ! -f "$dir/.aci-ok" ]; then
    log "venv $toolset (ansible-core $core, $py) -> $dir"
    rm -rf "$dir"
    "$py" -m venv "$dir" >&2
    "$dir/bin/python" -m pip install -q -c "$ACI_SHARE/constraints.txt" "${pkgs[@]}" "${reqs[@]}" >&2
    touch "$dir/.aci-ok"
  fi
  export VIRTUAL_ENV=$dir PATH=$dir/bin:$PATH
  echo "$dir"
}

# ---- Galaxy (Nexus) ---------------------------------------------------------------------------
aci_galaxy_cfg() {   # fichier ansible.cfg pour ansible-galaxy uniquement
  if [ -n "${ACI_ANSIBLE_CFG:-}" ]; then echo "$ACI_ANSIBLE_CFG"; return; fi
  local cfg=$ACI_WORK/ansible-galaxy.cfg servers=""
  mkdir -p "$ACI_WORK"
  [ -n "${ACI_GALAXY_URL:-}" ] && servers=aci_group
  [ -n "${ACI_GALAXY_PUBLISH_URL:-}" ] && servers=${servers:+$servers, }aci_publish
  if [ -z "$servers" ]; then warn "ni ACI_GALAXY_URL ni ACI_ANSIBLE_CFG : ansible-galaxy utilisera galaxy.ansible.com (Internet)"; echo ""; return; fi
  {
    echo "[galaxy]"; echo "server_list = $servers"
    [ -n "${ACI_GALAXY_URL:-}" ] && printf '\n[galaxy_server.aci_group]\nurl = %s\n' "$ACI_GALAXY_URL"
    [ -n "${ACI_GALAXY_PUBLISH_URL:-}" ] && printf '\n[galaxy_server.aci_publish]\nurl = %s\n' "$ACI_GALAXY_PUBLISH_URL"
  } > "$cfg"
  echo "$cfg"
}

aci_galaxy() {   # ansible-galaxy avec la configuration Nexus, sans polluer ansible-test
  local cfg; cfg=$(aci_galaxy_cfg)
  if [ -n "$cfg" ]; then ANSIBLE_CONFIG=$cfg run ansible-galaxy "$@"; else run ansible-galaxy "$@"; fi
}

aci_cert_env() {   # charge la reference de certification (versions figees) : share/aci/certification.env
  set -a; # shellcheck source=/dev/null
  . "${ACI_CERT_ENV:-$ACI_SHARE/certification.env}"; set +a
}

aci_requires_minor() {   # borne basse de requires_ansible -> "2.16" (meme expression que le checker)
  [ -f "$ACI_SRC/meta/runtime.yml" ] || return 0
  sed -n -E "s/^requires_ansible:[[:space:]]*[\"']?>=?[[:space:]]*([0-9]+)\.([0-9]+).*/\1.\2/p" "$ACI_SRC/meta/runtime.yml" | head -1
}

aci_meta() { python "$ACI_PY/galaxy_meta.py" "$ACI_SRC/galaxy.yml" "$@"; }   # -> "ns name version"

aci_tarball() {
  local ns name version; read -r ns name version < <(aci_meta)
  echo "$ACI_DIST/$ns-$name-$version.tar.gz"
}

# ---- arbre ansible_collections/<ns>/<name> -------------------------------------------------------
# aci_prepare_tree <type> : copie la collection hors du depot (sinon ansible-test se fie a git et
# saute les cibles) et installe A COTE les dependances Galaxy du type (lint, sanity, units, ...).
aci_prepare_tree() {
  local kind=$1 ns name version req
  ACI_TREE_BASE=$ACI_WORK/$kind-${ACI_CORE:-default}
  rm -rf "$ACI_TREE_BASE"; mkdir -p "$ACI_TREE_BASE"
  read -r ns name version < <(aci_meta "$ACI_TREE_BASE/galaxy-deps.yml")
  ACI_TREE_DEST=$ACI_TREE_BASE/ansible_collections/$ns/$name
  mkdir -p "$ACI_TREE_DEST"
  tar -C "$ACI_SRC" --exclude=./.git --exclude=./reports --exclude=./dist --exclude=./tests/output \
      --exclude=./.nox --exclude=./.tox --exclude=./.venv --exclude=__pycache__ -cf - . | tar -C "$ACI_TREE_DEST" -xf -
  local -a files=("$ACI_TREE_BASE/galaxy-deps.yml" "$ACI_SRC/tests/requirements.yml")
  case $kind in
    units)           files+=("$ACI_SRC/tests/unit/requirements.yml") ;;
    integration)     files+=("$ACI_SRC/tests/integration/requirements.yml") ;;
    lint|docs|molecule) files+=("$ACI_SRC/extensions/molecule/requirements.yml") ;;
  esac
  for req in "${files[@]}"; do
    # ANSIBLE_COLLECTIONS_PATH=base : une collection presente ailleurs serait sinon "deja installee"
    [ -f "$req" ] && ANSIBLE_COLLECTIONS_PATH=$ACI_TREE_BASE aci_galaxy collection install -r "$req" -p "$ACI_TREE_BASE"
  done
  export ACI_TREE_BASE ACI_TREE_DEST
}

# ---- ansible-test --------------------------------------------------------------------------------
aci_prime() {   # pre-tire depuis Nexus et re-tague sous quay.io/... (ansible-test ne tire pas une image presente)
  if [ -z "${ACI_IMAGE_MIRROR:-}" ]; then log "ACI_IMAGE_MIRROR vide : ansible-test tirera lui-meme les images"; return 0; fi
  run python "$ACI_PY/prime_images.py" "$@"
}

aci_common_test_args() {
  if [ "$ACI_COLOR" = true ]; then echo "-v --color"; else echo "-v --color no"; fi
  if [ "$ACI_TEST_MODE" = docker ]; then
    [ -n "${ACI_PYTHON:-}" ] && echo "--python $ACI_PYTHON"   # Python de l'EE cible (certification : 3.12)
    local ep=${ACI_PYPI_ENDPOINT:-${ACI_PIP_INDEX_URL:-}}
    # option masquee (argparse.SUPPRESS) mais implementee : pip des conteneurs ansible-test -> Nexus
    [ -n "$ep" ] && echo "--pypi-endpoint $ep"
  fi
  [ "${ACI_COVERAGE:-false}" = true ] && echo "--coverage"
  return 0
}

# ansible-test range ses venvs et son cache dans ~/.ansible/test : un HOME dedie par serie, sous verrou,
# pour que deux executions paralleles sur le meme agent (branches de la matrice, builds concurrents)
# ne construisent jamais le meme venv en meme temps (sinon : "No such file ... pip-*.dist-info").
aci_test_home() {
  local home=${ACI_TEST_HOME:-$ACI_CACHE/ansible-test-home/$(aci_core)}
  mkdir -p "$home"
  if command -v flock >/dev/null; then
    exec 8>"$home.lock"
    flock -n 8 || { log "attente du verrou $home.lock (autre execution ansible-test $(aci_core) sur cet agent)"; flock 8; }
  fi
  export HOME=$home
}

aci_venv_python_args() {   # mode venv : un seul Python (celui du venv), get-pip hors ligne
  run python "$ACI_PY/get_pip_offline.py" --seed >&2
  echo "--venv --python $(python -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
}

# aci_ansible_test <libelle> <args...> : execute dans l'arbre prepare et copie tests/output dans reports/
aci_ansible_test() {
  local label=$1; shift
  local rc=0
  (cd "$ACI_TREE_DEST" && run ansible-test "$@") || rc=$?
  if [ "${ACI_COVERAGE:-false}" = true ] && [ $rc -eq 0 ]; then
    (cd "$ACI_TREE_DEST" && run ansible-test coverage xml -v --requirements --group-by command --group-by version) || rc=$?
  fi
  if [ -d "$ACI_TREE_DEST/tests/output" ]; then
    rm -rf "${ACI_REPORTS:?}/$label"; mkdir -p "$ACI_REPORTS/$label"
    # sans .tmp/ (venvs de delegation, liens symboliques exotiques) : junit, bot, coverage, reports...
    tar -C "$ACI_TREE_DEST/tests/output" --exclude=./.tmp -cf - . | tar -C "$ACI_REPORTS/$label" -xf -
    log "rapports : $ACI_REPORTS/$label"
  fi
  return $rc
}
