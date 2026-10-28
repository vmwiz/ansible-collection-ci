# Proposal: CI libraries to test and validate Ansible collections (airgapped, Jenkins and GitLab, AAP 2.6)

*Version 2.1.0, 26/10/2026 (site settings as pipeline parameters, pod template in the library).
Previous revisions: 1.0.0 (20/10/2026), 1.0.1 (21/10/2026), 2.0.0 (23/10/2026).*

**What changed in 2.x**
* The **Jenkins shared library is a single fixed declarative pipeline** (`vars/ansibleCollectionPipeline.groovy`):
  no granular steps, no Groovy classes, no copy of the `aci` scripts. Stages and matrix are the same for
  every collection.
* **2.1.0**: site settings (Nexus URLs, Spotter, ci-tools-image, agent label, credential IDs) are **pipeline
  parameters with defaults**, defined in one map at the top of the Groovy file; the OpenShift **pod template
  ships with the library** (`resources/ansible-ci/pod.yaml`, image substituted from `ciToolsImage`); the admin
  setup is plain *Manage Jenkins* configuration (library, credentials, Kubernetes cloud, agents). The runner
  image is renamed **ci-tools-image**.
* Optional stages (units, integration, Molecule) are selected by the repository content, not by parameters.
* The pipeline calls the `aci` CLI baked into the ci-tools-image and the ansible-builder VM
  (`/opt/ansible-ci/bin/aci`).
* All documentation, comments and messages are in English (`aci` 1.1.0).
* The GitLab component is unchanged apart from the translation (still 46 inputs).

## 0. In short

```groovy
// Jenkinsfile
@Library('ansible-ci@v2') _
ansibleCollectionPipeline()
```
```yaml
# .gitlab-ci.yml
include:
  - component: $CI_SERVER_FQDN/ci/ansible-collection-ci/ansible-collection@1
```

These lines start the whole pipeline, in this order (each block only if the previous one passed):
* static analysis: lint, docs, changelog fragment on PRs/MRs, security scan, Spotter;
* ansible-test sanity and units on ansible-core 2.16 and 2.18 (plus 2.20, see §3), Python 3.12;
* integration and Molecule on the Podman VM when the collection has them;
* build **once**, galaxy-importer and Red Hat certification on that tarball;
* publication to Nexus of that same tarball on every tag.

Everything runs airgapped behind Nexus: OpenShift `restricted-v2` pods and an `ansible-builder` VM (podman).

## 1. Guiding principles

1. **The logic is central and versioned.** A collection contains no CI code: only a two-line
   `Jenkinsfile` or a short `.gitlab-ci.yml`. A fix or a tool update is released once and reaches every
   repository that follows `v2` (Jenkins) or `@1` (GitLab).
2. **One engine for both CIs.** The bash CLI `aci` (`ci-scripts/`) does all the work: venvs per series,
   Nexus, ansible-test, reports. Jenkins (Groovy) and GitLab (YAML) only **orchestrate**: stages,
   parallelism, agents, credentials, JUnit. The business rules are written once and tested with shellcheck
   and smoke tests.
3. **One pipeline for everybody (Jenkins).** No per-team options to document, validate or support. A
   change of behaviour is a new library release, not a Jenkinsfile change in N repositories.
4. **`ansible-test` stays the test engine** (sanity / units / integration), as in 100 % of the collections
   studied ([ANALYSIS](ANALYSIS.md)).
5. **Nothing goes to the Internet.** PyPI, images, collections, EEs and RPMs go through Nexus. Tools that
   download from GitHub (antsibull-nox, tox-ansible, ansible-test-gh-action) are ruled out.
6. **Aligned with the target platform** (AAP 2.6) and with the **Red Hat certification**, using the same
   tool versions as the `partner-certification-checker`.

## 2. Architecture

```mermaid
flowchart LR
  subgraph repo[ansible-collection-ci repository - CI maintainers]
    aci[ci-scripts/: bash CLI aci 1.3.0<br/>+ Python helpers, pinned versions,<br/>certification.env]
    jsl[jenkins-shared-library/<br/>vars/ansibleCollectionPipeline.groovy]
    glc[gitlab-ci-templates/<br/>templates/ansible-collection]
    img[infra/ci-tools-image<br/>UBI 9 + py3.12 + aci]
    vm[infra/ansible-builder-vm<br/>podman + aci]
  end
  aci -- COPY --> img
  aci -- playbook --> vm
  col[Collection<br/>2-line Jenkinsfile / 3-line .gitlab-ci.yml]
  col -->|@Library ansible-ci@v2| jk[Jenkins]
  col -->|include: component @1| gl[GitLab CI]
  jsl --> jk
  glc --> gl
  subgraph OCP[OpenShift restricted-v2]
    pod[ci-tools-image pod: static analysis, sanity/units --venv,<br/>build + certification, publish]
  end
  subgraph VMB[ansible-builder VM]
    pdm[podman: --docker, integration,<br/>molecule, EE introspection]
  end
  jk & gl --> pod & pdm
  pod & pdm -. PyPI, Galaxy, images, EE .-> nx[(Nexus)]
  pod -. HTTPS .-> sp[private Spotter]
```

| Component | Role | How the `aci` scripts arrive |
|---|---|---|
| `ci-scripts/` | **Single source**: `bin/aci` (dispatcher), `lib/aci/common.sh`, `lib/aci/cmd/*.sh` (one command per file), `lib/aci/py/*.py`, `share/aci/` (constraints, configurations, `python-map.txt`, `certification.env`) | — |
| `jenkins-shared-library/` | one fixed declarative pipeline, `vars/ansibleCollectionPipeline.groovy` (site parameters with defaults) + pod template `resources/ansible-ci/pod.yaml` | **from the ci-tools-image / VM** (`/opt/ansible-ci/bin/aci`) |
| `infra/jenkins/` | admin setup in *Manage Jenkins* (library, credentials, Kubernetes cloud, agents) | — |
| `gitlab-ci-templates/` | component `ansible-collection` (46 inputs) | **from the ci-tools-image / VM** (a component can only ship YAML) |
| `infra/ci-tools-image/` | image of the pods (Jenkins and GitLab) | `COPY ci-scripts` |
| `infra/ansible-builder-vm/` | podman VM (Jenkins agent, GitLab `shell` runner) | copied by the playbook |

`aci` commands: `lint`, `docs`, `build`, `importer`, `certification [sanity-cores]`, `changelog-check`,
`ee-introspect`, `sanity`, `units`, `integration`, `security-scan`, `spotter`, `molecule`, `prime-images`,
`publish`, `ee-units` (POC), `venv`, `info`. The interface is a set of `ACI_*` variables (`ACI_CORE`,
`ACI_TEST_MODE`, `ACI_PYPI_ENDPOINT`, `ACI_GALAXY_*`...; full list in [README.md](README.md)). Locally, a
developer runs the same thing: `ACI_CORE=2.18 /opt/ansible-ci/bin/aci sanity`.

Since the ci-tools-image carries `aci`, **its tag is the version of the scripts**: on Jenkins it is the `ciToolsImage`
parameter (site default in the library), on GitLab by the `runner-image` input (checked against
`ACI_EXPECTED_VERSION`).

## 3. AAP 2.6 alignment

| Series | Role | Upstream controller Python | Python used |
|---|---|---|---|
| **2.16** | AAP 2.6 (platform default) | 3.10 – 3.12 | **3.12** (the EE one) |
| **2.18** | AAP 2.5 / 2.6 / 2.7 | 3.11 – 3.13 | **3.12** |
| **2.20** | AAP 2.7; part of the certification sanity (stable-2.16/2.18/2.20) | 3.12 – 3.14 | **3.12** |

* **Jenkins**: fixed matrix 2.16 + 2.18 + 2.20, all blocking. 2.20 is included because the Red Hat
  certification checker runs sanity on stable-2.20 as well: a collection failing it would not certify.
* **GitLab**: default matrix 2.16 + 2.18 (`ansible-core-versions`), optional non-blocking series
  (`ansible-core-optional`), and the `aci-certification-sanity` job adds the certification series not
  already covered (2.20 by default).

