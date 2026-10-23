# shellcheck shell=bash
# Common functions of `aci` (sourced by bin/aci). No Jenkins- or GitLab-specific logic.
set -euo pipefail

ACI_LIB=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ACI_HOME=$(cd "$ACI_LIB/../.." && pwd)
ACI_SHARE=$ACI_HOME/share/aci
ACI_PY=$ACI_LIB/py
export ACI_VERSION; ACI_VERSION=$(cat "$ACI_HOME/VERSION" 2>/dev/null || echo dev)

ACI_SRC=$(cd "${ACI_SRC:-$PWD}" && pwd)                # collection root (checkout)
ACI_REPORTS=${ACI_REPORTS:-$ACI_SRC/reports}
ACI_DIST=${ACI_DIST:-$ACI_SRC/dist}
ACI_WORK=${ACI_WORK:-${TMPDIR:-/tmp}/aci-$(id -u)/$(basename "$ACI_SRC")}
ACI_CACHE=${ACI_CACHE:-${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/ansible-ci}
ACI_TEST_MODE=${ACI_TEST_MODE:-venv}
ACI_PRERELEASE=${ACI_PRERELEASE-}
# Default matrix = ansible-core versions supported by AAP 2.6 (EE Python 3.12); 2.20 = AAP 2.7 (optional)
ACI_CORE_VERSIONS_DEFAULT="2.16 2.18"
ACI_CONTAINER_ENGINE=${ACI_CONTAINER_ENGINE:-podman}
ACI_PYTHON_MAP=${ACI_PYTHON_MAP:-$ACI_SHARE/python-map.txt}   # series -> Pythons table (overridable)
ACI_COLOR=${ACI_COLOR:-true}
export ACI_CONTAINER_ENGINE
[ -n "${ACI_PIP_INDEX_URL:-}" ] && export PIP_INDEX_URL=$ACI_PIP_INDEX_URL
export PIP_DISABLE_PIP_VERSION_CHECK=1

if [ "$ACI_COLOR" = true ]; then _c=$'\033[36m' _w=$'\033[33m' _e=$'\033[31m' _0=$'\033[0m'; else _c='' _w='' _e='' _0=''; fi
log()  { printf '%s[aci]%s %s\n' "$_c" "$_0" "$*" >&2; }
warn() { printf '%s[aci] WARNING:%s %s\n' "$_w" "$_0" "$*" >&2; }
die()  { printf '%s[aci] ERROR:%s %s\n' "$_e" "$_0" "$*" >&2; exit 2; }
run()  { log "+ $*"; "$@"; }

# ---- ansible-core series and Python ---------------------------------------------------------------
aci_map_line() { awk -v c="$1" '$1 == c' "$ACI_PYTHON_MAP"; }

# ACI_CORE_VERSIONS: matrix series ("2.20 2.21" or '["2.20", "2.21"]', the form of a GitLab array input
# interpolated into a string); defaults to ACI_CORE_VERSIONS_DEFAULT.
aci_core_versions() {
  # tolerates any decoration around the series (e.g. 'series ["2.16", "2.18"]' produced by a GitLab input)
  if [ -n "${ACI_CORE_VERSIONS:-}" ]; then echo "$ACI_CORE_VERSIONS" | grep -oE '[0-9]+\.[0-9]+|devel|milestone' | xargs; return; fi
  echo "$ACI_CORE_VERSIONS_DEFAULT"
}

aci_default_core() {   # last matrix series that is neither a pre-release nor devel/milestone
  if [ -n "${ACI_CORE_DEFAULT:-}" ]; then echo "$ACI_CORE_DEFAULT"; return; fi
  local core last=""
  for core in $(aci_core_versions); do
    case " $ACI_PRERELEASE devel milestone " in *" $core "*) continue ;; esac
    last=$core
  done
  echo "$last"
}

aci_is_prerelease() { case " $ACI_PRERELEASE " in *" $(aci_core 2>/dev/null) "*) return 0 ;; esac; return 1; }

aci_core() {   # series to use: ACI_CORE, else the default series
  local core=${ACI_CORE:-$(aci_default_core)}
  [ -n "$(aci_map_line "$core")" ] || die "unknown ansible-core series '$core' (see $ACI_PYTHON_MAP)"
  echo "$core"
}

