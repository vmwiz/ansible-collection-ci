# Changelog - Jenkins library ansible-ci

SemVer. Immutable tags `vX.Y.Z` + moving tag `v2` (= latest 2.x tag, moved at every release).
Jenkinsfiles use `@Library('ansible-ci@v2')` (fixes and compatible changes automatically) or
`@Library('ansible-ci@v2.0.0')` (pinned).
* patch: fix, no behaviour change;
* minor: compatible change (e.g. a stage that only runs when the repository opts in);
* major: behaviour change (matrix, new blocking stage, removed stage).

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
  `infra/jenkins/jcasc.yaml`.
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