The ranges come from `CONTROLLER_PYTHON_VERSIONS` of the ansible-test `stable-2.16/2.18/2.20` branches.
They are centralised in `share/aci/python-map.txt`, where 3.12 comes first for every series that accepts it
(2.16 → 2.21). The ci-tools-image and the VM therefore only need **python3.12**. 2.22, `milestone` and
`devel` (controller ≥ 3.13) need a 3.14 controller: a second ci-tools-image built from
`corp/hub/python3:3.14` (one Python per image), or `python3.14` on the VM. Without it, `aci` stops with "no controller Python for ansible-core 2.22 on this agent".

**Matrix derived from the EEs (GitLab only, `target-ees`)**: on the VM,
`podman run --rm --pull=missing --network none --entrypoint ansible <EE> --version` reads `ansible [core X.Y.Z]`
and `python version = A.B`; `ee_matrix.py` checks that the series is known, the Python is in the controller
range and the version satisfies `requires_ansible`, otherwise the pipeline fails immediately. The GitLab
matrix is static, so `ansible-core-versions` must list exactly the EE series (the introspection job prints
the value to use). The Jenkins pipeline has no EE introspection: its matrix is fixed.

## 4. Pipeline stages

### 4.1 Jenkins (fixed)

| Stage | `aci` | Agent | When |
|---|---|---|---|
| 1. Static analysis › Lint | `lint` (yamllint --strict, antsibull-changelog lint, ansible-lint --offline) | pod | always |
| 1. Static analysis › Docs | `docs` (antsibull-docs) | pod | always |
| 1. Static analysis › Changelog fragment | `changelog-check` | pod | pull requests (`changeRequest()`) |
| 1. Static analysis › Security scan | `security-scan` (blocking from HIGH) | pod | always |
| 1. Static analysis › Spotter | `spotter` (private instance), findings → UNSTABLE | pod | `spotterEndpoint` not empty |
| 2. ansible-test (matrix `ACI_CORE` = 2.16, 2.18, 2.20) | `sanity`, `units` | pod (`venv` mode) | always; units if `tests/unit/` exists |
| 3. Container tests › Integration | `integration` (`ACI_TEST_MODE=docker`, default image, ansible-core 2.18) | VM | `tests/integration/targets/` exists |
| 3. Container tests › Molecule | `molecule` | VM | `extensions/molecule/` exists |
| 4. Package & certify | `build` (tarball archived + fingerprinted, `stash 'dist'`), `importer`, `certification` (both on that tarball) | pod | always |
| 5. Publish | `unstash 'dist'`, `publish` of the certified tarball (tag = `galaxy.yml` version) | pod | tag builds (`buildingTag()`) |

Each block runs only if the previous one passed (UNSTABLE, e.g. Spotter findings, does not stop it). The
collection is built **once**, after all the tests: `aci importer`, `aci certification` and `aci publish`
never rebuild, they take `dist/<ns>-<name>-<version>.tar.gz` (and stop if it is missing) and log its
sha256, so the published artifact is the certified one.

The matrix uses the declarative `matrix` directive: its axis values are literals, which is possible now
that the matrix is fixed. Each `aci` call archives `reports/**` and publishes its JUnit files; the exit
code of `aci` alone decides the stage result.

### 4.2 GitLab (configurable)

Same order as Jenkins, chained with `needs` (optional needs: a job disabled by its input is not waited
for; `allow_failure` jobs do not block). `aci-build` and `aci-certification` are in `stage-test`, after the
container tests; `aci-publish` (`stage-publish`) takes the `dist/` artifact of `aci-build`.

| Block | GitLab job | `aci` | Agent | When |
|---|---|---|---|---|
| (`.pre`) EE introspection | `aci-ee-introspect` | `ee-introspect` | VM | `target-ees` |
| 1. Lint / Docs | `aci-lint`, `aci-docs` | `lint`, `docs` | pod | always |
| 1. Changelog | `aci-changelog` | `changelog-check` | pod | MR |
| 1. Security / Spotter | `aci-security`, `aci-spotter` | `security-scan`, `spotter` | pod | always / `spotter` |
| 2. Sanity / units | `aci-{sanity,units}-{venv,docker}` (`parallel:matrix`) | `sanity`, `units` | pod (venv) / VM (docker) | always; docker on main/tags/schedules in `auto` mode |
| 2. Optional series | `aci-optional-cores` | `sanity`, `units` | pod | `ansible-core-optional` |
| 2. Certification sanity | `aci-certification-sanity` | `sanity` (Python 3.12) | pod | series 2.16/2.18/2.20 ≥ `requires_ansible` not yet covered with 3.12 |
| 3. Integration / Molecule | `aci-integration`, `aci-molecule` | `integration`, `molecule` | VM | `integration` / `molecule` |
| 2. EE units (POC) | `aci-ee-units` | `ee-units` | VM | `ee-tests` |
| 4. Build + import | `aci-build` | `build`, `importer` | pod | always |
| 4. Certification | `aci-certification` | `certification` (on the `aci-build` tarball) | pod | always (can be disabled) |
| 5. Publication | `aci-publish` | `publish` (the `aci-build` tarball) | pod | tag |

Reports are written to `reports/<stage>-<series>/`: JUnit (published by Jenkins `junit` and GitLab
`artifacts:reports:junit`), `importer_result.json`, SARIF, `guards.txt`, `matrix.txt`; all archived.

**Workspace layout (2.4.0).** The workspace holds three siblings: `src/` (the collection), `reports/` and
`dist/`. Every tool (yamllint, antsibull-changelog, ansible-lint, antsibull-docs, security scanner,
Spotter, ansible-test, Molecule, certification guards, `ansible-galaxy collection build`) only sees
`src/**`, so no tool can lint, scan or package a report or a previous tarball, whatever the collection's
`build_ignore`, `.ansible-lint` or `.gitignore` say. Jenkins: `checkoutToSubdirectory('src')`. GitLab: the
runner clone stays at `CI_PROJECT_DIR` (artifacts must be under it, and `GIT_CLONE_PATH` cannot point
outside it), and each job adds a `src/` git worktree of the same commit (tracked files only, shares `.git`,
no fetch). `aci` (1.3.0): `ACI_SRC` defaults to `./src` when `./src/galaxy.yml` exists, else the current
directory; `ACI_REPORTS`/`ACI_DIST` default to the siblings of `src/`, else to `/tmp/aci-<uid>/<name>/`;
it refuses any of them inside `ACI_SRC`.

Why: before 2.4.0 `reports/` and `dist/` were inside the collection. ansible-lint and the scanners
excluded them explicitly, but `ansible-galaxy collection build` only honours the collection's own
`build_ignore`: a collection without `reports`/`dist` there shipped `reports/security/*.sarif`, the
certification reports and the previous tarball, and galaxy-importer then ran ansible-lint on the extracted
tarball, SARIF included. 2.3.0 made it systematic by building after all the scans.

## 5. Red Hat certification (reference: partner-certification-checker v6.0.0)

All versions are in **one file**, `ci-scripts/share/aci/certification.env` (overridable with
`ACI_CERT_ENV`), updated when the checker changes:

```
ACI_CERT_CHECKER_VERSION=6.0.0      ACI_CERT_PYTHON=3.12           ACI_CERT_ANSIBLE_CORE=2.16.19
ACI_CERT_GALAXY_IMPORTER=0.4.39     ACI_CERT_ANSIBLE_LINT=26.4.0   ACI_CERT_EXTRA_PIP="distlib>=0.3.9"
ACI_CERT_IMPORTER_CHECK_REQUIRED_TAGS=True   ACI_CERT_IMPORTER_RUN_ANSIBLE_LINT=False
ACI_CERT_SANITY_CORES="2.16 2.18 2.20"       ACI_CERT_SANITY_PYTHON=3.12
ACI_CERT_SUPPORTED_CORES="2.16 2.18 2.20"    + list of allowed ignores, mandatory ansible-lint rules
```

| Checker control | Reproduction | Difference |
|---|---|---|
| galaxy-importer 0.4.39, Python 3.12, `ansible-core==2.16.19`, `distlib>=0.3.9`, `CHECK_REQUIRED_TAGS=True`, `RUN_ANSIBLE_LINT=False`, `--git-clone-path` | dedicated pinned venv, `python -m galaxy_importer.main dist/<ns>-<name>-<version>.tar.gz` (the tarball of `aci build`) | the checker builds the tarball from a git clone (`--git-clone-path`); `aci` imports the one already built, so the certified tarball is the published one (same content: same `ansible-galaxy collection build` of the same tree) |
| ansible-lint 26.4.0 `--profile=production` | same version, same profile, `--offline` | `--offline` (airgap) |
| sanity `stable-2.16/2.18/2.20` filtered by `requires_ansible` (regex `>=X.Y`), Python 3.12 | Jenkins: the fixed matrix (venv, Python 3.12); GitLab: `aci certification sanity-cores` then `aci sanity` for the uncovered series | the checker runs `ansible-test-gh-action` in docker; here the sanity runs in venv mode with Python 3.12 |

