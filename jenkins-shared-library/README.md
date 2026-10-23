# Jenkins shared library `ansible-ci` (v2)

Tests, validates and publishes Ansible collections, airgapped behind Nexus, aligned with AAP 2.6.
One fixed pipeline, the same for every collection:

```groovy
@Library('ansible-ci@v2') _
ansibleCollectionPipeline()
```

## Content

```
vars/ansibleCollectionPipeline.groovy   the whole library: one declarative pipeline, no parameters
CHANGELOG.md
```

The pipeline only orchestrates; the work is done by the `aci` CLI (`../ci-scripts`), which is installed in
the runner image and on the ansible-builder VM as `/opt/ansible-ci/bin/aci`. Every stage is one or two
`aci <command>` calls; reports (`reports/**`) are archived and JUnit files published.

## Stages

| Stage | Agent | Runs when |
|---|---|---|
| Static checks: Lint (+ docs), Certification, Build (+ galaxy-importer), Security scan | pod `ansible-runner` | always |
| Static checks: Spotter (findings → UNSTABLE) | pod | `SPOTTER_ENDPOINT` is set globally |
| Static checks: Changelog fragment | pod | pull requests |
| ansible-test: sanity + units, matrix 2.16 / 2.18 / 2.20 (Python 3.12) | pod | always; units if `tests/unit/` exists |
| Container tests: Integration (`--docker`), Molecule | label `ansible-builder` (Podman VM) | `tests/integration/targets/` / `extensions/molecule/` exists |
| Publish (Nexus) | pod | tag builds |

## Requirements on the Jenkins side

Everything site-specific is configured once in [`../infra/jenkins/jcasc.yaml`](../infra/jenkins/jcasc.yaml)
(see [`../infra/jenkins/README.md`](../infra/jenkins/README.md)):

* the global library `ansible-ci` (default version `v2`, tag discovery);
* global environment variables read by `aci`: `ACI_GALAXY_URL`, `ACI_GALAXY_PUBLISH_URL`,
  `ACI_PYPI_ENDPOINT`, `ACI_IMAGE_MIRROR`, `SPOTTER_ENDPOINT`, `SPOTTER_CACERT`;
* the Kubernetes pod template `ansible-runner` (containers `jnlp` + `runner`, runner image);
* agents labelled `ansible-builder` (the Podman VM, `infra/ansible-builder-vm`);
* Secret text credentials `spotter-api-token` and `nexus-galaxy-hosted-token`;
* plugins: pipeline-model-definition, kubernetes, credentials-binding, junit, timestamper, ansicolor.

## Changing the pipeline

Edit `vars/ansibleCollectionPipeline.groovy`, run the bench (`../tests/jenkins-e2e/run-e2e.sh`), add a
`CHANGELOG.md` entry, tag `vX.Y.Z` and move the `v2` tag. Behaviour changes (matrix, a new blocking
stage) are a new major version.
