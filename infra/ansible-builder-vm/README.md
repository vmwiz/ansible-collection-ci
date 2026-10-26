# "ansible-builder" VM (rootless podman)

Jenkins agent (label `ansible-builder`) / GitLab shell runner (tag `ansible-builder`) for the stages that
need containers: `ansible-test --docker` (through podman), `integration`, `molecule`.

```bash
mkdir -p files && cp /path/to/internal-ca.crt files/corp-ca.crt
ansible-playbook -i "builder01.corp.local," -e builder_ci_user=jenkins site.yml   # or gitlab-runner
```

Points checked during validation (podman 5.4, rootless, cgroup v2):

* ansible-test detects podman by itself; `ANSIBLE_TEST_PREFER_PODMAN=1` forces it when a real `docker`
  binary is also installed (a `docker` that is only a podman alias is already ignored). Set it in the
  Jenkins agent environment (node properties) if needed.
* The test containers start **systemd** (`--systemd always --cgroupns private`): the user needs a
  **delegated** cgroup v2 subtree (systemd user session, hence `loginctl enable-linger`). Without
  delegation: `Failed to create /init.scope control group: Permission denied` then
  `can only create exec sessions on running containers`.
  Check: `cat /sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/cgroup.controllers`.
* Jobs started without a logind session (GitLab runner through `su`): set `XDG_RUNTIME_DIR=/run/user/<uid>`.
* Python: `builder_python` (python3.12, also hosts the `/opt/ansible-ci` tooling venv). 3.12 covers
  2.16 (3.10-3.12), 2.18 (3.11-3.13), 2.20 (3.12-3.14) and the certification. `builder_extra_pythons`
  (empty by default): add `python3.14` only for 2.22 / `milestone` / `devel` (RHEL 9.8 AppStream has no 3.13).
* `templates/registries-nexus.conf`: podman mirrors (quay.io, docker.io, ghcr.io) to Nexus, installed in
  `/etc/containers/registries.conf.d/`.
* `aci` scripts: copied from `ci-scripts/` (same version as the ci-tools-image) to `/opt/ansible-ci`
  (`/opt/ansible-ci/bin/aci`, the path called by the Jenkins pipeline and the GitLab component).
  Run the playbook from a checkout of the matching tag of this repository.
* EE introspection (GitLab `target-ees`): the VM must be able to pull the EE images from the Nexus mirror
  of `registry.redhat.io` or from the Private Automation Hub (`podman login` of the CI account).
* `shellcheck` (sanity) is not needed on the VM: sanity runs in `default-test-container`.