**Guards** (`cert_guards.py`, report `reports/certification/guards.txt`), which fail with an explicit message:
1. **Sanity ignores**: any line of `tests/sanity/ignore-*.txt` outside the closed list of the ansible-lint
   `sanity` rule is refused:
   * allowed list: `validate-modules:missing-gplv3-license`, `action-plugin-docs`,
     `import-2.6/2.7/3.5`, `compile-2.6/2.7/3.5` (and their `!skip` form), `shebang`, `shellcheck`,
     `pylint:used-before-assignment`;
   * only `plugins/` and `roles/` paths are checked, like the rule does;
   * **tracked derogation**: a `# aci-derogation: <reason>` comment on the line turns the error into a warning.
2. **`.ansible-lint`**: `profile` is `production` or absent; none of the 10 mandatory rules in `skip_list`,
   `warn_list` or `.ansible-lint-ignore`; no `exclude_paths` hiding `plugins/`, `roles/` or `extensions/`
   (except `extensions/molecule`).
3. **`requires_ansible`**: its lower bound must be a supported series (2.16, 2.18 or 2.20). A 2.19 bound
   (tech preview) is refused.

## 6. Configuration

### 6.1 Jenkins: fixed stages, site settings as parameters

What used to be ~60 parameters (1.x) is now either fixed in the pipeline or one of ten **site parameters**
with defaults, defined in a single `DEFAULTS` map at the top of `vars/ansibleCollectionPipeline.groovy`.
A Jenkinsfile normally passes nothing; it can override a site parameter
(`ansibleCollectionPipeline(spotterEndpoint: 'https://spotter.corp.local/api', spotterCredentialsId: 'my-team-spotter')`).
Unknown keys stop the build before any agent is allocated.

| Setting | Where | Value |
|---|---|---|
| Matrix | pipeline (fixed) | 2.16, 2.18, 2.20 on Python 3.12 |
| Test mode | pipeline (fixed) | `venv` in the pod for sanity/units, `docker` on the VM for integration |
| Optional stages | repository content | `tests/unit/`, `tests/integration/targets/`, `extensions/molecule/` |
| Timeouts, history | pipeline (fixed) | 90 min per build, 20 builds kept |
| Nexus | parameters `galaxyUrl`, `galaxyPublishUrl`, `pypiEndpoint`, `imageMirror` | → `ACI_GALAXY_URL`, `ACI_GALAXY_PUBLISH_URL`, `ACI_PYPI_ENDPOINT`, `ACI_IMAGE_MIRROR` |
| Spotter | parameters `spotterEndpoint` (empty = stage skipped), `spotterCacert` | → `SPOTTER_ENDPOINT`, `SPOTTER_CACERT` |
| ci-tools-image (= `aci` version) | parameter `ciToolsImage`, substituted into `resources/ansible-ci/pod.yaml` | `nexus.corp.local:8443/corp/ci-tools-image:2026.10.2` |
| Podman agents | parameter `builderLabel` | `ansible-builder` |
| Secrets | parameters `spotterCredentialsId`, `galaxyCredentialsId` = IDs of Jenkins Secret text credentials | `spotter-api-token`, `nexus-galaxy-hosted-token` |
| Library version | *Manage Jenkins* global library | default `v2` |

Admin setup (library, credentials, Kubernetes cloud, agents): [`infra/jenkins/README.md`](infra/jenkins/README.md).

### 6.2 GitLab: inputs

The component keeps its 46 inputs (stages, ci-tools-image and tags, matrix, per-job switches, ansible-test
arguments, Nexus URLs, scanner thresholds); full table in `gitlab-ci-templates/README.md`. They are checked
by GitLab (types, `options`, `regex`) when the pipeline is created. Simplifying the component in the same
way as the Jenkins library is possible but not done in 2.x.

## 7. Versioning and release

### 7.1 Rules
* **SemVer** per deliverable:
  * Jenkins library: tags `vX.Y.Z` + **moving tag `v2`** (the library default version). Current: **2.4.0**.
  * `aci` scripts and ci-tools-image: `ci-scripts/VERSION` = image tag `aci-X.Y.Z`. Current: **1.3.0** (`2026.10.2`).
  * GitLab component: tags `X.Y.Z` (catalog format). Current: **1.3.0** (`ACI_EXPECTED_VERSION` = `ci-scripts/VERSION`).
* **Patch**: fix. **Minor**: compatible change (new stage that only runs when the repository opts in,
  compatible tool update). **Major**: changed default behaviour (e.g. matrix change for AAP 2.7), removed
  stage, or incompatible `aci` change.
* `CHANGELOG.md` in each deliverable.

### 7.2 Release procedure (CI maintainers)
1. Change `ci-scripts/`, then run `ci-scripts/tests/smoke.sh`, `ci-scripts/tests/guards.sh`, shellcheck and,
   in the ci-tools-image, `ci-scripts/tests/layout.sh` (real tools, needs the package index).
2. Run `tools/sync.sh --check`, `gitlab-ci-templates/tests/validate.sh`, then the bench
   (`tests/jenkins-e2e/run-e2e.sh`, `tests/gitlab-jobs/run-jobs.sh`, see `tests/README.md`).
3. Update `VERSION`, the `CHANGELOG.md` files, `ACI_EXPECTED_VERSION` and the default `runner-image` of the
   component (`validate.sh` checks consistency).
4. Build and push the ci-tools-image (`YYYY.MM[.N]` + `aci-X.Y.Z`, never overwrite a published tag), update the `ciToolsImage` default of the
   Jenkins library, re-run the VM playbook.
5. Publish:
   * `git subtree split --prefix jenkins-shared-library` → repository `ci/ansible-ci-jenkins`, tag `vX.Y.Z`
     and move the `v2` tag;
   * `git subtree split --prefix gitlab-ci-templates` → component project `ci/ansible-collection-ci`, tag
     `X.Y.Z` (`release` job).

### 7.3 Why the scripts live in the ci-tools-image
Three options were assessed: scripts **baked into the image**, **cloned by the job**, or **inline in the
YAML** (details in `gitlab-ci-templates/README.md`). Baked into the image wins: no extra network access in
jobs, version pinned by the image tag, same tested files for Jenkins and GitLab. Until 1.0.1 the Jenkins
library shipped its own copy of the scripts (`libraryResource`); 2.0.0 drops that copy and uses the image,
which removes `tools/sync.sh`'s scripts copy and the risk of two diverging versions.

## 8. Onboarding a collection

1. `meta/runtime.yml`: `requires_ansible: '>=2.16.0'` (or `>=2.18.0`); `galaxy.yml`: `tags` (mandatory),
   `build_ignore: [Jenkinsfile, Jenkinsfile.dev, .gitlab-ci.yml]`; `.gitignore`: `tests/output/` (reports and
   dist are outside the collection since 2.4.0).
2. Python files: header `from __future__ import (absolute_import, division, print_function)` +
   `__metaclass__ = type` (2.16 sanity and certification).
3. `.ansible-lint`: `profile: production` (or absent); `changelogs/config.yaml` (antsibull-changelog);
   `.yamllint` recommended.
4. Add the `Jenkinsfile` or the minimal `.gitlab-ci.yml` (§0, [USER-GUIDE.md](USER-GUIDE.md)).
   * **Jenkins**: **multibranch** job (PRs, changelog check, tag builds).
   * **GitLab**: masked variables `ACI_GALAXY_TOKEN` (protected) and `SPOTTER_TOKEN`, protected tags
     `*.*.*`, MR pipelines (`workflow:rules`).
5. First run on a branch. Fix in this order: certification guards, lint, sanity.

## 9. Agents

