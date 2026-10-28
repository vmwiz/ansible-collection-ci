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

That is the whole file for most collections: the stages are the same for everybody. It runs:

| # | Stage | What | Where |
|---|---|---|---|
| 1 | Static analysis (parallel) | Lint (yamllint, antsibull-changelog lint, ansible-lint), Docs (antsibull-docs), changelog fragment (pull requests only), ansible-security-scanner, Spotter (when `spotterEndpoint` is set; findings → UNSTABLE) | OpenShift pod |
| 2 | ansible-test | sanity + units on ansible-core **2.16, 2.18 and 2.20**, Python 3.12 (units only if `tests/unit/` exists) | OpenShift pod |
| 3 | Container tests (parallel) | `ansible-test integration --docker` (if `tests/integration/targets/` exists), Molecule (if `extensions/molecule/` exists) | ansible-builder VM (Podman) |
| 4 | Package & certify | `ansible-galaxy collection build` **once**, tarball archived (fingerprinted), then galaxy-importer and the Red Hat certification checks on that tarball | OpenShift pod |
| 5 | Publish | publication to Nexus of **the certified tarball** (no rebuild), on a tag equal to the `galaxy.yml` version | OpenShift pod |

Each stage runs only if the previous one passed: a collection is built and certified only once all its
tests are green, and what is published is exactly what was certified.

2.16 and 2.18 are the ansible-core versions of AAP 2.6; 2.20 (AAP 2.7) is also part of the Red Hat
certification sanity, so it is tested too.

Optional stages are switched on and off by the content of your repository: add
`tests/integration/targets/` or `extensions/molecule/` and the matching stage runs.

To pin a release instead of following the latest 2.x: `@Library('ansible-ci@v2.1.1') _`.

### 2.2 Overriding site settings (rarely needed)

The site defaults (Nexus URLs, Spotter, ci-tools-image, agent label, credential IDs) are set by the CI
maintainers. You can override any of them, for example to use your team's private Spotter instance:

```groovy
@Library('ansible-ci@v2') _
ansibleCollectionPipeline(spotterEndpoint: 'https://spotter.corp.local/api', spotterCredentialsId: 'my-team-spotter')
```

| Parameter | Default | Purpose |
|---|---|---|
| `galaxyUrl` | `https://nexus.corp.local/repository/ansible-group/` | Galaxy group for collection dependencies |
| `galaxyPublishUrl` | `https://nexus.corp.local/repository/ansible-hosted/` | Galaxy repository the `Publish` stage pushes to |
| `pypiEndpoint` | `https://nexus.corp.local/repository/pypi-group/simple` | PyPI index used inside the ansible-test containers |
| `imageMirror` | `nexus.corp.local:8444` | Docker proxy of quay.io (ansible-test and Molecule images) |
| `spotterEndpoint` | empty | Private Spotter API; empty = Spotter stage skipped |
| `spotterCacert` | `/etc/pki/tls/certs/ca-bundle.crt` | CA bundle for the Spotter API |
| `ciToolsImage` | `nexus.corp.local:8443/corp/ci-tools-image:2026.10.1` | Image the pod stages run in (it pins the `aci` version) |
| `builderLabel` | `ansible-builder` | Label of the Podman agents (Integration, Molecule) |
| `spotterCredentialsId` | `spotter-api-token` | ID of the Jenkins *Secret text* credential with the Spotter token |
| `galaxyCredentialsId` | `nexus-galaxy-hosted-token` | ID of the Jenkins *Secret text* credential allowed to publish |

Credentials are passed by **ID**: ask a Jenkins admin (or a folder admin) to create a *Secret text*
credential and use its ID; never put a secret in the Jenkinsfile. A misspelt parameter name stops the build
immediately with the list of valid names.

### 2.3 What the Jenkins admins set up (not your job)

The global library `ansible-ci`, the default credentials, the Kubernetes cloud and the `ansible-builder`
agents: see `infra/jenkins/README.md`.

### 2.4 Testing the library without registering it

To try a library branch, tag or commit (or the library in a Jenkins where it is not declared in
*Global Pipeline Libraries*), load it from its git repository with the `library` step instead of `@Library`.
`example-collection/corp.demo/Jenkinsfile.dev` does exactly that:

