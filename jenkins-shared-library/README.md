# Jenkins shared library `ansible-ci` (v2)

Tests, validates and publishes Ansible collections, airgapped behind Nexus, aligned with AAP 2.6.
One fixed pipeline, the same stages for every collection; only site settings are parameters.

```groovy
@Library('ansible-ci@v2') _
ansibleCollectionPipeline()
```

```groovy
@Library('ansible-ci@v2') _
ansibleCollectionPipeline(spotterEndpoint: 'https://spotter.corp.local/api', spotterCredentialsId: 'my-team-spotter')
```

## Content

```
vars/ansibleCollectionPipeline.groovy   the pipeline; parameter defaults at the top of the file (DEFAULTS)
resources/ansible-ci/pod.yaml           OpenShift pod (restricted-v2); @@CI_TOOLS_IMAGE@@ <- ciToolsImage
CHANGELOG.md
```

The pipeline only orchestrates; the work is done by the `aci` CLI (`../ci-scripts`), which is installed in
the ci-tools-image and on the ansible-builder VM as `/opt/ansible-ci/bin/aci`. Every stage is one or two
`aci <command>` calls; reports (`reports/**`) are archived and JUnit files published.

## Parameters

All optional. An unknown key stops the build at once with the list of allowed keys.

| Parameter | Default | Purpose (environment variable given to `aci`) |
|---|---|---|
| `galaxyUrl` | `https://nexus.corp.local/repository/ansible-group/` | Galaxy group for collection dependencies (`ACI_GALAXY_URL`) |
| `galaxyPublishUrl` | `https://nexus.corp.local/repository/ansible-hosted/` | Galaxy hosted repository, target of `Publish` (`ACI_GALAXY_PUBLISH_URL`) |
| `pypiEndpoint` | `https://nexus.corp.local/repository/pypi-group/simple` | PyPI index inside the ansible-test containers (`ACI_PYPI_ENDPOINT`) |
| `imageMirror` | `nexus.corp.local:8444` | Docker proxy of quay.io for ansible-test / Molecule images (`ACI_IMAGE_MIRROR`) |
| `spotterEndpoint` | `''` | Private Spotter API (`SPOTTER_ENDPOINT`); **empty = Spotter stage skipped** |
| `spotterCacert` | `/etc/pki/tls/certs/ca-bundle.crt` | CA bundle for the Spotter API (`SPOTTER_CACERT`) |
| `ciToolsImage` | `nexus.corp.local:8443/corp/ci-tools-image:2026.10` | Image of the `runner` container of the pod; its tag pins the `aci` version |
| `builderLabel` | `ansible-builder` | Label of the Podman VM agents (Integration, Molecule) |
| `spotterCredentialsId` | `spotter-api-token` | ID of the Secret text credential holding the Spotter token (`SPOTTER_TOKEN`) |
| `galaxyCredentialsId` | `nexus-galaxy-hosted-token` | ID of the Secret text credential allowed to publish (`ACI_GALAXY_TOKEN`) |

Adapt the defaults once for your site in `DEFAULTS` (top of the Groovy file); the credential parameters hold
Jenkins credential **IDs**, never secrets.

## Stages

| Stage | Agent | Runs when |
|---|---|---|
| Static checks: Lint (+ docs), Certification, Build (+ galaxy-importer), Security scan | OpenShift pod | always |
| Static checks: Spotter (findings → UNSTABLE) | pod | `spotterEndpoint` is not empty |
| Static checks: Changelog fragment | pod | pull requests |
| ansible-test: sanity + units, matrix 2.16 / 2.18 / 2.20 (Python 3.12) | pod | always; units if `tests/unit/` exists |
| Container tests: Integration (`--docker`), Molecule | `builderLabel` (Podman VM) | `tests/integration/targets/` / `extensions/molecule/` exists |
| Publish (Nexus) | pod | tag builds |

## Pod template

`resources/ansible-ci/pod.yaml` is read with `libraryResource` once per build, `@@CI_TOOLS_IMAGE@@` is
replaced by `ciToolsImage`, and every pod stage uses it with `kubernetes { yaml podYaml; defaultContainer 'runner' }`.
It is `restricted-v2` compatible: `runAsNonRoot`, no `runAsUser` (OpenShift assigns an arbitrary UID with
GID 0), no privilege escalation, `drop: ALL`, seccomp `RuntimeDefault`, requests/limits, `emptyDir` on `/tmp`.

## Jenkins setup

Declare the Global Pipeline Library, the two Secret text credentials, a Kubernetes cloud and the
`ansible-builder` agents in *Manage Jenkins*: see [`../infra/jenkins/README.md`](../infra/jenkins/README.md).

## Changing the pipeline

Edit `vars/ansibleCollectionPipeline.groovy`, run the bench (`../tests/jenkins-e2e/run-e2e.sh`), add a
`CHANGELOG.md` entry, tag `vX.Y.Z` and move the `v2` tag. Behaviour changes (matrix, a new blocking
stage) are a new major version.
