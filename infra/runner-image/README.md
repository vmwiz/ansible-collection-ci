# Runner image (OpenShift pods, Jenkins and GitLab)

Built **on the corporate UBI 9 base image** (`ARG BASE_IMAGE`, default
`nexus.corp.local:8443/corp/ubi9-corp:9.8`: **placeholder**, adapt the registry prefix).

```bash
# context = repository ROOT (the image embeds ci-scripts/)
podman build -f infra/runner-image/Dockerfile --build-arg BASE_IMAGE=<registry>/corp/ubi9-corp:9.8 \
  -t nexus.corp.local:8443/ci/ansible-collection-runner:2026.10 \
  -t nexus.corp.local:8443/ci/ansible-collection-runner:aci-$(cat ci-scripts/VERSION) .
```
Two tags: calendar (`2026.10`, the default of the Jenkins pod template and of the GitLab component) and
scripts version (`aci-1.1.0`). The GitLab component checks the version (`ACI_EXPECTED_VERSION`); on
Jenkins, the image tag set in `infra/jenkins/jcasc.yaml` decides which `aci` every build runs.

| ARG | Default | Role |
|---|---|---|
| `BASE_IMAGE` | `nexus.corp.local:8443/corp/ubi9-corp:9.8` | base image (contract below) |
| `PYTHON_VERSIONS` | `3.12` | interpreters **added** from AppStream (the last one hosts the tooling venv); `"3.12 3.14"` only to test 2.22 / `milestone` / `devel`; the system `python3` (3.9) is untouched |
| `SHELLCHECK_SOURCE` | `pip` | `pip` = `shellcheck-py` from Nexus; `rpm` = `ShellCheck` from EPEL 9 (internal mirror required); `none` |

## Base image contract

| Requirement | Why | Check |
|---|---|---|
| **`/etc/pip.conf`** (or `/etc/xdg/pip/pip.conf`) with `index-url` = Nexus PyPI proxy | *global* file: read for root, UID 1001 and **any arbitrary** OpenShift UID; `ansible-test --venv` **ignores** `PIP_INDEX_URL` for its venvs and only reads this file. No `~/.pip/pip.conf` or `~/.config/pip` (depends on HOME) | `python3.12 -m pip config debug` |
| Internal CA in the **system store** (`/etc/pki/ca-trust/source/anchors` + `update-ca-trust`) | git, curl, ansible-galaxy, Python `ssl` | `curl https://nexus.corp.local` |
| `REQUESTS_CA_BUNDLE` and `SSL_CERT_FILE` = `/etc/pki/tls/certs/ca-bundle.crt` (and/or `cert =` in pip.conf) | pip 23.2 (bootstrapped by `ensurepip` in the ansible-test venvs) and requests (Spotter, galaxy-importer) do not use the system store otherwise | `env` |
| microdnf repositories to the internal mirror with **BaseOS AND AppStream** | `python3.12`, `git-core`, `jq`, `rsync`... are in AppStream; `ShellCheck` only in EPEL 9 (optional) | `microdnf repolist` |
| `microdnf`, `coreutils`, `bash` (UBI minimal) | build | — |

## What the image adds
* `python3.12` and `python3.12-pip` (UBI 9.8: 3.12.15). ansible-test controller Pythons: 2.16 = 3.10-3.12,
  2.18 = 3.11-3.13, 2.20 = 3.12-3.14 → **3.12 covers the whole matrix** (2.16 + 2.18 + 2.20), the
  certification, and matches the Python of the AAP 2.6 EEs. `aci` picks per series (`share/aci/python-map.txt`).
  2.22, `milestone` and `devel` need ≥ 3.13: add `python3.14` (`PYTHON_VERSIONS="3.12 3.14"`; RHEL 9.8
  AppStream has no 3.13);
* `git-core`, `openssh-clients` (ssh-keygen required by ansible-test), `tar`, `gzip`, `findutils`, `rsync`, `jq`, `which`, `diffutils`, `shadow-utils`;
* venv `/opt/ansible-ci` (first in `PATH`): `PyYAML`, `shellcheck-py` (`requirements.txt`, pinned versions);
* **`aci`** scripts (`ci-scripts/`): `/opt/ansible-ci/bin/aci`, `lib/aci`, `share/aci`, `VERSION`;
* user `ci` UID **1001**, GID **0**, `HOME=/home/ci` with `chgrp 0` + `chmod g=u` (OpenShift arbitrary UID).

Deliberately absent: container engine and CLI (the `--docker`, integration and Molecule stages run on the
`ansible-builder` VM), ansible-core (installed by `aci` in cached venvs, per series), CA and `pip.conf`
(provided by the base image). `ansible-test --venv` normally downloads its `get-pip` scripts from the
Internet: `aci` puts `lib/aci/py/get_pip_offline.py` there instead (`ensurepip` + pip from Nexus), no
extra Nexus repository is needed.
Measured size (v1.0.1, Python 3.12 only): **326 MB**; 388 MB with `PYTHON_VERSIONS="3.12 3.14"`.

## Test
The corporate base image is emulated for testing by `tests/image-base-standin/` (not shipped, see
`tests/README.md`).
