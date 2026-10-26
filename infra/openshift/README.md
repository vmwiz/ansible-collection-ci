# OpenShift: CI agents for Ansible collections

| File | Usage |
|---|---|
| `../../jenkins-shared-library/resources/ansible-ci/pod.yaml` (pod of the Jenkins pipeline, image = `ciToolsImage`) | Jenkins agent pod, SCC `restricted-v2` (no fixed UID, non-root, `drop: ALL`, no privilege escalation, seccomp `RuntimeDefault`) |
| `nested-podman-pod.poc.yaml` | **POC** nested podman (OCP >= 4.20, SCC `nested-container`) - not validated |

## What runs in a restricted pod (no container engine)
lint, docs, build, galaxy-importer, security-scan, spotter, certification, `ansible-test sanity/units --venv`
(`aci` in `venv` mode, `ACI_TEST_MODE=venv`). Validated by simulating OpenShift: arbitrary UID (54321 then
1000680000, GID 0, not in `/etc/passwd`), `--cap-drop ALL`, `no-new-privileges`, no socket.

Airgap prerequisites specific to venv mode:
* ansible-test creates its venvs without pip and then runs `~/.ansible/test/cache/get_pip_<version>.py`
  (otherwise downloaded from `https://ci-files.testing.ansible.com/ansible-test/`): `aci` puts
  `lib/aci/py/get_pip_offline.py` there (`ensurepip` + pip at the requested version from Nexus). No raw
  repository needed;
* ansible-test --venv does not pass `PIP_INDEX_URL` to its venvs: the `/etc/pip.conf` of the base image
  (corporate UBI 9, see `infra/ci-tools-image/README.md`) points to Nexus.
* Validated with the UBI 9 image: UID 1000680000:0, `--cap-drop ALL`, network cut except the fake Nexus.

## What CANNOT run in a restricted pod
`ansible-test --docker` (including integration) and Molecule: they need a container engine.
Options assessed:

| Option | Realism | Comment |
|---|---|---|
| `ansible-builder` VM + rootless podman (chosen) | **High** | Validated end to end (sanity/units/integration/molecule) |
| Host Docker socket / privileged DinD | Refused | Forbidden by policy (SCC `privileged`) |
| Nested podman through user namespaces (`hostUsers: false` + SCC `nested-container`) | Medium, POC | GA in OCP 4.20 (Technology Preview in 4.19). ansible-test runs `--privileged --pid host` and systemd: to be validated |
| buildah in the pod | Off topic | Builds images, does not run test containers |
| OpenShift sandboxed containers (Kata) | Low/expensive | Pods in micro-VMs: privileges confined to the VM, but needs nested virtualisation or bare-metal nodes |
| `ansible-test integration` with `--venv`/`--local` in the pod | Limited | Only for targets that do not modify the system (API/network modules) |
