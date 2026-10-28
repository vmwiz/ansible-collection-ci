# GitLab CI/CD component `ansible-collection` (ansible-ci 1.x)

Test and validation pipeline for an Ansible collection on GitLab, airgapped behind Nexus and aligned
with AAP 2.6. It runs **the same `aci` scripts** (`../ci-scripts`, baked into the ci-tools-image) as the
Jenkins shared library (`../jenkins-shared-library`). Note: the Jenkins library is a single fixed
pipeline without parameters, while this component still exposes the inputs listed below.

## Usage

```yaml
# .gitlab-ci.yml of the collection: that's all
include:
  - component: $CI_SERVER_FQDN/ci/ansible-collection-ci/ansible-collection@1
```

`../USER-GUIDE.md` also contains the complete example (`examples/complete.gitlab-ci.yml`).

* **Version**: `@1` = latest published 1.x (recommended); `@1.2.0` = pinned version; avoid `@~latest`.
  Tags follow `x.y.z` (SemVer). The compatibility rule is described in `CHANGELOG.md`.
* **Requirements**: GitLab ≥ 17.0 (components and `spec:inputs` GA). No newer feature is used (no
  `$[[ component.version ]]`, which needs 18.7, and no `split` function).
* **Without the catalog** (unpublished project, other instance): include the same file with
  `include:project`, which also accepts `inputs:`. There is only one template to maintain.
  ```yaml
  include:
    - project: ci/ansible-collection-ci
      ref: 1.2.0
      file: /templates/ansible-collection/template.yml
      inputs: {ansible-core-optional: '2.20'}
  ```

## Expected runners

| Tag (input) | Executor | Role |
|---|---|---|
| `ansible-runner` (`runner-tags`) | Kubernetes/OpenShift, `restricted-v2` pods, image `runner-image` | Static analysis, sanity/units in `venv` mode, build, certification, publication |
| `ansible-builder` (`builder-tags`) | **shell** runner on the VM with podman | `aci-ee-introspect`, sanity/units in `docker` mode, integration, molecule, EE POC |

Venvs go to `~/.cache/ansible-ci`. GitLab's `cache:` is **not** used, because it requires a path inside
the project that lint and sanity would then scan (seen on the bench). To speed up the pods, mount a
persistent volume on `/home/ci/.cache/ansible-ci` in the Kubernetes runner configuration
(`[[runners.kubernetes.volumes.pvc]]`). The VM keeps its cache by itself.

## Scripts in the image (`/opt/ansible-ci/bin/aci`): assessment and recommendation

A GitLab component can only ship YAML, so the scripts have to arrive another way.

| Option | Pros | Cons |
|---|---|---|
| **A. Baked into the ci-tools-image** (`/opt/ansible-ci`) and installed on the VM (`infra/ansible-builder-vm`) | No network access in jobs; version pinned by the image tag; same files as Jenkins; tested | Changing the scripts requires a new image |
| B. Job that clones the scripts project (`CI_JOB_TOKEN`) | Scripts decoupled from the image | Project access to allow (job token allowlist); one clone per job; two versions to keep aligned |
| C. Scripts inline in the YAML (`!reference`) | Everything in the component | Duplicated bash, cannot be shellchecked; size limits; drifts from Jenkins |

**Recommendation: A.**
* The component sets `ACI_EXPECTED_VERSION`. `aci` **refuses** an image whose major version differs
  and **reports** a minor version drift.
* Publish the ci-tools-image with **two tags**: the calendar tag (`2026.10.1`, `YYYY.MM[.N]`) and the scripts version tag
  (`aci-1.2.0`).
* For every component release, update the default `runner-image` in the same commit.
  `tests/validate.sh` checks consistency with `ci-scripts/VERSION`.

## Created jobs