aci_python() {   # controller interpreter for series $1
  local core=$1 v
  # in docker mode, ACI_PYTHON is the TARGET Python (--python, inside the ansible-test container):
  # the host Python is picked freely within the range of the series.
  if [ -n "${ACI_PYTHON:-}" ] && [ "$ACI_TEST_MODE" != docker ]; then
    command -v "python$ACI_PYTHON" >/dev/null || die "ACI_PYTHON=$ACI_PYTHON: python$ACI_PYTHON not found on the agent"
    echo "python$ACI_PYTHON"; return
  fi
  for v in $(aci_map_line "$core" | cut -d' ' -f2- ); do
    if command -v "python$v" >/dev/null; then echo "python$v"; return; fi
  done
  die "no controller Python for ansible-core $core on this agent (expected one of: $(aci_map_line "$core" | cut -d' ' -f2- | xargs))"
}

aci_core_spec() {
  local core=$1 major minor
  # exact version (e.g. the one of a target EE, `aci ee-introspect`): ACI_CORE_PIN=2.16.19
  if [ -n "${ACI_CORE_PIN:-}" ]; then
    case $ACI_CORE_PIN in "$core".*) echo "ansible-core==$ACI_CORE_PIN"; return ;; esac
    die "ACI_CORE_PIN=$ACI_CORE_PIN does not match series $core"
  fi
  case $core in
    devel|milestone)
      local var="ACI_CORE_SRC_${core^^}"
      [ -n "${!var:-}" ] || die "ansible-core '$core' is not on PyPI: set $var (internal tarball, Nexus raw repository)"
      echo "${!var}"; return ;;
  esac
  major=${core%%.*}; minor=${core#*.}
  case " $ACI_PRERELEASE " in
    # pre-release specifier: only ansible-core pre-releases are accepted (no global --pre)
    *" $core "*) echo "ansible-core>=$major.$minor.0a0,<$major.$((minor + 1))" ;;
    *)           echo "ansible-core>=$major.$minor,<$major.$((minor + 1))" ;;
  esac
}

# ---- cached venvs ---------------------------------------------------------------------------------
# aci_venv <toolset>: core | lint | docs | import | molecule | security (without ansible-core)
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
  # lock: two parallel builds on the same agent never build the same venv at the same time
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
aci_galaxy_cfg() {   # ansible.cfg file for ansible-galaxy only
  if [ -n "${ACI_ANSIBLE_CFG:-}" ]; then echo "$ACI_ANSIBLE_CFG"; return; fi
  local cfg=$ACI_WORK/ansible-galaxy.cfg servers=""
  mkdir -p "$ACI_WORK"
  [ -n "${ACI_GALAXY_URL:-}" ] && servers=aci_group
  [ -n "${ACI_GALAXY_PUBLISH_URL:-}" ] && servers=${servers:+$servers, }aci_publish
  if [ -z "$servers" ]; then warn "neither ACI_GALAXY_URL nor ACI_ANSIBLE_CFG: ansible-galaxy will use galaxy.ansible.com (Internet)"; echo ""; return; fi
  {
    echo "[galaxy]"; echo "server_list = $servers"
    [ -n "${ACI_GALAXY_URL:-}" ] && printf '\n[galaxy_server.aci_group]\nurl = %s\n' "$ACI_GALAXY_URL"
    [ -n "${ACI_GALAXY_PUBLISH_URL:-}" ] && printf '\n[galaxy_server.aci_publish]\nurl = %s\n' "$ACI_GALAXY_PUBLISH_URL"
  } > "$cfg"
  echo "$cfg"
}

aci_galaxy() {   # ansible-galaxy with the Nexus configuration, without leaking it into ansible-test
  local cfg; cfg=$(aci_galaxy_cfg)
  if [ -n "$cfg" ]; then ANSIBLE_CONFIG=$cfg run ansible-galaxy "$@"; else run ansible-galaxy "$@"; fi
}

aci_cert_env() {   # loads the certification reference (pinned versions): share/aci/certification.env
  set -a; # shellcheck source=/dev/null
  . "${ACI_CERT_ENV:-$ACI_SHARE/certification.env}"; set +a
}

aci_requires_minor() {   # lower bound of requires_ansible -> "2.16" (same expression as the checker)
  [ -f "$ACI_SRC/meta/runtime.yml" ] || return 0
  sed -n -E "s/^requires_ansible:[[:space:]]*[\"']?>=?[[:space:]]*([0-9]+)\.([0-9]+).*/\1.\2/p" "$ACI_SRC/meta/runtime.yml" | head -1
}

