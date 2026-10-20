# Pipeline CI airgap pour collections Ansible (Jenkins + GitLab CI, Nexus)

Livrables :

| Fichier | Contenu |
|---|---|
| [ANALYSE.md](ANALYSE.md) | Étude des CI de 23 collections `ansible-collections/*`, avec liens vers les fichiers réels |
| [PROPOSITION.md](PROPOSITION.md) | Architecture cible, dépôts Nexus, stratégie d'images, matrice, pièges, validation |
| `collection-files/` | **À copier à la racine d'une collection** |
| `collection-files/noxfile.py` | Toute la logique CI (lint, docs, build, galaxy-importer, sanity/units/integration par série ansible-core en mode `docker` ou `venv`, security-scan, spotter, molecule, publish) |
| `collection-files/.gitlab-ci.yml` | Orchestration GitLab : runner Kubernetes OpenShift (tag `openshift`) + runner shell VM (tag `ansible-builder`), JUnit/SAST, publication sur tag |
| `collection-files/Jenkinsfile` | Jenkins déclaratif hybride : pods OpenShift (statique, sécurité, tests `--venv`) + agent VM `ansible-builder` (podman : `--docker`, intégration, Molecule) |
| `collection-files/ci/jenkins-agent-pod.yaml` | Pod agent Jenkins compatible SCC `restricted-v2` (jnlp + runner) |
| `collection-files/ci/ansible.cfg` | Serveurs Galaxy → Nexus (format Ansible, ≥ 3.93) |
| `collection-files/ci/prime_images.py` | Pull Nexus + re-tag `quay.io/ansible/*` pour ansible-test |
| `collection-files/ci/get_pip_offline.py` | Remplaçant hors ligne du get-pip d'ansible-test --venv (ensurepip + pip depuis Nexus), déposé par le noxfile |
| `collection-files/ci/{constraints,requirements-*}.txt`, `galaxy-importer.cfg`, `yamllint.yml` | Versions figées et configurations des outils (dont `requirements-security.txt`, `requirements-molecule.txt`) |
| `infra/runner-image/` | `Dockerfile` de l'image runner **FROM l'image UBI 9 d'entreprise** (`ARG BASE_IMAGE`), `requirements.txt`, README (contrat de la base), `standin/` (émulation de test) |
| `infra/openshift/` | Pod agent, POC podman imbriqué (OCP ≥ 4.20) et README des options OpenShift |
| `infra/ansible-builder-vm/` | Playbook de préparation de la VM `ansible-builder` (podman rootless, linger, Nexus, venv nox) |
| `infra/test-images/` | (Optionnel) images ansible-test dérivées : AC, pip et APT vers Nexus |
| `infra/podman/registries.conf` | Miroirs quay.io / docker.io / ghcr.io pour les agents Podman |
| `infra/gitlab-runner/config.toml.example` | Runners GitLab : Kubernetes sur OpenShift + shell sur la VM (socket Docker en commentaire) |
| `infra/jenkins/README.md` | Prérequis Jenkins : cloud Kubernetes, agent VM, plugins, credentials |
| `exemple-collection/corp.demo/` | Collection de démonstration (module, filtre, rôle `motd`, scénarios Molecule ansible-native) |

## Démarrage rapide

```bash
# 1. Image runner (dans l'airgap)
#    (AC, /etc/pip.conf et dépôts microdnf viennent de l'image de base : voir infra/runner-image/README.md)
podman build infra/runner-image \
  --build-arg BASE_IMAGE=nexus.corp.local:8443/corp/ubi9-corp:9.8 \
  -t nexus.corp.local:8443/ci/ansible-collection-runner:2026.10
podman push nexus.corp.local:8443/ci/ansible-collection-runner:2026.10

# 2. Dans le dépôt de la collection
cp -r collection-files/{noxfile.py,ci,.gitlab-ci.yml,Jenkinsfile} /chemin/ma.collection/
cp collection-files/ci/yamllint.yml /chemin/ma.collection/.yamllint   # recommandé (lu aussi par ansible-lint)
# galaxy.yml : build_ignore: [ci, noxfile.py, Jenkinsfile, .gitlab-ci.yml, reports, dist, .nox]
# .gitignore : .nox/ dist/ reports/ tests/output/

# 3. En local ou dans le runner
export PIP_INDEX_URL=https://nexus.corp.local/repository/pypi-group/simple
export ANSIBLE_TEST_IMAGE_MIRROR=nexus.corp.local:8444
export ANSIBLE_TEST_PYPI_ENDPOINT=https://nexus.corp.local/repository/pypi-group/simple/
nox -l
nox -s lint build galaxy-importer
nox -s sanity-2.21 units-2.21 integration-2.21
nox -s units-2.21 -- --python 3.12          # arguments passés à ansible-test (docker)
ANSIBLE_TEST_DOCKER=ubuntu2404 nox -s integration-2.21 -- ma_cible
ANSIBLE_TEST_MODE=venv nox -s sanity-2.21 units-2.21   # pod sans moteur de conteneurs
nox -s security-scan
SPOTTER_ENDPOINT=https://spotter.corp.local/api SPOTTER_TOKEN=… nox -s spotter
ANSIBLE_TEST_PREFER_PODMAN=1 CONTAINER_ENGINE=podman nox -s molecule   # VM podman
```

Adapter les noms d'hôtes `nexus.corp.local:844x` dans `.gitlab-ci.yml`, `Jenkinsfile`, `ci/ansible.cfg`, `infra/runner-image/Dockerfile` (`BASE_IMAGE`).

## Variables reconnues par le noxfile