| Job | Stage | When |
|---|---|---|
| `aci-ee-introspect` | `.pre` | `target-ees` not empty. Fails immediately on incompatibility (requires_ansible, Python range, series ≠ `ansible-core-versions`) |
| `aci-changelog` | static | MR pipelines. Exemption with the `skip-changelog` label or title word |
| `aci-lint`, `aci-docs`, `aci-security`, `aci-spotter` | static | According to the inputs. `aci-spotter` is `allow_failure` by default |
| `aci-sanity-venv` / `aci-units-venv` `[ACI_CORE]` | test | Branches other than the default branch (or `test-mode: venv`) |
| `aci-sanity-docker` / `aci-units-docker` `[ACI_CORE]` | test | Tags, scheduled pipelines, default branch (or `test-mode: docker`) |
| `aci-optional-cores` | test | `ansible-core-optional`, non-blocking |
| `aci-certification-sanity` | test | Python 3.12 sanity on stable-2.16/2.18/2.20 (filtered by requires_ansible) not already covered with 3.12 |
| `aci-integration` `[image]`, `aci-molecule` | test | `integration` / `molecule` |
| `aci-ee-units` | test | **Untested** POC (`ee-tests` + `target-ees`), non-blocking |
| `aci-build` (+ importer) | test | `build`. After the container tests; `dist/` artifact = the tarball certified and published |
| `aci-certification` | test | `certification`. Guards + galaxy-importer 0.4.39 on the `aci-build` tarball + ansible-lint 26.4.0 `--profile=production`. With `build: false` it builds the tarball itself (nothing is published then) |
| `aci-publish` | deploy | Tag, inputs `publish` and `build`. Waits for all previous stages to succeed; publishes the `dist/` artifact of `aci-build` (no rebuild) |

Order (same as the Jenkins library), each block only if the previous one passed: 1. static analysis
(`aci-lint`, `aci-docs`, `aci-changelog`, `aci-security`, `aci-spotter`) → 2. ansible-test (sanity, units,
optional series, certification sanity, EE units) → 3. container tests (`aci-integration`, `aci-molecule`) →
4. `aci-build` → `aci-certification` → 5. `aci-publish`. The chain uses `needs` with `optional: true` (a job
disabled by its input is not waited for) and `artifacts: false` (ordering only); a job with
`allow_failure` (Spotter, optional or pre-release series) does not block the next blocks. The test jobs
also wait for the EE introspection, when it exists. A failing series listed in `ansible-core-prerelease` exits with code 3
(`allow_failure: exit_codes: [3]`).

## Inputs (46)

