# Changelog - Jenkins library ansible-ci

SemVer. Immutable tags `vX.Y.Z` + moving tag `v2` (= latest 2.x tag, moved at every release).
Jenkinsfiles use `@Library('ansible-ci@v2')` (fixes and compatible changes automatically) or
`@Library('ansible-ci@v2.0.0')` (pinned).
* patch: fix, no behaviour change;
* minor: compatible change (e.g. a stage that only runs when the repository opts in);
* major: behaviour change (matrix, new blocking stage, removed stage).

## v2.1.1 - 2026-10-26

* No pipeline change. Documented and validated loading the library without registering it
  (`library` step, `modernSCM(scm: ..., libraryPath: 'jenkins-shared-library/')`): it runs in the Groovy
  sandbox with no script approval. New `example-collection/corp.demo/Jenkinsfile.dev` and
  `tools/export-collection.sh` (stand-alone test repository with the collection at its root).

## v2.1.0 - 2026-10-26

* The Configuration as Code file is removed: the admin setup is done in
  *Manage Jenkins* (library, credentials, Kubernetes cloud, `ansible-builder` agents), see `infra/jenkins/README.md`.
* `ansibleCollectionPipeline(Map config = [:])`: site settings become parameters with defaults, defined in one
  `DEFAULTS` map at the top of the file: `galaxyUrl`, `galaxyPublishUrl`, `pypiEndpoint`, `imageMirror`,
  `spotterEndpoint` (empty = Spotter skipped), `spotterCacert`, `ciToolsImage`, `builderLabel`,
  `spotterCredentialsId`, `galaxyCredentialsId` (Jenkins credential IDs). Unknown keys stop the build.
  Stages, matrix and behaviour are unchanged; `ansibleCollectionPipeline()` without arguments still works.
* The pod template ships with the library (`resources/ansible-ci/pod.yaml`, `restricted-v2`); its runner
  image is the `ciToolsImage` parameter. The Kubernetes cloud no longer needs an `ansible-runner` template.
* The runner image is renamed **ci-tools-image** (`infra/ci-tools-image/Containerfile`,
  `nexus.corp.local:8443/corp/ci-tools-image:2026.10`).

## v2.0.0 - 2026-10-23

Breaking: the library is now **one fixed declarative pipeline**, the same for every collection.

* `ansibleCollectionPipeline()` takes **no parameters**. Jenkinsfiles become
  `@Library('ansible-ci@v2') _` + `ansibleCollectionPipeline()`.
* Fixed matrix: ansible-core 2.16, 2.18 and 2.20 on Python 3.12, all blocking (2.20 is part of the Red Hat
  certification sanity). Declarative `matrix` directive.
* Optional stages are selected by the repository content: units (`tests/unit/`), integration
  (`tests/integration/targets/`), Molecule (`extensions/molecule/`); Spotter when the admins set
  `SPOTTER_ENDPOINT`; changelog check on pull requests; publication on tags.
* Site settings (Nexus URLs, Spotter, runner image, pod template, credentials, library version) moved to
  a Jenkins Configuration as Code file (removed again in 2.1.0).
* The `aci` scripts are no longer bundled: the pipeline calls `/opt/ansible-ci/bin/aci` from the runner
  image / VM (`aci` 1.1.0).
* Removed: all granular steps (`withAnsibleCi`, `withAnsibleCore`, `ansibleLint`, `ansibleTestSanity`, ...,
  `ansibleEeUnits`), the internal `aci*` steps, `src/org/corp/ansibleci/Config.groovy`, the `.txt` help
  files, `resources/` (bundled scripts, pod YAML), `test/` (unit tests, pod validation); the parameters
  (`ansibleCoreVersions`, `ansibleCoreOptional`, `targetEEs`, `testMode`, stage switches, Nexus URLs,
  agent settings, ...); EE introspection and the EE units POC (still available in the GitLab component).
* Documentation and messages in English.

## v1.0.1 - 2026-10-21

* Fix: default `moleculeImages` `['ubuntu2404', 'fedora40']`.
* `aci` 1.0.1: Python 3.12 preferred for every series that accepts it.

## v1.0.0 - 2026-10-20

* First release: configurable declarative pipeline (about 60 validated parameters), granular steps for
  scripted pipelines, AAP 2.6 matrix, EE-derived matrix, Red Hat certification, changelog check, bundled
  `aci` 1.0.0 scripts.