| Stage | OpenShift pod (`restricted-v2`, ci-tools-image, no container engine) | `ansible-builder` VM (rootless podman) |
|---|---|---|
| lint, docs, build, galaxy-importer, certification, changelog, security, spotter, publication | ✔ | |
| sanity/units in `--venv` mode (Python 3.12) | ✔ | |
| sanity/units in `--docker default` mode (all Pythons; GitLab `test-mode: docker`/`auto`) | | ✔ |
| EE introspection, integration, Molecule, EE POC | | ✔ |

### 9.1 Jenkins pod and GitLab runner
* **Jenkins**: pod template `resources/ansible-ci/pod.yaml` in the library: containers `jnlp` and `runner`
  (image `@@CI_TOOLS_IMAGE@@` ← `ciToolsImage`), `runAsNonRoot`, seccomp `RuntimeDefault`, `drop: ALL`, no
  privilege escalation, no `runAsUser` (OpenShift assigns an arbitrary UID with GID 0), requests/limits and
  an `emptyDir` for `/tmp`. The pipeline reads it once with `libraryResource`, substitutes the image and
  uses it with `kubernetes { yaml podYaml; defaultContainer 'runner' }`; the Kubernetes cloud needs no pod
  template.
* **GitLab**: Kubernetes runner (tag `ansible-runner`), `privileged = false`, `cap_drop = ["ALL"]`, helper
  `gitlab-runner-helper-ocp` from Nexus; `shell` runner on the VM (tag `ansible-builder`). See
  `infra/gitlab-runner/config.toml.example`.

### 9.2 `ansible-builder` VM: rootless podman
* ansible-test looks for `docker` then `podman` (`DOCKER_COMMANDS`) and ignores a `docker` that is only a
  podman alias; `ANSIBLE_TEST_PREFER_PODMAN=1` reverses the order.
* The test containers start systemd (`--systemd always --cgroupns private`): the CI user needs a **cgroup v2
  delegation** (systemd user session, `loginctl enable-linger`), `/etc/subuid`/`/etc/subgid` ranges, and
  `XDG_RUNTIME_DIR` for jobs started without a logind session (GitLab `shell` runner).
* Automated setup: `infra/ansible-builder-vm/site.yml` (podman, python3.12, CA, `/etc/pip.conf`, Nexus
  `registries.conf`, linger, `aci` scripts in `/opt/ansible-ci`).
* A single VM is a single point of failure: plan 2 (same label) and size the executors (one job = 2 to 3
  containers; `default-test-container` takes 1.55 GB).

### 9.3 Options to drop the VM on OpenShift
| Option | Status | Assessment |
|---|---|---|
| Host socket / DinD / `privileged` | Forbidden by the SCCs | Excluded |
| **Nested podman with user namespaces** (`hostUsers: false`, SCC `nested-container`) | **GA in OCP 4.20** ([release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/release_notes/ocp-4-20-release-notes)), Technology Preview in 4.19 | Most realistic option. ansible-test starts a `--privileged --pid host` container and systemd containers: **POC required** (`infra/openshift/nested-podman-pod.poc.yaml`, not validated) |
| buildah | — | Builds images, does not run test containers: off topic |
| OpenShift sandboxed containers (Kata) | Supported product | Pods in micro-VMs: needs bare-metal nodes or nested virtualisation; heavy for CI |
| `ansible-test integration --venv/--local` in the pod | Possible | Only for targets that do not modify the system (API, network) |

## 10. Nexus repositories to configure

| Repository | Format / type | Remote URL | Usage |
|---|---|---|---|
| `pypi-proxy` | PyPI proxy | `https://pypi.org` | ansible-core, ansible-lint, antsibull-*, galaxy-importer, test dependencies |
| `pypi-hosted` | PyPI hosted | — | internal tools, patched wheels |
| `pypi-group` | PyPI group | proxy + hosted | **single index**: `https://nexus.corp.local/repository/pypi-group/simple` |
| `quay-proxy` | Docker proxy (dedicated connector, e.g. port 8444) | `https://quay.io` | `quay.io/ansible/*-test-container`, `ansible-test-utility-container`, `quay.io/ansible-community/test-image:*` |
| `dockerhub-proxy` | Docker proxy | `https://registry-1.docker.io` | *optional*: service images of integration / Molecule targets (mysql, postgres, vault...) |
| `ghcr-proxy` | Docker proxy (e.g. port 8445) | `https://ghcr.io` | *optional*: helper images of some targets (e.g. `ghcr.io/ansible-collections/*`) |
| `docker-hosted` (+ `docker-group`, e.g. port 8443) | Docker hosted / group | — | corporate UBI 9 base image, ci-tools-image, internal Molecule images |
| `ansible-proxy` | **Ansible** proxy (Nexus ≥ 3.93.0) | `https://galaxy.ansible.com` | collection dependencies |
| `ansible-hosted` | Ansible hosted | — | **publication** of internal collections |
| `ansible-group` | Ansible group | proxy + hosted | single resolution point for `ansible-galaxy` |
| `ubuntu-proxy` | APT proxy | `http://archive.ubuntu.com/ubuntu` | *optional*: only if integration targets install packages in the Ubuntu ansible-test containers |
| `raw-hosted` | Raw | — | *optional*: ansible-core `devel`/`milestone` tarballs (`ACI_CORE_SRC_DEVEL` / `ACI_CORE_SRC_MILESTONE`), kind/helm binaries. The `get-pip` scripts are **no longer** needed (§12) |
| `gitlab-registry-proxy` (e.g. port 8446) | Docker proxy | `https://registry.gitlab.com` | helper image `gitlab-runner-helper-ocp` for the Kubernetes executor on OpenShift |
| `redhat-registry-proxy` (e.g. port 8447) | Docker proxy | `https://registry.redhat.io` (Red Hat service account) | **AAP EEs** (`ansible-automation-platform-26/ee-minimal-rhel9`...) for `target-ees`; or Private Automation Hub |
| `rpm-proxy` / BaseOS-AppStream repositories (+ optional EPEL 9) | Yum proxy | RHEL 9 / UBI 9 repositories | corporate UBI 9 Python image and ci-tools-image (git, ssh, jq...); `ansible-builder` VM (podman, python3.12...); EPEL only for the `ShellCheck` RPM |

