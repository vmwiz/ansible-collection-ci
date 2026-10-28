# Changelog - GitLab component ansible-collection (ansible-ci)

SemVer releases, tags `x.y.z` (format required by the CI/CD catalog), aligned with `ci-scripts/VERSION`:
* patch: fixes without input or default behaviour changes;
* minor: new input (with a default), new job disabled by default, compatible tool update;
* major: input renamed/removed, changed default (e.g. ansible-core matrix), major version of `aci`.

## 1.3.0 - 2026-10-28

* Workspace layout: every job adds a `src/` git worktree of the pipeline commit (`before_script`) and runs
  `aci` with `ACI_SRC=src`, `ACI_REPORTS=reports`, `ACI_DIST=dist`: the tools only see `src/`, the reports
  and the tarball stay under `CI_PROJECT_DIR` (artifact names unchanged). Fixes the SARIF and
  certification reports shipped in the tarball (and linted by galaxy-importer) when `build_ignore` lacked
  `reports`/`dist`. The jobs now define `before_script`: a `default: before_script` of the including
  project no longer applies to them.
* Inputs unchanged. Default `runner-image` `ci-tools-image:2026.10.2`, `ACI_EXPECTED_VERSION` 1.3.0
  (`aci` 1.3.0: `ACI_SRC` defaults to `./src` when `./src/galaxy.yml` exists, else the current
  directory; `ACI_REPORTS`/`ACI_DIST` default to the siblings of `src/`, else to `/tmp/aci-<uid>/<name>/`
  (local runs, shown by `aci info`); any of them inside `ACI_SRC` is refused. The `--exclude reports/dist`
  options of ansible-lint, yamllint, the security scanner and Spotter are removed (they never see them).
  `ci-scripts/tests/layout.sh` poisons `reports/` and `dist/` and checks that lint, docs, security-scan
  and build ignore them.)
* `tests/validate.sh`: every job has the `src/` worktree and the layout variables.

## 1.2.0 - 2026-10-28

* Same order as the Jenkins library, each block only if the previous one passed (`needs`): static analysis
  (`aci-lint`, `aci-docs`, `aci-changelog`, `aci-security`, `aci-spotter`) → ansible-test → container tests →
  `aci-build` (build + importer) → `aci-certification` → `aci-publish` (tags). `aci-build` and
  `aci-certification` move from `stage-static` to `stage-test`; `aci-certification` certifies the `dist/`
  artifact of `aci-build`, which `aci-publish` publishes (no rebuild). The test jobs no longer start before
  the static analysis has passed.
* Inputs unchanged (only the descriptions of `stage-static` / `stage-test`). Default `runner-image`
  `ci-tools-image:2026.10.1`, `ACI_EXPECTED_VERSION` 1.2.0 (`aci` 1.2.0).
* `tests/render.py --order` (execution order from `needs`/stages) and order checks in `tests/validate.sh`.

## 1.1.0 - 2026-10-23

* All comments, input descriptions and messages translated to English (no input or behaviour change).
* `ACI_EXPECTED_VERSION` 1.1.0 (`aci` 1.1.0: English messages only).
* Test files renamed: `examples/complete.gitlab-ci.yml`, `tests/inputs/complete.yml`, `tests/inputs/invalid.yml`.

## 1.0.1 - 2026-10-21

* Fix: default `molecule-images` `ubuntu2404 fedora40` (valid aliases in ansible-core 2.18).
* `ACI_EXPECTED_VERSION` 1.0.1; ci-tools-image: Python 3.12 only (326 MB), python3.14 optional.
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
