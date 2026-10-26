# ansible-ci: CI libraries for Ansible collections (Jenkins + GitLab, airgapped/Nexus, AAP 2.6)

Jenkins library **2.1.0**, `aci` scripts and GitLab component **1.1.0**. A collection has no CI code,
only two or three lines:

```groovy
@Library('ansible-ci@v2') _
ansibleCollectionPipeline()
```
```yaml
include:
  - component: $CI_SERVER_FQDN/ci/ansible-collection-ci/ansible-collection@1
```

| Path | Content |
|---|---|
| [PROPOSITION.md](PROPOSITION.md) | Architecture, AAP 2.6 alignment, Red Hat certification, configuration, versioning, onboarding, validation, limits, roadmap |
| [USER-GUIDE.md](USER-GUIDE.md) | For the collection teams: `Jenkinsfile` and `.gitlab-ci.yml` to copy, what each stage checks |
| [ANALYSIS.md](ANALYSIS.md) | Study of the CI of 23 `ansible-collections/*` collections |
| `ci-scripts/` | **Single source** of the bash CLI `aci` (`bin/aci`, `lib/aci/cmd/*.sh`, Python helpers, `share/aci/`: pinned versions, `python-map.txt`, `certification.env`) + `tests/` (smoke, guards) |
| `jenkins-shared-library/` | One fixed declarative pipeline, `vars/ansibleCollectionPipeline.groovy` (site parameters with defaults), pod template `resources/ansible-ci/pod.yaml`, `CHANGELOG.md` |
| `gitlab-ci-templates/` | CI/CD component `ansible-collection` (`templates/ansible-collection/template.yml`, 46 inputs), examples, `tests/` (emulated rendering + GitLab schema, test collection for the component project pipeline), `CHANGELOG.md` |
| `tools/sync.sh` | Refreshes the copy of `corp.demo` used by the component tests; `--check` fails if it differs |
| `tools/export-collection.sh` | Creates a stand-alone repository with `corp.demo` at its root and `Jenkinsfile.dev` as `Jenkinsfile` (testing the library without registering it, USER-GUIDE.md §2.4) |
| `infra/jenkins/` | Admin setup in *Manage Jenkins*: global library, credentials, Kubernetes cloud, `ansible-builder` agents |
| `infra/ci-tools-image/` | ci-tools-image UBI 9 + python3.12 + `aci` in `/opt/ansible-ci` (build context = repository root) |
| `infra/ansible-builder-vm/` | Playbook of the podman VM (Jenkins agent / GitLab shell runner); installs `aci` and the `registries.conf` mirrors |
| `infra/gitlab-runner/`, `infra/openshift/` | GitLab runners, OpenShift options (nested podman POC) |
| `example-collection/corp.demo/` | Demo collection (Jenkinsfile + .gitlab-ci.yml; `Jenkinsfile.dev` loads the library without registering it) |
| `tests/` | **Internal test bench, not shipped**: Jenkins 2.580.1 end to end, real run of the rendered GitLab jobs, emulated base image (see `tests/README.md`) |

## CI maintainers: development cycle

```bash
# 1. Change ci-scripts/, then
ci-scripts/tests/smoke.sh && ci-scripts/tests/guards.sh
shellcheck -x ci-scripts/bin/aci ci-scripts/lib/aci/*.sh ci-scripts/lib/aci/cmd/*.sh
# 2. GitLab component
tools/sync.sh --check                            # test collection up to date
gitlab-ci-templates/tests/validate.sh            # rendering + official schema + jobs per context
# 3. Bench (not shipped, tests/README.md): real Jenkins + rendered GitLab jobs
tests/jenkins-e2e/run-e2e.sh
tests/gitlab-jobs/run-jobs.sh tests/gitlab-jobs/inputs/bench.yml branch "aci-lint aci-certification"
# 4. ci-tools-image (its tag is the aci version used by Jenkins and GitLab)
podman build -f infra/ci-tools-image/Containerfile --build-arg BASE_IMAGE=<registry>/corp/ubi9-corp:9.8 \
  -t nexus.corp.local:8443/corp/ci-tools-image:2026.10 .
```

## `aci` locally (ci-tools-image or VM)

```bash
cd my.collection
ACI_CORE=2.18 /opt/ansible-ci/bin/aci sanity          # venv by default; ACI_TEST_MODE=docker on the VM
/opt/ansible-ci/bin/aci certification                 # Red Hat certification checks
/opt/ansible-ci/bin/aci help                          # all commands
```

| Variable | Role |
|---|---|
| `ACI_CORE`, `ACI_CORE_VERSIONS`, `ACI_CORE_DEFAULT`, `ACI_PRERELEASE`, `ACI_CORE_PIN` | Series, matrix, default series, pre-releases, exact version |
| `ACI_PYTHON`, `ACI_PYTHON_MAP` | Controller Python (target in docker mode), series → Python table |
| `ACI_TEST_MODE` | `venv` (default) or `docker` |
| `ACI_PYPI_ENDPOINT`, `ACI_PIP_INDEX_URL`, `ACI_IMAGE_MIRROR` | Nexus (ansible-test containers, pip, quay.io images) |
| `ACI_GALAXY_URL`, `ACI_GALAXY_PUBLISH_URL`, `ACI_GALAXY_TOKEN` | Nexus Galaxy |
| `ACI_EE_MATRIX`, `ACI_EE_EXPECT_CORES` | Matrix derived from the EEs (GitLab) |
| `ACI_CERT_ENV`, `ACI_CHANGELOG_SKIP`, `ACI_TARGET_BRANCH` | Certification, changelog |
| `SPOTTER_ENDPOINT`, `SPOTTER_TOKEN`, `SPOTTER_CACERT`, `ACI_SPOTTER_EXPORT_ONLY` | Private Spotter |
| `ACI_CACHE`, `ACI_WORK`, `ACI_REPORTS` | Venv cache, work tree (outside the git repository), reports |

The placeholders to adapt are `nexus.corp.local:844x`, `hub.corp.local`, `spotter.corp.local`,
`gitlab.corp.local` and the `BASE_IMAGE` of the ci-tools-image.

An earlier nox-based prototype is no longer shipped; it is in the git history (tag `v3-nox`).