```groovy
library identifier: 'ansible-ci@master',
        retriever: modernSCM(
            scm: [$class: 'GitSCMSource',
                  remote: 'https://gitlab.corp.local/ci/ansible-collection-ci.git',
                  credentialsId: 'git-readonly',
                  traits: [gitBranchDiscovery(), gitTagDiscovery()]],
            libraryPath: 'jenkins-shared-library/')

ansibleCollectionPipeline()
```

* **Version**: the part after `@`: a branch (`ansible-ci@master`, `ansible-ci@my-fix`), a tag
  (`ansible-ci@v2.1.1`) or a full commit SHA.
* **`libraryPath`**: the library is the `jenkins-shared-library/` sub-directory of this repository.
  When `modernSCM` gets more than one argument, the SCM must be passed as `scm:`
  (`modernSCM([$class: ...], libraryPath: ...)` is rejected).
* **`credentialsId`**: ID of a Jenkins credential with read access to the library repository (no secret in
  the Jenkinsfile).
* **Same commit as the Jenkinsfile**: `retriever: legacySCM(scm: scm, libraryPath: 'jenkins-shared-library/')`
  loads the library from the commit being built. Only useful in a repository that holds both the library
  and, at its root, a collection.
* **Sandbox**: a library loaded this way is *untrusted* and runs in the Groovy sandbox (the global library is
  trusted). `ansibleCollectionPipeline` only uses whitelisted calls: on the Jenkins 2.580.1 bench it ran
  with no script approval. If a future change needs one, the build fails with `Scripts not permitted to use
  ...` and an admin approves it in *Manage Jenkins > In-process Script Approval*.

**The collection must be at the root of the job repository.** To get such a repository from this one:

```bash
tools/export-collection.sh /tmp/corp-demo-test https://gitlab.corp.local/ci/ansible-collection-ci.git my-fix
cd /tmp/corp-demo-test        # corp.demo at the root, Jenkinsfile.dev renamed Jenkinsfile, library @my-fix
git remote add origin https://gitlab.corp.local/sandbox/corp-demo-test.git && git push -u origin main
```

Then create a Pipeline (or Multibranch Pipeline) job on that repository. Your own collection works the same:
copy `Jenkinsfile.dev` into it as `Jenkinsfile`, on a test branch.

**Quick edits without a commit**: open a finished build, *Replay*: the Jenkinsfile and the library script
(`ansibleCollectionPipeline`) can be edited there and the build re-run. Nothing is saved: commit the change
to the library branch once it works.

## 3. GitLab

### 3.1 Minimal `.gitlab-ci.yml`

```yaml
include:
  - component: $CI_SERVER_FQDN/ci/ansible-collection-ci/ansible-collection@1
```

It runs the same `aci` checks as Jenkins, in the same order (static analysis → ansible-test → container
tests → build + certification → publish of the certified tarball; default matrix 2.16 + 2.18, certification
sanity adds 2.20).
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
  - component: $CI_SERVER_FQDN/ci/ansible-collection-ci/ansible-collection@1.2.0
    inputs:
      runner-image: nexus.corp.local:8443/corp/ci-tools-image:2026.10.1
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
| Certification (in Package & certify) | forbidden sanity ignore, non-compliant `.ansible-lint`, unsupported `requires_ansible`, galaxy-importer or ansible-lint production failure | see `reports/certification/guards.txt`, `galaxy-importer.log` |
| Lint / Docs | yamllint, ansible-lint, antsibull-docs errors | reports in `reports/` (build artifacts) |
| Package & certify | `ansible-galaxy collection build` or galaxy-importer errors (runs after all the tests) | `reports/galaxy-importer/`, the tarball in the build artifacts (`dist/`) |
| Security scan | HIGH or CRITICAL finding | fix it, or a justified `# nosec: <rule> reason="..."` |
| Spotter | Spotter findings | the build becomes UNSTABLE (not failed); see `reports/spotter/` |
| Sanity / units / integration | ansible-test | JUnit in the *Tests* tab |
| Publish | the tag differs from the `galaxy.yml` version | tag `1.2.3` (or `v1.2.3`) = `version: 1.2.3` |

Locally, in the ci-tools-image: `ACI_CORE=2.18 /opt/ansible-ci/bin/aci sanity` (or `lint`,
`certification`...).

## 5. Versions

* `@v2` (Jenkins) and `@1` (GitLab): you automatically get fixes and compatible changes.
* A new major version (for example AAP 2.7 as the default platform) will be announced and must be
  adopted explicitly.
* History: `jenkins-shared-library/CHANGELOG.md` and `gitlab-ci-templates/CHANGELOG.md`.