| Input | Type | Default | Description |
|---|---|---|---|
| `stage-static` | string | `'build'` | Stage of the static analysis of the source (lint, docs, changelog, security, Spotter). |
| `stage-test` | string | `'test'` | Stage of ansible-test (sanity, units), container tests (integration, molecule), then build + certification. |
| `stage-publish` | string | `'deploy'` | Publication stage (on tags). |
| `runner-image` | string | `'nexus.corp.local:8443/corp/ci-tools-image:2026.10.1'` | ci-tools-image (contains /opt/ansible-ci/bin/aci and Python 3.12). Its tag pins the scripts. |
| `runner-tags` | array | `['ansible-runner']` | Tags of the Kubernetes/OpenShift runner (restricted-v2 pods, no container engine). |
| `builder-tags` | array | `['ansible-builder']` | Tags of the shell runner on the ansible-builder VM (podman) - docker mode, integration, molecule, EE. |
| `aci-path` | string | `'/opt/ansible-ci/bin/aci'` | Path of the aci scripts in the ci-tools-image and on the ansible-builder VM. |
| `ansible-core-versions` | array | `['2.16', '2.18']` | Tested series, quoted. With target-ees, must list exactly the series of the EEs. |
| `ansible-core-optional` | string | `''` | Extra non-blocking series, space separated (e.g. "2.20" for AAP 2.7). |
| `ansible-core-prerelease` | string | `''` | Series of ansible-core-versions that are pre-releases (rc), non-blocking failure (code 3). |
| `ansible-core-default` | string | `''` | Series of the non-matrix jobs (default - last series that is not a pre-release). |
| `target-ees` | string | `''` | Target EE images, space separated; introspection (fail early) and exact version per series. |
| `lint` | boolean | `true` | yamllint + ansible-lint + antsibull-changelog lint |
| `docs` | boolean | `true` | antsibull-docs lint-collection-docs |
| `build` | boolean | `true` | ansible-galaxy collection build |
| `galaxy-importer` | boolean | `true` | galaxy-importer on the tarball (needs build) |
| `security-scan` | boolean | `true` | ansible-security-scanner |
| `certification` | boolean | `true` | Red Hat certification checks (partner-certification-checker 6.0.0) |
| `certification-sanity` | boolean | `true` | py3.12 sanity on stable-2.16/2.18/2.20 not covered by the matrix |
| `changelog-check` | boolean | `true` | Changelog fragment required on MRs |
| `changelog-skip-token` | string | `'skip-changelog'` | MR label or title word that exempts from the fragment |
| `sanity` | boolean | `true` |  |
| `units` | boolean | `true` |  |
| `integration` | boolean | `false` | ansible-test integration --docker (ansible-builder VM) |
| `molecule` | boolean | `false` | molecule test (ansible-builder VM) |
| `spotter` | boolean | `false` | Steampunk Spotter (private instance, spotter-endpoint required) |
| `ee-tests` | boolean | `false` | Untested POC - units inside the target-ees EEs |
| `publish` | boolean | `true` | Publication to Nexus on tags (ACI_GALAXY_TOKEN) |
| `test-mode` | string | `'auto'` | auto = docker on tags, schedules and the default branch; venv otherwise. Values: auto, venv, docker. |
| `sanity-args` | string | `''` | Extra ansible-test sanity arguments |
| `units-args` | string | `''` | Extra ansible-test units arguments |
| `integration-args` | string | `''` | Extra ansible-test integration arguments |
| `integration-images` | array | `['default']` | ansible-test --docker images for integration (one job per image). |
| `docker-network` | string | `''` | ansible-test --docker-network |
| `coverage` | boolean | `false` |  |
| `molecule-images` | string | `'ubuntu2404 fedora40'` | Molecule images, space separated |
| `pip-index-url` | string | `''` | Empty = /etc/pip.conf of the image (the only one read by ansible-test --venv) |
| `pypi-endpoint` | string | `'https://nexus.corp.local/repository/pypi-group/simple'` | PyPI index of the ansible-test containers |
| `image-mirror` | string | `'nexus.corp.local:8444'` | Mirror of the quay.io/ansible images |
| `galaxy-server-url` | string | `'https://nexus.corp.local/repository/ansible-group/'` |  |
| `galaxy-publish-url` | string | `'https://nexus.corp.local/repository/ansible-hosted/'` |  |
| `security-fail-on` | string | `'high'` | Values: high, critical, none. |
| `spotter-endpoint` | string | `''` | API URL of the private Spotter instance |
| `spotter-allow-failure` | boolean | `true` |  |
| `spotter-ansible-version` | string | `'2.20'` |  |
| `spotter-display-level` | string | `'error'` | Values: hint, warning, error. |

**Secrets**: never pass them as inputs (inputs are visible in clear text in the configuration).
Define them as **masked** CI/CD variables:
* `ACI_GALAXY_TOKEN`: publication, **protected** variable (protected tags `*.*.*`);
* `SPOTTER_TOKEN`: Spotter.

**Pitfalls**:
* ansible-core series must be **quoted** (`'2.20'`). Unquoted, YAML reads `2.20` as the number 2.2,
  and `aci` then refuses the "unknown" series.
* With `target-ees`, `ansible-core-versions` must list exactly the series of the EEs. The GitLab matrix
  is static; the introspection job prints the value to use.

## Tests (without a GitLab instance)

* `tests/validate.sh [schema.json]`:
  * input rendering (`tests/render.py` emulates types, options, regex, whole or partial interpolation,
    `!reference` and `extends`);
  * validation of the rendered file and of the `spec` header against the **official GitLab schema**
    (`tests/gitlab-ci-schema.json`, copy of GitLab 19.6.0-pre `ci.json`);
  * check that invalid inputs are refused;
  * simulation of the jobs created in each context (branch, default branch, MR, tag);
  * validation of the examples.
* `../tests/gitlab-jobs/run-jobs.sh INPUTS CONTEXT "jobs..."` (bench, not shipped): **really** runs the
  scripts of the rendered jobs. Each job runs in a fresh clone, in the ci-tools-image, airgapped, with an
  arbitrary UID; the introspection runs on the host with podman.
* `render.py` is only an **emulation**. The final validation happens in GitLab: CI Lint
  (`/-/ci/lint`, or the `POST /projects/:id/ci/lint` API) and the component project pipeline
  (`.gitlab-ci.yml`), which includes the component `@$CI_COMMIT_SHA` on `tests/collection` (copy of
  `example-collection/corp.demo` kept in sync by `tools/sync.sh`).
