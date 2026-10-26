# Internal test bench (not shipped)

These files were used to validate the deliverables **without** a real OpenShift cluster, GitLab instance
or Nexus. They are **not published** with the Jenkins library or the GitLab component
(`git subtree split` only takes `jenkins-shared-library/` and `gitlab-ci-templates/`), and they depend on a
bench environment prepared by hand. The fast tests stay with each deliverable: `ci-scripts/tests/`,
`gitlab-ci-templates/tests/validate.sh`.

| Directory | Role |
|---|---|
| `jenkins-e2e/` | Real Jenkins 2.580.1 set up by `init.groovy.d/` like an admin would in *Manage Jenkins* (global library, credentials, agents, jobs), library loaded from a local git repository (`v2`, `v2.1.0`). Agent `runner-1` = ci-tools-image + JDK 21 (stands in for the `ansible-runner` pod), agent `builder-1` = process on the bench host running as root with podman (stands in for the ansible-builder VM; root because the bench host has no systemd user session, hence no cgroup v2 delegation for rootless systemd containers). Jobs `corp-demo` (full example collection, 2-line Jenkinsfile), `corp-demo-lite` (no units/integration/Molecule: checks the auto-skip, pinned `@v2.1.0`), `corp-demo-params` (overridden parameters, Spotter disabled), `corp-demo-spotter` (Spotter enabled, unreachable endpoint → UNSTABLE), `corp-demo-typo` (unknown parameter → FAILURE). `run-e2e.sh` builds everything, runs the builds and collects the logs. |
| `gitlab-jobs/` | `run-jobs.sh` really runs the scripts of the jobs rendered by `gitlab-ci-templates/tests/render.py`, each in a fresh clone, in the ci-tools-image, airgapped; `inputs/bench*.yml` = bench inputs (devpi, simulated EEs, EE mismatch case). |
| `image-base-standin/` | Emulation of the corporate base image `ubi9-corp:9.8` (UBI 9 minimal, test CA, `/etc/pip.conf` to the fake Nexus). |

`jenkins-e2e/run-e2e.sh` uses the Internet (PyPI, Galaxy, quay.io) instead of Nexus and needs podman
(rootless for the containers, passwordless sudo for `builder-1`), Java 21 on the host and the bench images (`JENKINS_IMAGE`, `CI_TOOLS_IMAGE`). The bench copy of the
library replaces the `kubernetes { ... }` agent with `label 'ansible-runner'` (no cluster on the bench), archives the
rendered pod YAML (`pod-rendered.yaml`, checked by the script) and points the Nexus defaults to the public services.

`gitlab-jobs/run-jobs.sh` needs (not scripted, specific to the test machine): podman networks `airgap`
(`--internal`) and `egress`, a simulated "Nexus" container (devpi for PyPI + static Galaxy v3, alias
`nexus.corp.local`, test CA), the image `localhost/corp/ci-tools-image:2026.10` and a bare git
repository of `corp.demo`.