Nexus notes:
* enable the **Docker Bearer Token** and **Ansible Galaxy Bearer Token** realms ([Sonatype doc](https://help.sonatype.com/en/configure-ansible-with-nexus.html)). The Nexus Galaxy token is `base64("user:password")`;
* native support of the Ansible format arrived with **Nexus 3.93.0 (04/06/2026)** ([release notes](https://help.sonatype.com/en/sonatype-nexus-repository-3-93-0-release-notes.html)). On an older version, see the alternatives in §13;
* Docker Engine only applies `registry-mirrors` to `docker.io`. For quay.io and ghcr.io, use either the
  **re-tag** (§11.2) or Podman with `registries.conf` (`infra/ansible-builder-vm/templates/registries-nexus.conf`,
  installed by the VM playbook).

## 11. Images

### 11.1 ci-tools-image (`infra/ci-tools-image/`, details in its README)
* `FROM` the corporate **UBI 9 Python** image (`ARG BASE_IMAGE`, default
  `nexus.corp.local:8443/corp/hub/python3:3.12`, registry prefix = placeholder). The CA, `/etc/pip.conf`
  (Nexus), the internal microdnf repositories **and Python** (`/usr/bin/python`, `python3`, `python3.12`,
  same for pip) come from this base.
* **One Python per image**, the base one: 3.12 covers 2.16, 2.18, 2.20, the certification and matches the
  Python of the AAP EEs; it is the `ansible-test --venv` controller and hosts `/opt/ansible-ci`. For
  2.22 / `devel`, build another image with `BASE_IMAGE=.../corp/hub/python3:3.14` (images exist for 3.6 to 3.14).
* Adds `git-core`, `openssh-clients`, `tar`, `gzip`, `rsync`, `jq`; a tooling venv `/opt/ansible-ci`
  (PyYAML, shellcheck-py); the **`aci` scripts** (`/opt/ansible-ci/bin/aci`); the `ci` user (UID 1001,
  GID 0, HOME with `g=u`, compatible with an arbitrary OpenShift UID).
* No container engine or CLI. **277 MB** (stand-in base, v2.2.0). Tags `2026.MM` and `aci-X.Y.Z`.
* ansible-core is not in the image: `aci` creates one venv per series (`~/.cache/ansible-ci/venv`, `flock`
  lock), from Nexus.

### 11.2 ansible-test images: mirror and re-tag (chosen approach)
ansible-test reads its images from `ansible_test/_data/completion/docker.txt`. This file cannot be
overridden, and the tag depends on the ansible-core version:

| ansible-core | `default` (collections) | `base` |
|---|---|---|
| 2.16.19 | `quay.io/ansible/default-test-container:8.12.0` | `base-test-container:5.10.0` |
| 2.18.19 | `default-test-container:10.9.0` | `base-test-container:7.7.0` |
| 2.20.10 | `default-test-container:v2.20-4` | `v2.20-2` |

However, **ansible-test does not pull an image that is already present locally** (`docker_util.py`:
*"Skipping pull of existing image"*). `aci prime-images` (`lib/aci/py/prime_images.py`) uses this:
1. reads `docker.txt` in the venv of the series, so for the right ansible-core version;
2. `podman pull <ACI_IMAGE_MIRROR>/ansible/default-test-container:<tag>` from Nexus;
3. `podman tag ... quay.io/ansible/default-test-container:<tag>`.

The semantics of the `default` alias are kept: sanity and units run on **all** target Python versions of
the image of the series. It also pulls **`ansible-test-utility-container`**, which ansible-test uses in every
`--docker` run to probe cgroups and audit and to remount `/sys/fs/cgroup`
(`docker run --pid host --privileged ... nsenter`). Without it, even sanity fails when airgapped.

*Podman variant*: `registries.conf` with a mirror for `quay.io`, `ANSIBLE_TEST_PREFER_PODMAN=1` and an empty
`ACI_IMAGE_MIRROR`. The re-tag is then unnecessary.

## 12. pip when airgapped

| Level | Mechanism | Note |
|---|---|---|
| Runner and `aci` venvs | `/etc/pip.conf` (+ optional `ACI_PIP_INDEX_URL`) | **Never** put `~/.pip/pip.conf` on the runner: ansible-test refuses to overwrite it outside a managed container (*"Refusing to overwrite existing file"*, `pypi_proxy.py`) |
| ansible-test containers (controller and targets) | **`--pypi-endpoint <URL>`** (`ACI_PYPI_ENDPOINT`, added by `aci` in docker mode) | Hidden option (`argparse.SUPPRESS`) but implemented and passed to the delegated invocation. ansible-test writes `~/.pip/pip.conf` (`index-url` + `trusted-host`) in the container and removes it at the end |
| `ansible-test --venv` (OpenShift pods) | `/etc/pip.conf` of the **UBI 9 base image** **only** | ansible-test **does not pass** `PIP_INDEX_URL` to its venvs. pip is bootstrapped by `lib/aci/py/get_pip_offline.py` (ensurepip + Nexus) |

Observations from the tests:
* **sanity** installs nothing in docker mode, since the venvs are pre-built in `default-test-container`;
* **units `--requirements`** installs `tests/unit/requirements.txt` **in the container**. Without
  `--pypi-endpoint`, pip goes to `pypi.org` and fails when airgapped; with it, it works. Both cases were tested;
* **integration** installs at least `requirements/ansible.txt` in the controller container;
* `PIP_INDEX_URL` set in the job is **not propagated** into the ansible-test containers;
* `trusted-host` is set on the index host, which **disables TLS verification** for that host in the test
  containers. Acceptable for an internal Nexus.

## 13. Galaxy collections (dependencies and publication)

* `ansible.cfg` generated by `aci` (servers = `ACI_GALAXY_URL`, `ACI_GALAXY_PUBLISH_URL`), passed **only** to
  `ansible-galaxy` through `ANSIBLE_CONFIG` so that ansible-test is not affected.
* Tokens outside the repository: `ANSIBLE_GALAXY_SERVER_<NAME>_TOKEN` (set by `aci publish` from
  `ACI_GALAXY_TOKEN`), or `_USERNAME` / `_PASSWORD` for basic auth (mechanism checked in `ansible/config/manager.py`).
* Dependencies (`galaxy.yml: dependencies`, `tests/requirements.yml`, `tests/unit/requirements.yml`,
  `tests/integration/requirements.yml`) are installed **in the same `ansible_collections` root** as the
  collection, and ansible-test picks them up.
* Publication: `ansible-galaxy collection publish dist/<ns>-<name>-<ver>.tar.gz --server aci_publish`.
* Alternatives if Nexus < 3.93: **Private Automation Hub** (galaxy_ng); or tarballs in a Nexus *raw*
  repository then `ansible-galaxy collection install <file>.tar.gz --offline`; or internal Git mirrors of
  the collections (`git+https://gitlab.corp.local/...`).

## 14. Validation

The bench (`tests/`, not shipped): devpi + static Galaxy v3 behind `nexus.corp.local` with a test CA for
the airgapped runs, UID `1000680000:0`, `--cap-drop ALL`, `no-new-privileges`, collection `corp.demo`
(module, role `motd`, Molecule), `requires_ansible: '>=2.16.0'`.

### 14.1 Releases 2.0.0 (23/10/2026) and 2.1.0 (26/10/2026)
* `aci` 1.1.0 (translated messages): shellcheck clean, `ci-scripts/tests/smoke.sh`, `ci-scripts/tests/guards.sh`
  (assertions updated to the English messages).
* GitLab component 1.1.0 (translated): `gitlab-ci-templates/tests/validate.sh` against the official GitLab
  schema.
* Jenkins library 2.0.0: Groovy compiled with the Groovy of Jenkins 2.580.1 (groovy-all 2.4.21), and run end
  to end on **Jenkins 2.580.1** by `tests/jenkins-e2e/run-e2e.sh`. 2.1.0: Jenkins set up like an admin
  would in *Manage Jenkins* (init scripts: global library, Secret text credentials, agents, jobs), the
  library loaded from a local git repository (moving tag `v2` and pinned `v2.1.0`), the static agent
  `runner-1` (ci-tools-image + JDK) standing in for the pod, and a host agent with podman standing in for the
  VM. Packages came from the Internet (PyPI, Galaxy, quay.io) on this run, not from the simulated Nexus.
  Results are in §14.3.

### 14.2 Release 1.x (20-21/10/2026, airgapped)
* Real runs in the ci-tools-image, airgapped: `lint`, `docs`, `build`, `importer`, `security-scan`, `spotter`
  (export only); sanity on 2.16, 2.18 and 2.20 with Python 3.12; units on 2.16 and 2.18; `certification`
  (guards 0 errors, galaxy-importer 0.4.39 OK, ansible-lint 26.4.0 `production` passed).
* EE introspection with real podman and *simulated* EEs (UBI 9 + Python 3.12 + ansible-core 2.16.19 / 2.18.19):
  correct matrix; `requires_ansible: '>=2.18.0'` with a 2.16 EE → immediate failure; image without ansible
  → clear message; Python out of range → refused.
* Jenkins 1.0.0 library on Jenkins 2.580.1, airgapped, `venv` mode: full pipeline SUCCESS (130 s).
* GitLab component: `validate.sh` against the official schema; `tests/gitlab-jobs/run-jobs.sh` really ran the
  scripts of the rendered jobs (introspection, certification, lint, docs, build, security, sanity/units
  venv 2.16 and 2.18 with the EE exact version, optional cores, certification sanity, changelog on MR with
  and without fragment, EE mismatch → failure with the value to use).
* Earlier releases (nox prototypes) validated the rootless podman VM in docker mode (sanity, units,
  integration, Molecule). They are only in the git history (tag `v3-nox`).

### 14.3 Jenkins end-to-end results

**2.4.0 (28/10/2026)**: workspace layout `src/` + `reports/` + `dist/` (`checkoutToSubdirectory('src')`),
ci-tools-image `2026.10.2` (`aci` 1.3.0, stand-in base). `check-run.py` also checks that the archived
tarball has no `reports/`, `dist/` or SARIF member and that every artifact is under `reports/` or `dist/`.

| Job | Result | What it shows |
|---|---|---|
| `corp-demo` | **SUCCESS**, 261 s | checkout in `corp-demo/src` and `corp-demo@2/src`; 4 blocks in order; tarball 53 members, none from `reports/`/`dist/`; 93 artifacts; same sha256 build = importer = certification = archived; JUnit 78 (the informational MEDIUM finding) |
| `corp-demo-lite` (`@v2.1.0`) | **SUCCESS**, 225 s | auto-skip of units, Integration, Molecule still works with the `src/` paths |
| `corp-demo-params` | **SUCCESS**, 251 s | same as `corp-demo` with the overridden parameters |
| `corp-demo-spotter` | **UNSTABLE** (expected), 241 s | Spotter UNSTABLE does not stop the next blocks |
| `corp-demo-typo` | **FAILURE** (expected), 3 s | unknown parameter, no stage |
| `corp-demo-release` » `1.0.0` (tag build) | **SUCCESS**, 234 s | Publish from the stash: build = importer = certification = publish = archived = uploaded (sha256 `b6664e86…`) |

No script approval. `ci-scripts/tests/layout.sh` in the `2026.10.2` image: `reports/` and `dist/` poisoned
(YAML failing yamllint/ansible-lint, `curl | sh` task, SARIF), `galaxy.yml` without `reports`/`dist` in
`build_ignore`: lint, docs, security-scan, build pass and never mention them, the tarball has none of them
(the same poison inside `src/` makes lint and security-scan fail and lands in the tarball).

**2.3.0 (28/10/2026)**: new order (static analysis → ansible-test → container tests → package & certify →
publish), ci-tools-image `2026.10.1` (`aci` 1.2.0, stand-in base). Order checked from `wfapi/describe`
(every executed stage of a block ends before the next block starts); tarball sha256 compared across steps.

| Job | Result | What it shows |
|---|---|---|
| `corp-demo` | **SUCCESS**, 271 s | 4 blocks in order; one `ansible-galaxy collection build`; build = importer = certification = archived artifact (same sha256); JUnit 78 (the informational MEDIUM finding) |
| `corp-demo-lite` (`@v2.1.0`) | **SUCCESS**, 251 s | units, Integration, Molecule skipped; container block empty, package after ansible-test |
| `corp-demo-params` | **SUCCESS**, 289 s | same as `corp-demo` with the overridden parameters |
| `corp-demo-spotter` | **UNSTABLE** (expected), 259 s | Spotter UNSTABLE does not stop the next blocks |
| `corp-demo-typo` | **FAILURE** (expected), 3 s | unknown parameter, no stage |
| `corp-demo-release` » `1.0.0` (tag build) | **SUCCESS**, 274 s | Publish after Package & certify: `unstash 'dist'`, `aci publish` to the fake Galaxy; build = importer = certification = publish = archived = uploaded tarball (sha256 `1ea9d8ac…`) |

Longer than 2.2.0 (~150 s) because the static analysis no longer runs in parallel with the tests. No script approval.

**2.2.0 (26/10/2026)**: ci-tools-image rebuilt `FROM` a stand-in of `corp/hub/python3:3.12` (UBI 9 minimal +
UBI AppStream `python3.12`/`python3.12-pip` linked as `/usr/bin/python`, `python3`, `pip`, `pip3`, no Python 3.9),
277 MB. Same five jobs and results as 2.1.0: `corp-demo` SUCCESS 150 s (JUnit 78, sanity + units 2.16 / 2.18 /
2.20 with a Python 3.12 controller), `corp-demo-lite` SUCCESS 144 s, `corp-demo-params` SUCCESS 165 s,
`corp-demo-spotter` UNSTABLE, `corp-demo-typo` FAILURE (expected). The bench agent image adds
`java-21-openjdk-headless`, which pulls the RHEL `python3` 3.9 onto `/usr/bin/python3`: the first build failed
(tooling venv linked to `/usr/bin/python3`, pip saw no ansible-core ≥ 2.16); the venv is now created from the
resolved versioned interpreter. A `corp/hub/python3:3.14` stand-in was also built: `aci` picks python3.14 for
2.20 / 2.22 and stops on 2.16 with "no controller Python".

**2.1.1 (26/10/2026)**: `DEV=1 run-e2e.sh`, **no** Global Pipeline Library configured (checked: empty list); the
jobs load the library with the `library` step from a copy of the whole repository
(`modernSCM(scm: [GitSCMSource ...], libraryPath: 'jenkins-shared-library/')`), repositories made by
`tools/export-collection.sh` (corp.demo at the root, `Jenkinsfile.dev` as `Jenkinsfile`).

| Job | Result | What it shows |
|---|---|---|
| `corp-demo-dev` (`@master`, full collection) | **SUCCESS**, 122 s | untrusted library in the Groovy sandbox: same stages and results as `corp-demo` (JUnit 78 tests, the informational MEDIUM finding), Integration and Molecule on `builder-1`, `git-readonly` credential resolved |
| `corp-demo-dev-tag` (`@v2.1.1`, lite) | **SUCCESS**, 92 s | tag resolved via `gitTagDiscovery()`; units, Integration, Molecule skipped |
| `corp-demo-dev-positional` (`modernSCM([$class: ...], libraryPath: ...)`) | **FAILURE** (expected), 0 s | `Expected named arguments`: with `libraryPath` the SCM must be passed as `scm:` |

Script approval: none pending and none approved after the runs (`ScriptApproval` queried), no
`RejectedAccessException` in the logs.

**2.1.0 (26/10/2026)**: Jenkins set up without any configuration file (init scripts doing the *Manage
Jenkins* steps), plain `ansibleCollectionPipeline()` and overridden parameters.

| Job | Result | What it shows |
|---|---|---|
| `corp-demo` (`@v2`, 2-line Jenkinsfile, full example collection) | **SUCCESS**, 148 s | defaults: static checks, matrix 2.16 / 2.18 / 2.20 sanity + units, Integration and Molecule on the `ansible-builder` agent; Spotter skipped (empty default `spotterEndpoint`), changelog and Publish skipped; rendered pod: `runner` image = default `ciToolsImage`; JUnit 78 tests, 1 informational MEDIUM finding of the security scanner (blocking threshold: HIGH) |
| `corp-demo-lite` (`@v2.1.0`, no `tests/unit`, `tests/integration`, `extensions/molecule`) | **SUCCESS**, 131 s | pinned version resolved; units (×3), Integration and Molecule skipped by `fileExists`; JUnit 71 tests, 0 failures |
| `corp-demo-params` (`spotterEndpoint: ''`, `spotterCredentialsId`/`galaxyCredentialsId` = team IDs, `ciToolsImage: 'localhost/bench/ci-tools-image:override'`, `builderLabel: 'podman-bench'`) | **SUCCESS**, 162 s | Spotter skipped; container stages scheduled on the `podman-bench` label; rendered pod YAML = template with the overridden image (diffed and parsed) |
| `corp-demo-spotter` (lite + `spotterEndpoint: 'https://spotter.invalid/api'`, `spotterCredentialsId: 'bench-team-spotter'`) | **UNSTABLE** (expected), 148 s | Spotter stage runs with the team credential bound to `SPOTTER_TOKEN` and the endpoint passed to `aci`; the unreachable endpoint only makes the build UNSTABLE |
| `corp-demo-typo` (`spoterEndpoint: ...`) | **FAILURE** (expected), 2 s | "unknown parameter(s) [spoterEndpoint]. Allowed: galaxyUrl, ..." before any agent is allocated |

**2.0.0 (23/10/2026)**: `corp-demo` SUCCESS (166 s) and `corp-demo-lite` SUCCESS (115 s), same stages.

Bench caveat: the bench host has no systemd user session, so rootless podman had no delegated cgroup v2
and the systemd test containers could not start (pitfall 13). The bench therefore runs the Podman agent
as root; on the real VM the playbook enables linger for the CI user instead.

## 15. Limits and untested points

* **No OpenShift cluster and no GitLab instance** on the bench:
  * the Jenkins pod is never scheduled on a cluster: on the bench it is replaced by a static agent (the
    bench copy of the library swaps `kubernetes { ... }` for `label 'ansible-runner'`); the rendered pod
    YAML (`libraryResource` + image substitution, in Jenkins) is archived and parsed by the bench script;
  * the component is validated by the official schema and an emulated rendering (`render.py`), without
    real CI Lint or GitLab pipeline. First thing to do: CI Lint of the component + pipeline of the
    component project; `@1` (partial version) and catalog publication are not tested.
* **Jenkins**: the changelog check on a real multibranch PR and the `Publish` stage on a real tag build are
  not tested in Jenkins (they are by `guards.sh` and `run-jobs.sh`).
* **EEs**: introspection tested with **simulated** EEs, not with the `registry.redhat.io` images (no
  authenticated access). The **POC `ee-units`** step is written but **not run**.
* **Certification**: faithful reproduction of versions and options, but the official checker runs sanity
  with `ansible-test-gh-action` in docker. The ignore rule is applied as ansible-lint 26.4.0 defines it;
  the actual tolerance of Red Hat reviewers is unknown.
* **Spotter**: never run against a real private instance (export only).
* GitLab: no venv cache without a persistent volume (first job of a series: about 30 to 60 s of pip from Nexus).

## 16. Roadmap (Red Hat study, P2 and P3 priorities)

| # | Item | Priority | Proposal |
|---|---|---|---|
| 3 | Units and integration **inside the EE image** | P1 (POC) | Validate `ee-units` on site (VM + registry.redhat.io mirror) |
| 5 | galaxy-importer configuration **shared with the Private Automation Hub** | P1/P2 | `share/aci/galaxy-importer.cfg` becomes the source, also deployed on the hub |
| 9 | **Metadata lint**: version ≥ 1.0.0 on tags, `license`, `requirements.txt` without pins or ansible-core, `bindep.txt`, `tests/config.yml`, absolute README links | P2 | new check in `cert_guards.py` |
| 10 | Dependencies resolved **certified/validated → community** (hub then Nexus) | P2 | several Galaxy servers in the generated `ansible.cfg` |
| 11 | **`ee-build`** stage: `ansible-builder build` from `ee-minimal` with the tarball | P2 | VM; proves that `requirements.txt` and `bindep.txt` install |
| 12 | **Smoke test `ansible-navigator run --eei <EE>`** | P2 | VM, after `ee-build` |
| 14 | Publication to the Private Automation Hub **staging**, then approval and signature | P3 | `ACI_GALAXY_PUBLISH_URL` = staging, promotion outside CI |
| 15 | **Nightly** run on the rolling EE tag and the next core series | P3 | scheduled job |
| — | Simplify the GitLab component like the Jenkins library (fixed jobs, site settings as group CI/CD variables) | — | major release of the component |
| — | Move to **AAP 2.7** by default (2.18 + 2.20) | — | major release (changed default) |

## 17. Pitfalls found (✔ = hit during the tests)

1. ✔ **Work tree inside the git repository**: if `ansible_collections/<ns>/<name>` is created under the
   repository, ansible-test walks up to the parent `.git`, lists files through git and prints
   *"WARNING: All targets skipped"* **while exiting successfully**. `aci` therefore works in
   `$TMPDIR/aci-<uid>/<repo>` (`ACI_WORK`).
2. ✔ **`--network host` on the job container**: ansible-test reuses that network for its containers and
   crashes (*"Missing IP address for container"*).
3. ✔ **`ssh-keygen` missing** on the runner: *"Required program "ssh-keygen" not found"*.
4. ✔ **`ansible-test-utility-container`** not mirrored: every `--docker` run needs it.
5. Image **tags change with ansible-core patch releases**. `aci prime-images` reads them dynamically. To pin,
   pin the ansible-core patch version.
6. **antsibull-nox / tox-ansible / ansible-test-gh-action** download ansible-core from GitHub. Do not use
   them as is when airgapped.
7. **ansible-lint without `--offline`** tries to install `requirements.yml` and refresh its schemas.
8. **`--remote`** (Red Hat Core CI VMs) does not exist on-prem. Use distribution containers or internal VMs
   (`ansible-test integration --target ssh:<user>@<host>[:<port>]`).
9. **Integration targets** that run `apt`/`dnf`/`pip`: `--pypi-endpoint` covers pip; for `apt`/`dnf`,
   configurable `setup_*` roles (Nexus mirrors) or derived images (not shipped).
10. **Docker socket = root on the agent**: ansible-test starts a `--privileged --pid host` container.
11. ✔ **`build_ignore`** in `galaxy.yml`: exclude `Jenkinsfile`, `.gitlab-ci.yml`. Until 2.3.0 a missing
    `reports`/`dist` entry put the SARIF and certification reports and the previous tarball in the published
    tarball (and galaxy-importer's ansible-lint scanned them); 2.4.0 writes them outside `src/`.
12. **galaxy-importer** writes `importer_result.json` to the current directory. `aci importer` runs it in
    `reports/galaxy-importer/`.
13. ✔ **Rootless podman without cgroup delegation**: the ansible-test (systemd) containers die at start
    (*"Failed to create /init.scope control group: Permission denied"*, then *"can only create exec sessions
    on running containers"*). Fixed by giving the user a delegated cgroup v2 subtree (`loginctl enable-linger`).
    Hit again on the 2.0.0 bench, whose host has no systemd user session.
14. ✔ **`ansible-test --venv` when airgapped** downloads `get-pip-<v>.py` from `ci-files.testing.ansible.com`
    and ignores `PIP_INDEX_URL` → `get_pip_offline.py` installed by `aci` + `/etc/pip.conf`.
15. ✔ **ansible-security-scanner has no exclude option**: `aci security-scan` scans a clean copy.
16. ✔ **galaxy-importer** requires a `README.md` per role; **antsibull-docs** requires `description` in
    `meta/argument_specs.yml`.
17. ✔ **Spotter CLI 6.6.0**: `--ansible-version` only accepts 2.0 → 2.20; exit code 1 as soon as a result
    remains after `--display-level` filtering (default: `error`).
18. ✔ **ansible-security-scanner false positive** (`linux_cap_bpf_granted_to_container_or_service` triggered by
    `podman_container` + `systemd`): targeted suppression `# nosec: <rule_id> reason="..."`.
19. **UBI 9**: system `python3` = 3.9; AppStream has 3.11, 3.12 and 3.14 but **not 3.13** (the ci-tools-image
    now takes its Python from `corp/hub/python3:<X.Y>`, the VM from AppStream); no ShellCheck outside EPEL; CA path = `/etc/pki/tls/certs/ca-bundle.crt`.
20. ✔ **GitLab `cache:` inside the project**: lint, yamllint and sanity scan the cached venvs. The component
    does not use `cache:`; persistent volume on `~/.cache/ansible-ci` instead.
21. ✔ **GitLab `array` input interpolated alone in `variables:`** stays a YAML array, refused by the schema.
    The component writes `"series $[[ inputs.ansible-core-versions ]]"` and `aci` extracts the series.
22. ✔ **Checkout owned by another UID** (GitLab pod, container): `git` refuses the repository (*dubious
    ownership*). `aci changelog-check` passes `-c safe.directory=<checkout>`.
23. ✔ **ansible-core 2.16**: sanity requires the `from __future__ import ...` + `__metaclass__ = type` header.
24. ✔ **Parallel ansible-test venvs on the same agent**: "No such file ... pip-25.2.dist-info". `aci` gives
    each ansible-core series its own `HOME`, protected by `flock`.
25. ✔ **Jenkins `matrix`**: literal axis values only (*"Expected string literal but got ${cores}"*). Fine for
    the fixed 2.0.0 matrix; it is why 1.x generated `parallel` branches.

## 18. Security and SBOM
* Ansible scanners: §19 (ansible-security-scanner locally, blocking from HIGH; Steampunk Spotter on a
  private instance).
* ansible-lint `production` profile and certification guards (§5). `CHECK_REQUIRED_TAGS`.
* **Global** Jenkins library: only CI maintainers write to it. Secrets only through credentials or masked
  variables, never as parameters or inputs.
* Nexus Firewall / IQ on the proxy repositories. Pinned versions (`share/aci/constraints.txt`,
  `certification.env`), dated images.
* To plan: SBOM of the artifact (`syft dist/*.tar.gz`) and `pip-audit` (non-blocking); collection signing
  with the Private Automation Hub.

## 19. Security scanners

### 19.1 "ansible-security-scanner": identification
* The name matches the PyPI package [**ansible-security-scanner**](https://pypi.org/project/ansible-security-scanner/)
  (0.1.41, 25/08/2026, Apache-2.0, repository [cpeoples/ansible-security-scanner](https://github.com/cpeoples/ansible-security-scanner)):
  static analysis of YAML (playbooks, roles, collections), **1,165 patterns**, SARIF / JUnit / GitLab SAST /
  CycloneDX output. Chosen as the most likely candidate.
* **Uncertainty**: young project (created 29/04/2026), **a single maintainer**, 0.1.x versions. Other tools
  possibly behind this generic name: [KICS](https://github.com/Checkmarx/kics), [ansible-risk-insight](https://pypi.org/project/ansible-risk-insight/),
  the ansible-lint security rules. To confirm with the security team.
* **Airgap verdict: ✅ fully local.** Only `--github-comment` / `--gitlab-comment` make network calls.
* Integration (`aci security-scan`): clean copy of the collection, SARIF + GitLab SAST with `--exit-zero`,
  then a **blocking** JUnit pass (non-zero on HIGH/CRITICAL). Plan a calibration phase and an allowlist (`--allowlist`).

### 19.2 Steampunk Spotter: private instance
* CLI [**steampunk-spotter**](https://pypi.org/project/steampunk-spotter/) 6.6.0, installed from the Nexus
  PyPI proxy (`share/aci/requirements-security.txt`, pinned).
* **The analysis happens server side**: the CLI extracts tasks and metadata and sends them to the API.
  Without a server, only `--export-payload` works.
* **Airgap verdict: ✅ feasible with the on-prem Spotter instance** ([on-prem install](https://spotter.steampunk.si/docs/onprem/)).
  ❌ Impossible with the SaaS.

| Need | Option / variable |
|---|---|
| Private endpoint | `--endpoint` or **`SPOTTER_ENDPOINT`** (e.g. `https://spotter.corp.local/api`); otherwise `~/.config/steampunk-spotter/spotter.json`, then the SaaS |
| Token | `--token` or **`SPOTTER_TOKEN`** (alias `SPOTTER_API_TOKEN`) |
| Internal CA | `--cacert` or **`SPOTTER_CACERT`** (default: system bundle); never `-k`/`SPOTTER_INSECURE` |
| Target version | `--ansible-version` limited to 2.0 → 2.20 in CLI 6.6.0 → `ACI_SPOTTER_ANSIBLE_VERSION` = 2.20 |
| Reports | `--junit-xml`, `--sarif`; `--display-level error`; exit code 1 if results remain |

* **Network flows**: CI agent → private Spotter instance, **HTTPS 443 only** (checked: with a private
  endpoint the CLI only calls that host).
* Pipelines: Jenkins parameters `spotterEndpoint` + `spotterCredentialsId` (default credential `spotter-api-token`; findings make the build
  UNSTABLE); GitLab masked variable `SPOTTER_TOKEN`, `spotter-allow-failure: true` by default.
* Confidentiality: the payload contains the tasks **and their values** (`--exclude-values`,
  `--exclude-metadata`, `--exclude-environment` reduce it; detected secrets are masked).

## 20. FAQ

### 20.1 Why is Molecule not the main engine? Is it abandoned?
**No, Molecule is neither abandoned nor deprecated.**
* [ansible/molecule](https://github.com/ansible/molecule/releases) is very active (v26.10.0 on 12/10/2026,
  about one release a month) and is part of [ansible-dev-tools](https://pypi.org/project/ansible-dev-tools/).
* Since **Molecule 25.9.0**, the **"ansible-native"** configuration is the recommended way: no *driver*,
  `create.yml`/`destroy.yml` playbooks written with normal collections, native Ansible inventory, scenario
  discovery in `extensions/molecule/`, `shared_state`. The drivers live in
  [molecule-plugins](https://pypi.org/project/molecule-plugins/) ("pre ansible-native").
* **ansible-test and Molecule do not test the same thing**:

| | ansible-test | Molecule |
|---|---|---|
| Target | plugins/modules of a collection | roles, playbooks, multi-node scenarios |
| Tests | sanity (required by Galaxy / Automation Hub / certification), units, integration targets | converge → **idempotence** → verify on real OSes |
| Environment | controlled official images (Python matrix) | whatever you create (systemd containers, VMs, cloud, devices) |

* **Real usage** (ANALYSIS §1): **4 of the 23 collections studied**; none replaces ansible-test with Molecule.
* **Recommendation**: ansible-test stays mandatory; **Molecule runs automatically when the collection has
  `extensions/molecule/`**, on the `ansible-builder` VM with rootless podman (scenarios like
  `example-collection/corp.demo/extensions/molecule`, targets reusing the mirrored ansible-test
  distribution images).

### 20.2 Why bash + Groovy/YAML, and why a fixed Jenkins pipeline?
* The teams know Jenkins (declarative and scripted Groovy) and GitLab CI. Central libraries (Shared Library
  and component) are the **native** reuse mechanism of each tool.
* The business logic exists **once**, in bash (`aci`), testable with shellcheck and smoke tests. Only a few
  small Python helpers are called.
* A fixed Jenkins pipeline (2.x) keeps only ten site parameters with defaults (Nexus, Spotter, image, label,
  credential IDs): nothing behavioural to document per team, the same stages everywhere.
* An earlier prototype used nox (one `noxfile.py` per repository); it was dropped because every fix had to
  be copied into N repositories and the teams do not know nox. It is in the git history (tag `v3-nox`).

### 20.3 What do the preloaded ansible-test images contain?
They are **chosen by ansible-test**, not by us: `ansible_test/_data/completion/docker.txt` maps aliases to
images, with tags per ansible-core version. `aci prime-images` reads this file in the venv of the series.

| Family | Content | Used by | amd64 size (compressed; uncompressed) |
|---|---|---|---|
| `base-test-container` | Ubuntu, **all target Python versions** of the series, PowerShell 7.6, systemd, sshd, build tools | base of the next two; alias `base` | `v2.21-4`: 462 MB |
| `default-test-container` | base + **pre-installed sanity/units requirements** per Python version | `--docker default` for a **collection** | `v2.21-4`: 565 MB; **1.55 GB** |
| `ansible-core-test-container` | same, tuned to test ansible-core itself | `context=ansible-core` (not used here) | — |
| `ubuntu-test-container`, `fedora-test-container`, `alpine-test-container` | one distribution, **one** Python version, systemd (except alpine) | `integration --docker ubuntu2404 / fedora40 / alpine320...`, Molecule targets | Ubuntu 24.04: 242 MB; 666 MB — Fedora 43: 252 MB; 653 MB — Alpine 3.23: 158 MB |
| `ansible-test-utility-container` | probe utilities (audit, cgroup) | **every** `--docker` run | 4 MB; 9 MB |
| `http-test-container` / `pypi-test-container` / `acme-test-container` | test HTTP server, PyPI proxy, ACME | `needs/httptester` targets, `--pypi-proxy`, ACME cloud plugin | 33 MB / 33 MB / — |

Tags per ansible-core version (read on 20-21/10/2026 from `docker.txt` and `docker_util.py`):

| ansible-core | default / base | Ubuntu / Fedora / Alpine | utility |
|---|---|---|---|
| 2.16 | `default-test-container:8.12.0` / `base:5.10.0` | `ubuntu2204-test-container:6.3.0`, `alpine3-test-container:6.3.0` (no Fedora, no Ubuntu 24.04) | 2.0.0 |
| 2.18 | `default-test-container:10.9.0` / `base:7.7.0` | `ubuntu2204/2404-test-container:8.1.0`, `fedora40-...:8.1.0`, `alpine320-...:8.1.0` | 3.1.0 |
| 2.20 | `v2.20-4` / `v2.20-2` (3.9 → 3.14) | `ubuntu-test-container:24.04-v2.20-1`, `fedora-...:42-v2.20-1`, `alpine-...:3.22-v2.20-1` | 3.4.0 |
| 2.21 | `v2.21-4` / `v2.21-4` (3.9 → 3.14) | `24.04-v2.21-2`, `fedora 43-v2.21-2`, `alpine 3.23-v2.21-2` | 3.5.0 |
| 2.22 | `v2.22-8` / `v2.22-8` (3.9 → 3.15) | `24.04-v2.22-4`, `26.04-v2.22-4`, `fedora 44-v2.22-4`, `alpine 3.24-v2.22-4` | — |

Indicative Nexus budget for 3 series: about 2.5 GB compressed (3 × default + 2 distributions + utilities).
Sources: [base-test-container](https://github.com/ansible/base-test-container),
[default-test-container](https://github.com/ansible/default-test-container), `quay.io/v2` API.
