#!/usr/bin/env bash
# End-to-end bench: Jenkins 2.580.1 set up by init.groovy.d/ (what an admin does in "Manage Jenkins":
# global library, credentials, agents, jobs), library loaded from a local git
# repository (moving tag v2 + tag v2.1.0), and two agents:
#   runner-1  : container from the ci-tools-image + Java (stands in for the OpenShift pod);
#   builder-1 : agent process on THIS host, run as root with podman (stands in for the ansible-builder VM;
#               the bench host has no systemd user session, so rootless podman would have no delegated
#               cgroup v2 for the systemd test containers - on the real VM: `loginctl enable-linger`).
# The bench copy of the library differs from the published one in three points only:
#   * `kubernetes { yaml podYaml; ... }` -> `label 'ansible-runner'` (no cluster on the bench);
#   * the rendered pod YAML is archived (pod-rendered.yaml) so that the substitution can be checked;
#   * Nexus defaults -> public galaxy.ansible.com / pypi.org / quay.io.
# Jobs: corp-demo (@v2, 2-line Jenkinsfile), corp-demo-lite (@v2.1.0, no units/integration/Molecule),
#   corp-demo-params (overrides: spotterEndpoint '', credential IDs, ciToolsImage, builderLabel),
#   corp-demo-spotter (lite + spotterEndpoint set: Spotter runs, unreachable -> UNSTABLE),
#   corp-demo-typo (unknown parameter -> FAILURE before any agent).
# Requires: podman (rootless for the containers, sudo for builder-1), java 21 on the host, images
# $JENKINS_IMAGE and $CI_TOOLS_IMAGE.
#   usage: tests/jenkins-e2e/run-e2e.sh        -> logs in $OUT (default /tmp/jk/out)
#          SKIP_BUILD=1 ...                     reuse the bench images built by a previous run
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); repo=$(cd "$here/../.." && pwd)
W=${W:-/tmp/jk}; OUT=${OUT:-$W/out}
JENKINS_IMAGE=${JENKINS_IMAGE:-docker.io/jenkins/jenkins:2.580.1-jdk21}
CI_TOOLS_IMAGE=${CI_TOOLS_IMAGE:-localhost/corp/ci-tools-image:2026.10}
podman rm -f jenkins runner-1 >/dev/null 2>&1 || true
sudo pkill -f "agent.jar.*-name builder-1" 2>/dev/null || true
sudo rm -rf "$W"; mkdir -p "$W/repos" "$W/src" "$W/shared" "$W/builder" "$OUT"; chmod 777 "$W/shared"

# 1) local git repositories: library (tag v2.1.0 + moving tag v2) and the consumer collections
cp -r "$repo/jenkins-shared-library" "$W/src/ansible-ci"
python3 - "$W/src/ansible-ci/vars/ansibleCollectionPipeline.groovy" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
for a, b in [
    ("kubernetes { yaml podYaml; defaultContainer 'runner' }", "label 'ansible-runner'"),
    ("https://nexus.corp.local/repository/ansible-group/", "https://galaxy.ansible.com/"),
    ("https://nexus.corp.local/repository/pypi-group/simple", "https://pypi.org/simple"),
    ("'nexus.corp.local:8444'", "'quay.io'"),
    ("\n    pipeline {", "\n    node('ansible-runner') { writeFile file: 'pod-rendered.yaml', text: podYaml; archiveArtifacts 'pod-rendered.yaml' }\n    pipeline {"),
]:
    assert a in s, a
    s = s.replace(a, b)
open(p, 'w').write(s)
PY
(cd "$W/src/ansible-ci" && git init -q -b main && git add -A && git -c user.name=ci -c user.email=ci@corp.local commit -qm bench &&
  git tag v2.1.0 && git tag v2 && git clone -q --bare . "$W/repos/ansible-ci.git")
lib="@Library('ansible-ci@v2') _"
declare -A jf=(
  [corp-demo]="$lib
ansibleCollectionPipeline()"
  [corp-demo-lite]="@Library('ansible-ci@v2.1.0') _
ansibleCollectionPipeline()"
  [corp-demo-params]="$lib
ansibleCollectionPipeline(spotterEndpoint: '', spotterCredentialsId: 'bench-team-spotter', galaxyCredentialsId: 'bench-team-galaxy',
                          ciToolsImage: 'localhost/bench/ci-tools-image:override', builderLabel: 'podman-bench')"
  [corp-demo-spotter]="$lib
ansibleCollectionPipeline(spotterEndpoint: 'https://spotter.invalid/api', spotterCredentialsId: 'bench-team-spotter')"
  [corp-demo-typo]="$lib
ansibleCollectionPipeline(spoterEndpoint: 'https://spotter.corp.local/api')"
)
for c in "${!jf[@]}"; do
  cp -r "$repo/example-collection/corp.demo" "$W/src/$c"
  (cd "$W/src/$c" && rm -rf dist reports tests/output
   case $c in corp-demo-lite|corp-demo-spotter|corp-demo-typo) rm -rf tests/unit tests/integration extensions/molecule ;; esac
   printf '%s\n' "${jf[$c]}" > Jenkinsfile
   git init -q -b main && git add -A && git -c user.name=ci -c user.email=ci@corp.local commit -qm demo &&
   git clone -q --bare . "$W/repos/$c.git")
done
chmod -R a+rX "$W/repos"

