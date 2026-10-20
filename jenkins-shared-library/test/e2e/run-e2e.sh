#!/usr/bin/env bash
# Banc de bout en bout : Jenkins 2.580.1 + bibliotheque chargee depuis un depot git local + agent runner
# sur un reseau SANS Internet (seul "nexus.corp.local" : proxy PyPI devpi + stub Galaxy, voir README).
#   prerequis : reseau podman "airgap" (--internal) + conteneur nexus (alias nexus.corp.local) ;
#               images localhost/jk:test (Jenkins) et localhost/ansible-collection-runner:ubi9-v4.
#   usage : sudo -E ./run-e2e.sh            -> logs dans $OUT (defaut /tmp/jk/out)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); repo=$(cd "$here/../../.." && pwd)
W=${W:-/tmp/jk}; OUT=${OUT:-$W/out}; P="sudo podman"
mkdir -p "$W/repos" "$W/shared" "$OUT"; chmod 777 "$W/shared"

# 1) depots git locaux : bibliotheque (tag v1.0.0 + branche mobile v1) et collection consommatrice
rm -rf "$W/repos"/* "$W/src"; mkdir -p "$W/src"
"$repo/tools/sync-aci.sh" --check
cp -r "$repo/jenkins-shared-library" "$W/src/ansible-ci"
(cd "$W/src/ansible-ci" && rm -rf test/e2e/out && git init -q -b main && git add -A &&
  git -c user.name=ci -c user.email=ci@corp.local commit -qm "ansible-ci $(cat resources/org/corp/ansibleci/aci/VERSION)" &&
  git tag v1.0.0 && git branch v1 && git clone -q --bare . "$W/repos/ansible-ci.git")
cp -r "$repo/exemple-collection/corp.demo" "$W/src/corp.demo"
cp "$here/Jenkinsfile.corp-demo" "$W/src/corp.demo/Jenkinsfile"
cp "$here/Jenkinsfile.ee" "$here/Jenkinsfile.ee-bad" "$W/src/corp.demo/"
(cd "$W/src/corp.demo" && rm -rf dist reports tests/output && git init -q -b main && git add -A &&
  git -c user.name=ci -c user.email=ci@corp.local commit -qm demo && git clone -q --bare . "$W/repos/corp.demo.git")
chmod -R a+rX "$W/repos"

# 2) images (REUSE=1 : banc deja demarre, seuls les depots git sont regeneres)
if [ -z "${REUSE:-}" ]; then
podman run --rm --entrypoint sh localhost/jk:test -c 'cd /tmp && unzip -q -o /usr/share/jenkins/jenkins.war "WEB-INF/lib/remoting-*.jar" && cat WEB-INF/lib/remoting-*.jar' > "$here/agent.jar"
podman build -q -t localhost/ansible-ci-e2e-jenkins -f "$here/Containerfile.jenkins" "$here"
podman build -q --network host -t localhost/ansible-ci-e2e-agent -f "$here/Containerfile.agent" "$here"
for i in localhost/ansible-ci-e2e-jenkins localhost/ansible-ci-e2e-agent; do podman save "$i" | $P load -q; done
rm -f "$here/agent.jar"

# 3) Jenkins (reseaux egress + airgap) puis agent (airgap seul, UID arbitraire facon OpenShift)
$P rm -f jenkins runner-1 >/dev/null 2>&1 || true
$P run -d --name jenkins --network egress --network airgap:alias=jenkins -p 127.0.0.1:8080:8080 \
  -v "$W/repos:/repos:ro" -v "$W/shared:/var/jenkins_home/shared" localhost/ansible-ci-e2e-jenkins >/dev/null
until curl -sf http://127.0.0.1:8080/login >/dev/null && [ -s "$W/shared/runner-1.secret" ]; do sleep 3; done
$P run -d --name runner-1 --network airgap --user 1000680000:0 --cap-drop ALL --security-opt no-new-privileges \
  -e JENKINS_URL=http://jenkins:8080/ -e JENKINS_AGENT_NAME=runner-1 -e JENKINS_SECRET_FILE=/shared/runner-1.secret \
  -v "$W/shared:/shared:ro" -v "$W/repos:/repos:ro" localhost/ansible-ci-e2e-agent >/dev/null
fi
J=http://127.0.0.1:8080
until curl -sf "$J/computer/runner-1/api/json" | grep -q '"offline":false'; do sleep 3; done
echo "agent runner-1 connecte"

# 4) builds
crumb() { curl -sf -c "$W/cookies" "$J/crumbIssuer/api/json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["crumbRequestField"]+":"+d["crumb"])'; }
next() { curl -sf "$J/job/$1/api/json?tree=nextBuildNumber" | python3 -c 'import json,sys; print(json.load(sys.stdin)["nextBuildNumber"])'; }
trigger() { curl -sf -b "$W/cookies" -H "$(crumb)" -X POST "$J/job/$1/build" >/dev/null; }
result() { curl -sf "$J/job/$1/$2/api/json" 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print("RUNNING" if d["building"] else d["result"])' 2>/dev/null || echo PENDING; }
jobs=${JOBS:-corp-demo corp-demo-ee corp-demo-ee-bad corp-demo-scripted bad-config bad-step matrix-dynamic}
declare -A num
for j in $jobs; do num[$j]=$(next "$j"); trigger "$j"; done
for j in $jobs; do
  n=${num[$j]}
  while :; do r=$(result "$j" "$n"); case $r in RUNNING|PENDING) sleep 10 ;; *) break ;; esac; done
  curl -sf "$J/job/$j/$n/consoleText" > "$OUT/$j.log"
  curl -sf "$J/job/$j/$n/testReport/api/json?tree=passCount,failCount,skipCount" > "$OUT/$j.tests.json" 2>/dev/null || true
  echo "$j #$n : $r"
done | tee "$OUT/results.txt"