aci_meta() { python "$ACI_PY/galaxy_meta.py" "$ACI_SRC/galaxy.yml" "$@"; }   # -> "ns name version"

aci_tarball() {
  local ns name version; read -r ns name version < <(aci_meta)
  echo "$ACI_DIST/$ns-$name-$version.tar.gz"
}

# ---- ansible_collections/<ns>/<name> tree ----------------------------------------------------------
# aci_prepare_tree <kind>: copies the collection out of the repository (otherwise ansible-test trusts git
# and skips targets) and installs NEXT TO IT the Galaxy dependencies of that kind (lint, sanity, units...).
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
    # ANSIBLE_COLLECTIONS_PATH=base: otherwise a collection present elsewhere would count as "already installed"
    [ -f "$req" ] && ANSIBLE_COLLECTIONS_PATH=$ACI_TREE_BASE aci_galaxy collection install -r "$req" -p "$ACI_TREE_BASE"
  done
  export ACI_TREE_BASE ACI_TREE_DEST
}

# ---- ansible-test --------------------------------------------------------------------------------
aci_prime() {   # pre-pulls from Nexus and re-tags as quay.io/... (ansible-test does not pull an image already present)
  if [ -z "${ACI_IMAGE_MIRROR:-}" ]; then log "ACI_IMAGE_MIRROR empty: ansible-test will pull the images itself"; return 0; fi
  run python "$ACI_PY/prime_images.py" "$@"
}

aci_common_test_args() {
  if [ "$ACI_COLOR" = true ]; then echo "-v --color"; else echo "-v --color no"; fi
  if [ "$ACI_TEST_MODE" = docker ]; then
    [ -n "${ACI_PYTHON:-}" ] && echo "--python $ACI_PYTHON"   # Python of the target EE (certification: 3.12)
    local ep=${ACI_PYPI_ENDPOINT:-${ACI_PIP_INDEX_URL:-}}
    # hidden option (argparse.SUPPRESS) but implemented: pip inside ansible-test containers -> Nexus
    [ -n "$ep" ] && echo "--pypi-endpoint $ep"
  fi
  [ "${ACI_COVERAGE:-false}" = true ] && echo "--coverage"
  return 0
}

# ansible-test keeps its venvs and cache in ~/.ansible/test: one dedicated HOME per series, under a lock,
# so that two parallel runs on the same agent (matrix branches, concurrent builds) never build the
# same venv at the same time (otherwise: "No such file ... pip-*.dist-info").
aci_test_home() {
  local home=${ACI_TEST_HOME:-$ACI_CACHE/ansible-test-home/$(aci_core)}
  mkdir -p "$home"
  if command -v flock >/dev/null; then
    exec 8>"$home.lock"
    flock -n 8 || { log "waiting for lock $home.lock (another ansible-test $(aci_core) run on this agent)"; flock 8; }
  fi
  export HOME=$home
}

aci_venv_python_args() {   # venv mode: a single Python (the venv one), offline get-pip
  run python "$ACI_PY/get_pip_offline.py" --seed >&2
  echo "--venv --python $(python -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
}

# aci_ansible_test <label> <args...>: runs in the prepared tree and copies tests/output to reports/
aci_ansible_test() {
  local label=$1; shift
  local rc=0
  (cd "$ACI_TREE_DEST" && run ansible-test "$@") || rc=$?
  if [ "${ACI_COVERAGE:-false}" = true ] && [ $rc -eq 0 ]; then
    (cd "$ACI_TREE_DEST" && run ansible-test coverage xml -v --requirements --group-by command --group-by version) || rc=$?
  fi
  if [ -d "$ACI_TREE_DEST/tests/output" ]; then
    rm -rf "${ACI_REPORTS:?}/$label"; mkdir -p "$ACI_REPORTS/$label"
    # without .tmp/ (delegation venvs, odd symlinks): junit, bot, coverage, reports...
    tar -C "$ACI_TREE_DEST/tests/output" --exclude=./.tmp -cf - . | tar -C "$ACI_REPORTS/$label" -xf -
    log "reports: $ACI_REPORTS/$label"
  fi
  return $rc
}