# 2) images
if [ -z "${SKIP_BUILD:-}" ]; then
  podman build -q --build-arg JENKINS_IMAGE="$JENKINS_IMAGE" -t localhost/ansible-ci-e2e-jenkins -f "$here/Containerfile.jenkins" "$here"
  podman run --rm --entrypoint sh localhost/ansible-ci-e2e-jenkins -c 'cd /tmp && unzip -q -o /usr/share/jenkins/jenkins.war "WEB-INF/lib/remoting-*.jar" && cat WEB-INF/lib/remoting-*.jar' > "$here/agent.jar"
  podman build -q --build-arg CI_TOOLS_IMAGE="$CI_TOOLS_IMAGE" -t localhost/ansible-ci-e2e-agent -f "$here/Containerfile.agent" "$here"
  rm -f "$here/agent.jar"
fi
podman run --rm --entrypoint sh localhost/ansible-ci-e2e-jenkins -c 'cd /tmp && unzip -q -o /usr/share/jenkins/jenkins.war "WEB-INF/lib/remoting-*.jar" && cat WEB-INF/lib/remoting-*.jar' > "$W/agent.jar"
printf '[global]\nindex-url = https://pypi.org/simple\n' > "$W/pip.conf"

# 3) Jenkins, then the agents
podman network exists jk || podman network create jk >/dev/null
podman run -d --name jenkins --network jk -p 127.0.0.1:8080:8080 \
  -v "$W/repos:/repos:ro" -v "$W/shared:/var/jenkins_home/shared" localhost/ansible-ci-e2e-jenkins >/dev/null
# rootless podman: the bind-mounted repositories look root-owned inside the containers -> safe.directory
podman exec jenkins git config --global --add safe.directory '*'
until curl -sf http://127.0.0.1:8080/login >/dev/null && [ -s "$W/shared/runner-1.secret" ]; do sleep 3; done
# aci baked into the ci-tools-image is replaced by the working tree version (the image may be older)
podman run -d --name runner-1 --network jk --user 1001:0 --cap-drop ALL --security-opt no-new-privileges \
  -e JENKINS_URL=http://jenkins:8080/ -e JENKINS_AGENT_NAME=runner-1 -e JENKINS_SECRET_FILE=/shared/runner-1.secret \
  -v "$W/shared:/shared:ro" -v "$W/repos:/repos:ro" -v "$W/pip.conf:/etc/pip.conf:ro" \
  -v "$repo/ci-scripts/bin/aci:/opt/ansible-ci/bin/aci:ro" -v "$repo/ci-scripts/lib/aci:/opt/ansible-ci/lib/aci:ro" \
  -v "$repo/ci-scripts/share/aci:/opt/ansible-ci/share/aci:ro" -v "$repo/ci-scripts/VERSION:/opt/ansible-ci/VERSION:ro" \
  localhost/ansible-ci-e2e-agent >/dev/null
podman exec runner-1 git config --global --add safe.directory '*'
# builder-1 on the host: the jobs clone file:///repos/... -> /repos must exist on the host too
[ "$(readlink /repos 2>/dev/null)" = "$W/repos" ] || sudo ln -sfn "$W/repos" /repos
# aci from the working tree under /opt/ansible-ci, like infra/ansible-builder-vm/site.yml
[ -x /opt/ansible-ci/bin/python ] || { sudo mkdir -p /opt/ansible-ci && sudo chown "$(id -u)" /opt/ansible-ci && python3 -m venv /opt/ansible-ci; }
/opt/ansible-ci/bin/pip install -q PyYAML
ln -sfn "$repo/ci-scripts/bin/aci" /opt/ansible-ci/bin/aci
# shellcheck disable=SC2024  # the agent log is meant to be owned by the calling user
(cd "$W/builder" && sudo -n env HOME=/root PATH="$PATH" ANSIBLE_TEST_PREFER_PODMAN=1 nohup java -jar "$W/agent.jar" \
  -url http://127.0.0.1:8080/ -secret @"$W/shared/builder-1.secret" -name builder-1 -webSocket -workDir "$W/builder" \
  > "$OUT/builder-1.agent.log" 2>&1 &)
J=http://127.0.0.1:8080
for a in runner-1 builder-1; do until curl -sf "$J/computer/$a/api/json" | grep -q '"offline":false'; do sleep 3; done; done
echo "agents connected"

# 4) builds, then the checks of the rendered pod YAML
crumb() { curl -sf -c "$W/cookies" "$J/crumbIssuer/api/json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["crumbRequestField"]+":"+d["crumb"])'; }
result() { curl -sf "$J/job/$1/1/api/json" 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print("RUNNING" if d["building"] else d["result"])' 2>/dev/null || echo PENDING; }
jobs=${JOBS:-corp-demo corp-demo-lite corp-demo-params corp-demo-spotter corp-demo-typo}
for j in $jobs; do curl -sf -b "$W/cookies" -H "$(crumb)" -X POST "$J/job/$j/build" >/dev/null; done
for j in $jobs; do
  while :; do r=$(result "$j"); case $r in RUNNING|PENDING) sleep 15 ;; *) break ;; esac; done
  curl -sf "$J/job/$j/1/consoleText" > "$OUT/$j.log"
  curl -sf "$J/job/$j/1/testReport/api/json?tree=passCount,failCount,skipCount" > "$OUT/$j.tests.json" 2>/dev/null || true
  curl -sf "$J/job/$j/1/artifact/pod-rendered.yaml" > "$OUT/$j.pod.yaml" 2>/dev/null || rm -f "$OUT/$j.pod.yaml"
  img=$([ -s "$OUT/$j.pod.yaml" ] && /opt/ansible-ci/bin/python -c 'import sys,yaml; d=yaml.safe_load(open(sys.argv[1])); print(*[c.get("image","(cloud default)") for c in d["spec"]["containers"]], sep=" | ")' "$OUT/$j.pod.yaml" || echo "-")
  echo "$j #1: $r   pod images: $img"
done | tee "$OUT/results.txt"
