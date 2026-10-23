# Changelog - GitLab component ansible-collection (ansible-ci)

SemVer releases, tags `x.y.z` (format required by the CI/CD catalog), aligned with `ci-scripts/VERSION`:
* patch: fixes without input or default behaviour changes;
* minor: new input (with a default), new job disabled by default, compatible tool update;
* major: input renamed/removed, changed default (e.g. ansible-core matrix), major version of `aci`.

## 1.1.0 - 2026-10-23

* All comments, input descriptions and messages translated to English (no input or behaviour change).
* `ACI_EXPECTED_VERSION` 1.1.0 (`aci` 1.1.0: English messages only).
* Test files renamed: `examples/complete.gitlab-ci.yml`, `tests/inputs/complete.yml`, `tests/inputs/invalid.yml`.

## 1.0.1 - 2026-10-21

* Fix: default `molecule-images` `ubuntu2404 fedora40` (valid aliases in ansible-core 2.18).
* `ACI_EXPECTED_VERSION` 1.0.1; runner image: Python 3.12 only (326 MB), python3.14 optional.
* Component `tests/` reduced to validation (render + schema) and the test collection (copy kept in sync
  by `tools/sync.sh`); running the jobs on the bench lives in `tests/gitlab-jobs/` of the source repository.

## 1.0.0 - 2026-10-20

* First release: static checks, ansible-test sanity/units (venv in pods, docker on the ansible-builder
  VM), integration, molecule, private Spotter, Nexus publication on tags.
* AAP 2.6 alignment: default matrix ansible-core 2.16 + 2.18 (Python 3.12), `ansible-core-optional`
  (2.20 = AAP 2.7, non-blocking), `target-ees` (EE introspection, immediate failure if incompatible).
* Red Hat certification (partner-certification-checker 6.0.0 reference): guards, galaxy-importer 0.4.39,
  ansible-lint 26.4.0 `--profile=production`, Python 3.12 sanity on stable-2.16/2.18/2.20.
* Changelog fragment required on MRs (`changelog-skip-token`).
* Untested POC: units inside the EEs (`ee-tests`).
