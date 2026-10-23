# Jenkins: `ansible-ci` shared library, agents and site settings

Everything an admin needs is in [`jcasc.yaml`](jcasc.yaml) (Jenkins Configuration as Code). The pipeline
itself takes **no parameters**: every collection runs the same stages, and all site-specific values
live here.

## 1. Library

`unclassified.globalLibraries` declares the **global** library `ansible-ci` (trusted code, runs outside
the sandbox; only CI maintainers can write to its repository), default version `v2`.

* `v2` = moving tag on the latest 2.x release (moved at every release); `v2.0.0`... = immutable tags.
* Collections use `@Library('ansible-ci@v2') _` (fixes arrive automatically) or pin `@Library('ansible-ci@v2.0.0')`.
* `gitTagDiscovery` is required so that tags can be used as library versions.

## 2. Global environment (read by `aci`)

| Variable | Role |
|---|---|
| `ACI_GALAXY_URL` | Nexus Galaxy group (proxy of galaxy.ansible.com / Automation Hub) used to install collection dependencies |
| `ACI_GALAXY_PUBLISH_URL` | Nexus Galaxy hosted repository, target of the `Publish` stage (tag builds) |
| `ACI_PYPI_ENDPOINT` | PyPI index used inside ansible-test containers (ansible-builder VM) |
| `ACI_IMAGE_MIRROR` | Nexus Docker proxy of quay.io (ansible-test and Molecule images) |
| `SPOTTER_ENDPOINT` | Private Spotter API. **Empty = the Spotter stage is skipped** |
| `SPOTTER_CACERT` | CA bundle for the Spotter API |

pip itself needs nothing here: the runner image and the VM have `/etc/pip.conf` pointing to Nexus.

## 3. Agents

| Agent | Defined in | Used for |
|---|---|---|
| Pod template `ansible-runner` (OpenShift, SCC `restricted-v2`) | `jcasc.yaml`, `clouds.kubernetes.templates` | Static checks, certification, build, security scan, Spotter, changelog, sanity/units matrix (`venv` mode), publish |
| Permanent agents labelled `ansible-builder` (Podman VM) | Jenkins nodes (SSH or inbound), prepared by `../ansible-builder-vm/site.yml` | Integration (`ansible-test --docker`) and Molecule |

* The pipeline selects the pod with `kubernetes { inheritFrom 'ansible-runner'; defaultContainer 'runner' }`.
  The `runner` container image tag (`nexus.corp.local:8443/ci/ansible-collection-runner:2026.10`) decides
  which `aci` version every build uses: bump it to roll out a new runner image.
* VM: one executor per parallel container stage (each `ansible-test --docker` run starts 2-3 containers).
  If a real `docker` binary is installed next to podman, set `ANSIBLE_TEST_PREFER_PODMAN=1` on the node.

## 4. Plugins and credentials

* Plugins: configuration-as-code, workflow-aggregator (Pipeline), pipeline-model-definition,
  pipeline-groovy-lib, git, kubernetes, junit, credentials-binding, plain-credentials, ansicolor, timestamper.
* Credentials (Secret text): `spotter-api-token` (private Spotter), `nexus-galaxy-hosted-token`
  (publication to `ACI_GALAXY_PUBLISH_URL`). Values come from `${SPOTTER_API_TOKEN}` / `${NEXUS_GALAXY_TOKEN}`
  (e.g. a Kubernetes Secret mounted into the controller).
* The changelog fragment check runs on pull requests of **multibranch** jobs (`changeRequest()`), and
  `Publish` on tag builds (`buildingTag()`, multibranch with tag discovery).

## 5. Validation

`../../tests/jenkins-e2e/run-e2e.sh` (bench, not shipped) starts Jenkins 2.580.1 with this very
`jcasc.yaml`, loads the library from a local git repository and runs the example collection. The
Kubernetes pod template is checked by JCasC at load time, but no build ran on a real cluster (the bench
uses a static agent labelled `ansible-runner` instead).
