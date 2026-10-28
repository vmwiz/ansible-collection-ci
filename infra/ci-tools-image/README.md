# ci-tools-image (OpenShift pods, Jenkins and GitLab)

Built **on the corporate UBI 9 Python image** `corp/hub/python3:3.12` (`ARG BASE_IMAGE`, default
`nexus.corp.local:8443/corp/hub/python3:3.12`: the registry prefix is a **placeholder**, adapt it).

```bash
# context = repository ROOT (the image embeds ci-scripts/)
podman build -f infra/ci-tools-image/Containerfile --build-arg BASE_IMAGE=<registry>/corp/hub/python3:3.12 \
  -t nexus.corp.local:8443/corp/ci-tools-image:2026.10.2 \
  -t nexus.corp.local:8443/corp/ci-tools-image:aci-$(cat ci-scripts/VERSION) .
```
Two tags: calendar `YYYY.MM[.N]` (`2026.10.2`, the default `ciToolsImage` of the Jenkins library and `runner-image` of the
GitLab component; `.N` = rebuild within the same month, a published tag is never overwritten) and
scripts version (`aci-1.3.0`). The GitLab component checks the version (`ACI_EXPECTED_VERSION`); on
Jenkins, the `ciToolsImage` pipeline parameter (default in `jenkins-shared-library/vars/ansibleCollectionPipeline.groovy`)
decides which `aci` every build runs.

| ARG | Default | Role |
|---|---|---|
| `BASE_IMAGE` | `nexus.corp.local:8443/corp/hub/python3:3.12` | corporate Python base image (contract below); its Python is the only one of the image. `.../corp/hub/python3:3.14` only to test 2.22 / `milestone` / `devel` (separate image tag) |
| `SHELLCHECK_SOURCE` | `pip` | `pip` = `shellcheck-py` from Nexus; `rpm` = `ShellCheck` from EPEL 9 (internal mirror required); `none` |

## Base image contract

| Requirement | Why | Check |
|---|---|---|
| **One Python** at `/usr/bin/python`, `/usr/bin/python3`, `/usr/bin/python3.<Y>` (and `pip`, `pip3`, `pip3.<Y>`), with the `venv` and `ensurepip` modules | ansible-test controller (`python3.<Y>` found by `aci`), `/opt/ansible-ci` venv (`/usr/bin/python3 -m venv`), the ansible-test venvs (`ensurepip`) | checked at the end of the build |
| **`/etc/pip.conf`** (or `/etc/xdg/pip/pip.conf`) with `index-url` = Nexus PyPI proxy | *global* file: read for root, UID 1001 and **any arbitrary** OpenShift UID; `ansible-test --venv` **ignores** `PIP_INDEX_URL` for its venvs and only reads this file. No `~/.pip/pip.conf` or `~/.config/pip` (depends on HOME) | `python3.12 -m pip config debug` |
| Internal CA in the **system store** (`/etc/pki/ca-trust/source/anchors` + `update-ca-trust`) | git, curl, ansible-galaxy, Python `ssl` | `curl https://nexus.corp.local` |
| `REQUESTS_CA_BUNDLE` and `SSL_CERT_FILE` = `/etc/pki/tls/certs/ca-bundle.crt` (and/or `cert =` in pip.conf) | pip 23.2 (bootstrapped by `ensurepip` in the ansible-test venvs) and requests (Spotter, galaxy-importer) do not use the system store otherwise | `env` |
| microdnf repositories to the internal mirror with **BaseOS AND AppStream** | `git-core`, `jq`, `rsync`... are in AppStream; `ShellCheck` only in EPEL 9 (optional) | `microdnf repolist` |
| `microdnf`, `coreutils`, `bash` (UBI minimal) | build | — |

## What the image adds
* no Python of its own: the base image Python (3.12) is the ansible-test controller. Controller ranges:
  2.16 = 3.10-3.12, 2.18 = 3.11-3.13, 2.20 = 3.12-3.14 → **3.12 covers the whole matrix** (2.16 + 2.18 + 2.20),
  the certification, and matches the Python of the AAP 2.6 EEs. `aci` picks `python3.<Y>` per series
  (`share/aci/python-map.txt`). 2.22, `milestone` and `devel` need ≥ 3.13: build a second image from
  `corp/hub/python3:3.14` (in that image 2.16 / 2.18 stop with "no controller Python for ansible-core ...");
* the `/opt/ansible-ci` venv is created from the versioned interpreter (`readlink -f /usr/bin/python3`, e.g.
  `/usr/bin/python3.12`): an RPM added on top of the image can pull the RHEL `python3` (3.9) and take over
  `/usr/bin/python3` (seen with `java-21-openjdk-headless` in the bench agent image); `aci` calls
  `python3.<Y>`, so neither is affected;
* if the base image already has a UID 1001 user it is reused, otherwise the `ci` user is created;
* `git-core`, `openssh-clients` (ssh-keygen required by ansible-test), `tar`, `gzip`, `findutils`, `rsync`, `jq`, `which`, `diffutils`, `shadow-utils`;
* venv `/opt/ansible-ci` (first in `PATH`): `PyYAML`, `shellcheck-py` (`requirements.txt`, pinned versions);
* **`aci`** scripts (`ci-scripts/`): `/opt/ansible-ci/bin/aci`, `lib/aci`, `share/aci`, `VERSION`;
* user `ci` UID **1001**, GID **0**, `HOME=/home/ci` with `chgrp 0` + `chmod g=u` (OpenShift arbitrary UID).

Deliberately absent: container engine and CLI (the `--docker`, integration and Molecule stages run on the
`ansible-builder` VM), ansible-core (installed by `aci` in cached venvs, per series), CA and `pip.conf`
(provided by the base image). `ansible-test --venv` normally downloads its `get-pip` scripts from the
Internet: `aci` puts `lib/aci/py/get_pip_offline.py` there instead (`ensurepip` + pip from Nexus), no
extra Nexus repository is needed.
Measured size (v2.2.0, stand-in base): **277 MB** (326 MB before, when python3.12 was added on top of the
system Python 3.9).

## Test
The corporate Python base image is emulated for testing by `tests/image-base-standin/` (not shipped, see
`tests/README.md`).
