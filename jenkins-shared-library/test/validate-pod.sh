#!/usr/bin/env bash
# Valide resources/org/corp/ansibleci/pod/runner-pod.yaml : schema Kubernetes v1.33 strict (Pod) et
# contraintes SCC OpenShift restricted-v2.  Prerequis : check-jsonschema + PyYAML (pip), acces au schema
# (ou SCHEMA=/chemin/pod-v1.json en airgap).
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
sed -e 's|@RUNNER_IMAGE@|registry.example/runner:1|' -e 's|@JNLP_IMAGE@|registry.example/inbound-agent:1|' \
  "$here/resources/org/corp/ansibleci/pod/runner-pod.yaml" > "$tmp/pod.yaml"
schema=${SCHEMA:-https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/v1.33.0-standalone-strict/pod-v1.json}
check-jsonschema --schemafile "$schema" "$tmp/pod.yaml"
python3 - "$tmp/pod.yaml" <<'PY'
import sys, yaml
spec = yaml.safe_load(open(sys.argv[1]))['spec']
psc = spec['securityContext']
assert psc.get('runAsNonRoot') is True and psc['seccompProfile']['type'] == 'RuntimeDefault'
assert 'runAsUser' not in psc and not spec.get('hostNetwork') and not spec.get('hostPID')
assert all('hostPath' not in v for v in spec.get('volumes', []))
names = [c['name'] for c in spec['containers']]
assert 'runner' in names, 'le conteneur des etapes doit s appeler runner'
for c in spec['containers']:
    sc = c.get('securityContext', {})
    assert sc.get('allowPrivilegeEscalation') is False, c['name']
    assert sc.get('capabilities', {}).get('drop') == ['ALL'], c['name']
    assert 'runAsUser' not in sc and not sc.get('privileged'), c['name']
print('restricted-v2 : OK (runAsNonRoot, UID libre, drop ALL, pas d escalade, seccomp RuntimeDefault, pas de hostPath)')
PY
