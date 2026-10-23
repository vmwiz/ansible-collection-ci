# User guide: CI for an Ansible collection (Jenkins or GitLab)

This guide is for the teams that develop collections. For the technical details, see
[PROPOSITION.md](PROPOSITION.md).

## 1. Before you start (once per collection)

* `meta/runtime.yml`: `requires_ansible: '>=2.16.0'`. AAP 2.6 supports ansible-core 2.16 and 2.18. A lower
  bound of 2.19 is refused, because 2.19 was only a technology preview.
* `galaxy.yml`:
  * `tags:` must contain at least one tag (required by the certification);
  * `build_ignore: [Jenkinsfile, .gitlab-ci.yml, reports, dist]`.
* `.gitignore`: `reports/`, `dist/`, `tests/output/`.
* Python modules, plugins and tests: add the header required by the 2.16 sanity and by the certification:
  ```python
  from __future__ import (absolute_import, division, print_function)
  __metaclass__ = type
  ```
* `.ansible-lint`: `profile: production` (or no profile). Do not put any mandatory rule in `skip_list`
  and do not exclude `plugins/` or `roles/`.
* `changelogs/config.yaml` (antsibull-changelog). Every PR/MR that changes the collection adds a
  fragment `changelogs/fragments/<num>-<topic>.yml`:
  ```yaml
  minor_changes:
    - hello - add the ``greeting`` option.
  ```
  Exemption: put the label or the word **`skip-changelog`** in the PR/MR title.
* `tests/sanity/ignore-2.16.txt` (and following): only the entries allowed by the certification are
  accepted. An exceptional derogation is tracked with a `# aci-derogation: <reason>` comment on the line.

## 2. Jenkins

Create a **Multibranch Pipeline** job on the repository. It is needed for pull requests (changelog check)
and for tag builds (publication).

### 2.1 Jenkinsfile

```groovy
@Library('ansible-ci@v2') _
ansibleCollectionPipeline()
```

That is the whole file, and it is the same for every collection: the pipeline is fixed and takes no
parameters. It runs:

| Stage | What | Where |
|---|---|---|
| Static checks (parallel) | Lint (yamllint, antsibull-changelog lint, ansible-lint) + docs, Red Hat certification checks, build + galaxy-importer, ansible-security-scanner, Spotter (when the admins configured it), changelog fragment (pull requests only) | OpenShift pod |
| ansible-test | sanity + units on ansible-core **2.16, 2.18 and 2.20**, Python 3.12 (units only if `tests/unit/` exists) | OpenShift pod |
| Container tests (parallel) | `ansible-test integration --docker` (if `tests/integration/targets/` exists), Molecule (if `extensions/molecule/` exists) | ansible-builder VM (Podman) |
| Publish | publication to Nexus, on a tag equal to the `galaxy.yml` version | OpenShift pod |

2.16 and 2.18 are the ansible-core versions of AAP 2.6; 2.20 (AAP 2.7) is also part of the Red Hat
certification sanity, so it is tested too.

Optional stages are switched on and off by the content of your repository, not by parameters: add
`tests/integration/targets/` or `extensions/molecule/` and the matching stage runs.

To pin a release instead of following the latest 2.x: `@Library('ansible-ci@v2.0.0') _`.

### 2.2 What the Jenkins admins set up (not your job)

Nexus URLs, the Spotter endpoint, the runner image, the agents and the credentials
(`spotter-api-token`, `nexus-galaxy-hosted-token`) are configured once for everybody in
`infra/jenkins/jcasc.yaml`.

## 3. GitLab

### 3.1 Minimal `.gitlab-ci.yml`

```yaml
include:
  - component: $CI_SERVER_FQDN/ci/ansible-collection-ci/ansible-collection@1
```

It runs the same `aci` checks as Jenkins (default matrix 2.16 + 2.18; certification sanity adds 2.20).
MR jobs check the changelog fragment.

### 3.2 Complete `.gitlab-ci.yml`

Unlike the Jenkins library, the GitLab component still takes inputs (see
`gitlab-ci-templates/README.md` for the full list).

```yaml
workflow:            # a single pipeline per MR
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS
      when: never
    - if: $CI_COMMIT_BRANCH || $CI_COMMIT_TAG || $CI_PIPELINE_SOURCE == "schedule"

include:
  - component: $CI_SERVER_FQDN/ci/ansible-collection-ci/ansible-collection@1.1.0
    inputs:
      runner-image: nexus.corp.local:8443/ci/ansible-collection-runner:2026.10
      ansible-core-versions: ['2.16', '2.18']       # quoted
      ansible-core-optional: '2.20'                 # AAP 2.7, non-blocking
      # target-ees: >-                              # matrix checked against the EEs (same series required)
      #   hub.corp.local/ansible-automation-platform-26/ee-minimal-rhel9:latest
      #   hub.corp.local/ansible-automation-platform/ee-minimal-rhel9:2.18
      test-mode: auto
      integration: true
      integration-images: [default, ubuntu2404]
      molecule: true
      spotter: true
      spotter-endpoint: https://spotter.corp.local/api
      spotter-allow-failure: true
      security-fail-on: high
```

* **Masked CI/CD variables** (Settings > CI/CD > Variables):
  * `ACI_GALAXY_TOKEN`, **protected**, with protected tags `*.*.*`;
  * `SPOTTER_TOKEN`.
* **Never** put a secret in `inputs`.
* Your own jobs go next to the `include` as usual. The component jobs start with `aci-`.

## 4. What you will see

| Stage | Fails if... | What to do |
|---|---|---|
| Changelog | a PR/MR changes the collection without a fragment | add `changelogs/fragments/*.yml`, or the `skip-changelog` label |
| Certification | forbidden sanity ignore, non-compliant `.ansible-lint`, unsupported `requires_ansible`, galaxy-importer or ansible-lint production failure | see `reports/certification/guards.txt`, `galaxy-importer.log` |
| Lint / Docs / Build | yamllint, ansible-lint, antsibull-docs, galaxy-importer errors | reports in `reports/` (build artifacts) |
| Security scan | HIGH or CRITICAL finding | fix it, or a justified `# nosec: <rule> reason="..."` |
| Spotter | Spotter findings | the build becomes UNSTABLE (not failed); see `reports/spotter/` |
| Sanity / units / integration | ansible-test | JUnit in the *Tests* tab |
| Publish | the tag differs from the `galaxy.yml` version | tag `1.2.3` (or `v1.2.3`) = `version: 1.2.3` |

Locally, in the runner image: `ACI_CORE=2.18 /opt/ansible-ci/bin/aci sanity` (or `lint`,
`certification`...).

## 5. Versions

* `@v2` (Jenkins) and `@1` (GitLab): you automatically get fixes and compatible changes.
* A new major version (for example AAP 2.7 as the default platform) will be announced and must be
  adopted explicitly.
* History: `jenkins-shared-library/CHANGELOG.md` and `gitlab-ci-templates/CHANGELOG.md`.
