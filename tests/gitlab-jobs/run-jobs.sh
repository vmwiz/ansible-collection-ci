#!/usr/bin/env bash
# Bench: really runs the scripts of the component's RENDERED jobs (render.py), without GitLab.
#   "runner" jobs (pods) -> container of the runner image on the airgap network, arbitrary UID, cap-drop ALL;
#   aci-ee-introspect (shell runner of the ansible-builder VM) -> on the bench host, with podman.
# Every job starts from a fresh clone (like a runner); the introspection artifacts are copied over;
# /tmp/gl/cache simulates the persistent ~/.cache/ansible-ci volume of the Kubernetes runner.
# Usage: run-jobs.sh INPUTS CONTEXT "job[:cell-json] ..."     Output: $OUT/<job>.log + results.txt
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../.." && pwd)
G=$root/gitlab-ci-templates; T=$G/templates/ansible-collection/template.yml
inputs=$1 ctx=$2 jobs=$3
OUT=${OUT:-/tmp/gl/out}; W=${W:-/tmp/gl/work}; IMAGE=${IMAGE:-localhost/ansible-collection-runner:ubi9-v4}
REPO=${REPO:-/tmp/gl/repos/corp-demo.git}
mkdir -p "$OUT" "$W" /tmp/gl/cache; chmod 0777 /tmp/gl/cache
run_one() {
  local spec=$1 name cell slug dir rc
  name=${spec%%:*}; cell='{}'; [ "$spec" != "$name" ] && cell=${spec#*:}
  slug=$(echo "$spec" | tr -c 'a-zA-Z0-9.\n' '-')
  dir=$W/$slug/builds/corp/demo; rm -rf "${W:?}/$slug"; mkdir -p "$(dirname "$dir")"
  git clone -q "$REPO" "$dir"
  if [ "$ctx" = mr ]; then git -C "$dir" checkout -q "${MR_BRANCH:-feature}"; fi
  [ -f "$W/ee-matrix.txt" ] && mkdir -p "$dir/reports/ee" && cp "$W/ee-matrix.txt" "$dir/reports/ee/matrix.txt"
  python3 "$G/tests/render.py" "$T" -i "$inputs" --job "$name" --context "$ctx" --cell "$cell" --emit "$W/$slug/job.sh" || return 1
  if [ "$name" = aci-ee-introspect ]; then   # ansible-builder VM: shell runner, aci from ci-scripts
    (cd "$dir" && ACI_CACHE=/tmp/aci-cache bash -c "$(sed "s#^export ACI=.*#export ACI=$root/ci-scripts/bin/aci#" "$W/$slug/job.sh")") > "$OUT/$slug.log" 2>&1
    rc=$?; [ -f "$dir/reports/ee/matrix.txt" ] && cp "$dir/reports/ee/matrix.txt" "$W/ee-matrix.txt"
  else
    chmod -R a+rwX "$W/$slug"
    # shellcheck disable=SC2024  # log written by the current user
    sudo podman run --rm --network airgap --user 1000680000:0 --cap-drop ALL --security-opt no-new-privileges \
      -e CI_PROJECT_DIR=/builds/corp/demo -v "$W/$slug/builds:/builds" -v "$REPO:$REPO:ro" -v "$W/$slug/job.sh:/job.sh:ro" \
      -v /tmp/gl/cache:/home/ci/.cache/ansible-ci -w /builds/corp/demo \
      "$IMAGE" bash /job.sh > "$OUT/$slug.log" 2>&1
    rc=$?
  fi
  echo "$spec rc=$rc" | tee -a "$OUT/results.txt"
}
export -f run_one; export here root G T inputs ctx OUT W IMAGE REPO
: > "$OUT/results.txt"
for j in $jobs; do case $j in aci-ee-introspect*) run_one "$j" ;; esac; done
# shellcheck disable=SC2086  # space-separated job list
printf '%s\n' $jobs | grep -v '^aci-ee-introspect' | xargs -r -d '\n' -P "${PAR:-4}" -I{} bash -c 'run_one "$@"' _ {}