| Variable | Défaut | Rôle |
|---|---|---|
| `ANSIBLE_TEST_MODE` | `docker` | `docker` (`--docker`, VM podman/docker) ou `venv` (`--venv`, pod OpenShift ; integration refusée) |
| `ANSIBLE_TEST_PREFER_PODMAN` | — | lu par ansible-test : préférer podman à docker |
| `SECURITY_SCAN_SEVERITY` | — | seuil d'affichage d'ansible-security-scanner (l'échec reste HIGH/CRITICAL) |
| `SPOTTER_ENDPOINT` | — (obligatoire) | API de l'instance Spotter privée, ex. `https://spotter.corp.local/api` (lue par la CLI) |
| `SPOTTER_TOKEN` / `SPOTTER_API_TOKEN` | — | jeton Spotter (credential CI) |
| `SPOTTER_CACERT` | — | bundle AC interne pour l'instance privée (lu par la CLI) |
| `SPOTTER_ANSIBLE_VERSION` | `2.20` | `--ansible-version` (la CLI 6.6.0 s'arrête à 2.20) |
| `SPOTTER_DISPLAY_LEVEL` | `error` | `hint`, `warning` ou `error` |
| `SPOTTER_EXPORT_ONLY` | — | `1` : `--export-payload` hors ligne, sans appel à l'API |
| `MOLECULE_IMAGES` | `ubuntu2404 fedora43` | alias ansible-test pré-tirés pour les cibles Molecule |
| `ANSIBLE_CORE_VERSIONS` | `2.19 2.20 2.21 2.22` | séries générant les sessions `sanity-X.Y`, `units-X.Y`, `integration-X.Y`, `images-X.Y` |
| `ANSIBLE_CORE_PRERELEASE` | `2.22` | séries encore en pré-version (`ansible-core>=X.Y.0a0`) ; à vider à la GA |
| `ANSIBLE_CI_PYTHON_<X_Y>` | — | force le Python contrôleur d'une série (défaut : le plus récent supporté et présent : 2.19 → 3.12, 2.20-2.22 → 3.14) |
| `ANSIBLE_TEST_VENV_URL_REQS` | — | `allow` : ne pas ignorer en `--venv` les tests sanity à exigences par URL (2.22 : pylint) |
| `ANSIBLE_CORE_DEFAULT` | dernière série hors pré-version | série utilisée par lint / docs / build / importer / publish |
| `ANSIBLE_CORE_SRC_DEVEL`, `ANSIBLE_CORE_SRC_MILESTONE` | — | URL interne d'un tarball ansible-core si `devel`/`milestone` sont dans la matrice |
| `ANSIBLE_TEST_IMAGE_MIRROR` | — | miroir Nexus de quay.io ; vide = pas de re-tag |
| `ANSIBLE_TEST_PYPI_ENDPOINT` | — | index PyPI injecté par ansible-test dans ses conteneurs |
| `ANSIBLE_TEST_DOCKER` | `default` | image/alias ansible-test pour l'intégration |
| `ANSIBLE_TEST_DOCKER_NETWORK` | — | réseau docker (services applicatifs démarrés à côté) |
| `ANSIBLE_TEST_COVERAGE` | — | `1` : `--coverage` + `ansible-test coverage xml` |
| `ANSIBLE_CI_WORKDIR` | `$TMPDIR` | racine de l'arbre `ansible_collections/…`, **hors dépôt git** |
| `CONTAINER_ENGINE` | `docker` (`podman` pour molecule) | moteur utilisé par `prime_images.py` et vérifié par `molecule` |
| `GALAXY_PUBLISH_SERVER` | — | nom de serveur `ci/ansible.cfg` (ex. `nexus_hosted`) pour `publish` |
| `ANSIBLE_GALAXY_SERVER_<NOM>_TOKEN` | — | jeton du serveur Galaxy (credential CI, jamais dans le dépôt) |

## Validation effectuée (20/10/2026)
* `noxfile.py` et `ci/prime_images.py` compilent (`py_compile`). `nox -l` liste les 20 sessions.
* `.gitlab-ci.yml` : yamllint OK et **schéma GitLab officiel OK** (`check-jsonschema --builtin-schema vendor.gitlab-ci`).
* `infra/runner-image/Dockerfile` et `infra/test-images/Dockerfile` : **build OK**.
* Exécution de bout en bout **dans l'image runner**, en **airgap simulé** (egress des conteneurs coupé, registre pull-through quay.io et proxy PyPI devpi en guise de Nexus) : lint, build, galaxy-importer, docs, sanity-2.21, units-2.21, integration-2.21 **OK**, plus sanity-2.19 OK. Test négatif : units sans `--pypi-endpoint` → échec attendu.
* `Jenkinsfile` : **validé** sur Jenkins 2.580.1 + plugin kubernetes (`pipeline-model-converter/validate`).
* v2 : VM simulée en **podman rootless** (lint, docs, build, galaxy-importer, security-scan, spotter export, molecule, sanity/units/integration 2.21 OK) ; **pod OpenShift simulé** (UID arbitraire, aucun moteur, `--cap-drop ALL`) : statique + sanity/units 2.19/2.20/2.21 en `--venv` OK. Détails : PROPOSITION §11.
* v3 : image runner **UBI 9** (base émulée), UID `1000680000:0`, réseau coupé sauf un faux Nexus HTTPS (AC de test) : statique + sanity/units 2.19/2.20/2.21 en `--venv` OK. v3.1 : python3.12 + python3.14, sanity/units **2.19 → 2.22** OK ; 403 Mo (341 Mo avec 3.12 seul, 347 Mo pour l'image Debian).
