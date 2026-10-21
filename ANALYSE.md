# Analyse : comment les collections de `ansible-collections` construisent leur CI

*Relevé effectué le 20/10/2026 (dépôts clonés en `--depth 1` sur leur branche par défaut, commits du 23/06 au 20/10/2026). Sources vérifiées dans le code d'ansible-core 2.21.5, antsibull-nox 1.9.3, tox-ansible 26.10.0, galaxy-importer 0.4.44.*

## 1. Résumé

1. **Le moteur de test reste partout `ansible-test`** (sanity, units, integration), presque toujours avec `--docker`. L'image utilisée est `default` (`quay.io/ansible/default-test-container`), ou une image de distribution (`ubuntu2404`, `fedora43`, `alpine323`…). Toutes les versions de Python embarquées dans l'image sont testées d'un coup.
2. **Matrice = séries ansible-core × (versions Python | images)** : `stable-2.19` … `stable-2.21`, plus `milestone`/`devel`. On trouve un fichier `tests/sanity/ignore-2.X.txt` par série.
3. **Trois « familles » d'outillage partagé** ont remplacé les workflows écrits à la main :

   | Famille | Utilisée par | Mécanique |
   |---|---|---|
   | **antsibull-nox** (communauté, Felix Fontein) | community.general, .docker, .crypto, .dns, .routeros, .sops, (.postgresql, .vmware, ansible.mysql pour les « extra checks ») | `noxfile.py` + `antsibull-nox.toml` ; workflows réutilisables `reusable-nox-matrix.yml` / `reusable-nox-run.yml`. **Même logique en local, sur GHA et sur AZP**, via `tests/utils/shippable/nox.sh` |
   | **ansible/ansible-content-actions** + **ansible-network/github_actions** (Red Hat) | cisco.ios, arista.eos, ansible.netcommon, ansible.utils, kubernetes.core, amazon.aws | Workflows réutilisables (`sanity.yaml`, `unit.yaml`, `ansible_lint.yaml`, `build_import.yaml`, `changelog.yaml`, `release.yaml`), matrice générée par **tox-ansible** (`tox --ansible --gh-matrix`) |
   | **ansible-community/ansible-test-gh-action** | collection_template, amazon.aws (sanity/units), community.vmware, azure, community.grafana, ansible.mysql | Action composite : installe ansible-core, les dépendances, puis lance `ansible-test … --docker` |

4. **Azure Pipelines (AZP) reste très présent** pour les grosses collections communautaires : community.general, .crypto, .docker, .postgresql, .libvirt, .rabbitmq, ansible.posix, ansible.windows. Les jobs tournent dans `quay.io/ansible/azure-pipelines-test-container:8.0.0` avec le socket Docker de l'agent. AZP sert surtout aux cibles `--remote` (VM RHEL, FreeBSD, macOS, Windows), payées via l'« Ansible Core CI » et **inaccessibles hors de l'infra Red Hat**.
5. **Tests d'intégration « applicatifs »** : conteneurs de service démarrés à côté (docker compose pour Vault ou Zabbix, `services:` GHA pour MySQL/MariaDB) puis `--docker-network`, cluster **kind** (kubernetes.core), labo **Cisco CML** (collections réseau), comptes cloud réels (amazon.aws via `ansible/ansible-test-auth`, azure).
6. **Qualité / publication** : `antsibull-changelog lint` (fragments obligatoires dans `changelogs/fragments/`), `ansible-lint`, **galaxy-importer** (validation identique à Galaxy/Automation Hub), `antsibull-docs` (docs-pr/docs-push), puis `ansible-galaxy collection build/publish` sur un tag (`release.yaml` → Galaxy + Automation Hub).
7. **Molecule** : **4 des 23 collections du tableau** (≈ 17 %). Deux pour tester des **rôles** sur de vrais OS conteneurisés : community.zabbix (12 scénarios, `driver: default` et create/destroy maison avec images systemd `privileged`) et community.grafana (1 scénario, driver `docker` de molecule-plugins). Deux comme **harnais d'intégration sans instance** : cisco.ios (32 scénarios `extensions/molecule`, configuration ansible-native, simulateur SSH `cisshgo`) et ansible.scm (6 scénarios lancés par `pytest-ansible`). community.sops, qui a aussi des rôles, les teste leurs rôles avec des cibles `ansible-test integration`. Aucune collection n'utilise Molecule **à la place** d'ansible-test.

## 2. Tableau des collections échantillonnées

| Collection | CI principale | Lint / qualité | Sanity / Units | Intégration | Liens (fichiers réels) |
|---|---|---|---|---|---|
| **community.general** | GHA + AZP, tout via **antsibull-nox** | ruff, mypy, yamllint, extra-checks, docs-check, galaxy-importer (`build_import_check`), ansible-lint | `ansible-test-sanity-2.19…devel` ; units par (core × python) | docker (`fedora43`, `alpine323`, `ubuntu2404`, images `quay.io/ansible-community/test-image:*`) + `--remote` (rhel, macos, freebsd) via AZP | [nox.yml](https://github.com/ansible-collections/community.general/blob/main/.github/workflows/nox.yml) · [antsibull-nox.toml](https://github.com/ansible-collections/community.general/blob/main/antsibull-nox.toml) · [noxfile.py](https://github.com/ansible-collections/community.general/blob/main/noxfile.py) · [azure-pipelines.yml](https://github.com/ansible-collections/community.general/blob/main/.azure-pipelines/azure-pipelines.yml) · [nox.sh](https://github.com/ansible-collections/community.general/blob/main/tests/utils/shippable/nox.sh) |
| **community.docker** | GHA antsibull-nox + AZP | black, ruff, flake8, pylint, mypy, yamllint | matrice antsibull-nox | docker + images d'aide construites et poussées sur `ghcr.io/ansible-collections` | [nox.yml](https://github.com/ansible-collections/community.docker/blob/main/.github/workflows/nox.yml) · [antsibull-nox.toml](https://github.com/ansible-collections/community.docker/blob/main/antsibull-nox.toml) · [docker-images.yml](https://github.com/ansible-collections/community.docker/blob/main/.github/workflows/docker-images.yml) · [azure-pipelines.yml](https://github.com/ansible-collections/community.docker/blob/main/.azure-pipelines/azure-pipelines.yml) |
| **community.crypto** | GHA antsibull-nox + AZP | idem + REUSE/licences | matrice antsibull-nox | docker + remote | [nox.yml](https://github.com/ansible-collections/community.crypto/blob/main/.github/workflows/nox.yml) · [antsibull-nox.toml](https://github.com/ansible-collections/community.crypto/blob/main/antsibull-nox.toml) · [azure-pipelines.yml](https://github.com/ansible-collections/community.crypto/blob/main/.azure-pipelines/azure-pipelines.yml) |
| **community.dns** | GHA antsibull-nox (+ images d'aide `docker-images.yml`) | idem | matrice antsibull-nox | matrice antsibull-nox | [nox.yml](https://github.com/ansible-collections/community.dns/blob/main/.github/workflows/nox.yml) · [antsibull-nox.toml](https://github.com/ansible-collections/community.dns/blob/main/antsibull-nox.toml) |
| **community.routeros** | GHA antsibull-nox | idem | matrice antsibull-nox (ignore-2.9 → 2.23 !) | — | [nox.yml](https://github.com/ansible-collections/community.routeros/blob/main/.github/workflows/nox.yml) |
| **community.sops** | GHA antsibull-nox | idem | matrice antsibull-nox | matrice antsibull-nox | [nox.yml](https://github.com/ansible-collections/community.sops/blob/main/.github/workflows/nox.yml) |
| **community.postgresql** | AZP (`shippable.sh`) + action antsibull-nox (extra sanity) | extra-checks | AZP | docker (distributions) | [nox.yml](https://github.com/ansible-collections/community.postgresql/blob/main/.github/workflows/nox.yml) · [azure-pipelines.yml](https://github.com/ansible-collections/community.postgresql/blob/main/.azure-pipelines/azure-pipelines.yml) · [shippable.sh](https://github.com/ansible-collections/community.postgresql/blob/main/tests/utils/shippable/shippable.sh) |
| **ansible.mysql** (successeur de community.mysql, dépréciée) | GHA ansible-test-gh-action + antsibull-nox | extra-checks | — | conteneurs `services:` MySQL/MariaDB (`docker.io/library/…`) + réplication | [ansible-test-plugins.yml](https://github.com/ansible-collections/ansible.mysql/blob/main/.github/workflows/ansible-test-plugins.yml) · [nox.yml](https://github.com/ansible-collections/ansible.mysql/blob/main/.github/workflows/nox.yml) |
| **ansible.posix** | AZP uniquement (+ certification GHA) | `lint` (ansible-lint) | `ansible-test sanity --docker --junit`, `units --docker default` | `--docker <image>` + `--remote` | [azure-pipelines.yml](https://github.com/ansible-collections/ansible.posix/blob/main/.azure-pipelines/azure-pipelines.yml) · [shippable.sh](https://github.com/ansible-collections/ansible.posix/blob/main/tests/utils/shippable/shippable.sh) · [sanity.sh](https://github.com/ansible-collections/ansible.posix/blob/main/tests/utils/shippable/sanity.sh) · [linux.sh](https://github.com/ansible-collections/ansible.posix/blob/main/tests/utils/shippable/linux.sh) |
| **ansible.windows** | AZP | — | sanity/units | `windows-integration` sur 2019/2022/2025 (winrm, psrp, ssh) | [azure-pipelines.yml](https://github.com/ansible-collections/ansible.windows/blob/main/.azure-pipelines/azure-pipelines.yml) |
| **community.libvirt** | AZP | — | sanity/units `--docker default` | docker + remote (VM) | [azure-pipelines.yml](https://github.com/ansible-collections/community.libvirt/blob/main/.azure-pipelines/azure-pipelines.yml) |
| **community.rabbitmq** | AZP | — | sanity/units | docker (ubuntu2204/2404) | [azure-pipelines.yml](https://github.com/ansible-collections/community.rabbitmq/blob/main/.azure-pipelines/azure-pipelines.yml) |
| **kubernetes.core** | GHA + workflows réutilisables **ansible-network/github_actions** | tox-linters, ansible-lint, changelog, galaxy-importer, security-check | `sanity.yml`, `unit_source.yml` | **kind** (`helm/kind-action`, `kindest/node:v1.29.2`) + `ansible_test_integration` | [integration-tests.yaml](https://github.com/ansible-collections/kubernetes.core/blob/main/.github/workflows/integration-tests.yaml) · [sanity-tests.yaml](https://github.com/ansible-collections/kubernetes.core/blob/main/.github/workflows/sanity-tests.yaml) · [galaxy-import.yaml](https://github.com/ansible-collections/kubernetes.core/blob/main/.github/workflows/galaxy-import.yaml) · [linters.yaml](https://github.com/ansible-collections/kubernetes.core/blob/main/.github/workflows/linters.yaml) |
| **amazon.aws** | GHA ; intégration historiquement Zuul (cf. commentaire du workflow) | ruff/pylint via **tox** (`tox-ansible==26.9.0`), ansible-lint, changelog, SonarCloud | **ansible-test-gh-action** : `stable-2.18…devel × py3.11…3.15` | comptes AWS réels (`ansible/ansible-test-auth`), « splitter » de cibles sur 24 jobs | [ansible-test.yml](https://github.com/ansible-collections/amazon.aws/blob/main/.github/workflows/ansible-test.yml) · [tox.ini](https://github.com/ansible-collections/amazon.aws/blob/main/tox.ini) · [integration.yml](https://github.com/ansible-collections/amazon.aws/blob/main/.github/workflows/integration.yml) · [galaxy-importer.yaml](https://github.com/ansible-collections/amazon.aws/blob/main/.github/workflows/galaxy-importer.yaml) |
| **cisco.ios** | GHA **ansible-content-actions** | changelog, ansible-lint, build_import (galaxy-importer, `CHECK_REQUIRED_TAGS`) | sanity/unit par **tox-ansible** (`tox-ansible.ini`) | labo **CML** (libssh/paramiko) × `stable-2.19…devel` ; **molecule** | [tests.yml](https://github.com/ansible-collections/cisco.ios/blob/main/.github/workflows/tests.yml) · [tox-ansible.ini](https://github.com/ansible-collections/cisco.ios/blob/main/tox-ansible.ini) · [integration-libssh.yml](https://github.com/ansible-collections/cisco.ios/blob/main/.github/workflows/integration-libssh.yml) · [release.yml](https://github.com/ansible-collections/cisco.ios/blob/main/.github/workflows/release.yml) |
| **arista.eos** | idem cisco.ios | idem | idem | CML | [tests.yml](https://github.com/ansible-collections/arista.eos/blob/main/.github/workflows/tests.yml) |
| **ansible.netcommon** | idem | idem | idem | CML | [tests.yml](https://github.com/ansible-collections/ansible.netcommon/blob/main/.github/workflows/tests.yml) |
| **ansible.utils** | idem | idem | idem | `integration.yaml` | [tests.yml](https://github.com/ansible-collections/ansible.utils/blob/main/.github/workflows/tests.yml) |
| **ansible.scm** | GHA **tox-ansible** (`ansible/tox-ansible/.github/workflows/run.yml`) | ansible-lint, pre-commit | tox-ansible | molecule (`extensions/molecule`) | [test.yml](https://github.com/ansible-collections/ansible.scm/blob/main/.github/workflows/test.yml) · [tox-ansible.ini](https://github.com/ansible-collections/ansible.scm/blob/main/tox-ansible.ini) |
| **community.hashi_vault** | GHA « fait main » | docs | `sanity --docker default`, `units --docker default` | **docker compose** (Vault, Postgres) + `--docker-network hashi_vault_default` ; pré-chargement des images avec `--prime-containers` | [ansible-test.yml](https://github.com/ansible-collections/community.hashi_vault/blob/main/.github/workflows/ansible-test.yml) · [pull-ansible-test-images](https://github.com/ansible-collections/community.hashi_vault/blob/main/.github/actions/pull-ansible-test-images/action.yml) |
| **community.vmware** | GHA ansible-test-gh-action + antsibull-nox | extra-docs | sanity/units `stable-2.21`, `2.22`, `milestone` | vCenter réel (historique Zuul, cf. `testing.md`) | [ansible-test.yml](https://github.com/ansible-collections/community.vmware/blob/main/.github/workflows/ansible-test.yml) · [nox.yml](https://github.com/ansible-collections/community.vmware/blob/main/.github/workflows/nox.yml) |
| **azure** (azure.azcollection) | GHA ansible-test-gh-action (units) + AZP (`pr-pipelines.yml`) | certification | units | souscription Azure réelle | [ansible-test.yml](https://github.com/ansible-collections/azure/blob/dev/.github/workflows/ansible-test.yml) · [pr-pipelines.yml](https://github.com/ansible-collections/azure/blob/dev/pr-pipelines.yml) |
| **community.grafana** | GHA ansible-test-gh-action | ansible-lint, black, ruff, fragments | sanity/units | ansible-test integration + **molecule** (docker) | [ansible-test.yml](https://github.com/ansible-collections/community.grafana/blob/main/.github/workflows/ansible-test.yml) · [lint.yml](https://github.com/ansible-collections/community.grafana/blob/main/.github/workflows/lint.yml) |
| **community.zabbix** | GHA « fait main » (1 workflow par rôle) | flake8, `antsibull-changelog lint` (tox) | `sanity --docker` | **molecule** (7 distributions) ; plugins : **docker compose** Zabbix puis `ansible-test integration` **sans** `--docker` | [agent.yml](https://github.com/ansible-collections/community.zabbix/blob/main/.github/workflows/agent.yml) · [plugins-integration-full.yml](https://github.com/ansible-collections/community.zabbix/blob/main/.github/workflows/plugins-integration-full.yml) · [docker-compose.yml](https://github.com/ansible-collections/community.zabbix/blob/main/docker-compose.yml) |
| **collection_template** (référence) | GHA ansible-test-gh-action | extra-docs-linting | sanity/units `stable-2.19…devel` | exemple avec conteneur applicatif | [ansible-test.yml](https://github.com/ansible-collections/collection_template/blob/main/.github/workflows/ansible-test.yml) |

> Le dépôt historique `community.mysql` est **déprécié** (README : « all its content moved as-is to ansible.mysql »). Aucune configuration Zuul (`.zuul.yaml`/`zuul.d`) n'est encore présente dans les dépôts échantillonnés : Zuul n'apparaît plus qu'en mention historique (amazon.aws, community.vmware).

## 3. Motifs communs (ce qu'il faut reproduire)

### 3.1 Arborescence imposée par ansible-test
`ansible-test` doit être lancé depuis `…/ansible_collections/<namespace>/<name>/`. Chaque CI règle ce point à sa façon :
* `checkoutPath: ansible_collections/community/general` (AZP) ;
* `actions/checkout` avec `path: ansible_collections/${NAMESPACE}/${COLLECTION_NAME}` (hashi_vault, zabbix) ;
* `rsync` vers `{envtmpdir}/…/ansible_collections/amazon/aws` (tox d'amazon.aws).

Les dépendances de collections sont installées **dans la même racine `ansible_collections`**. ansible-test les embarque alors dans le conteneur (vérifié dans `ansible_test/_internal/payload.py` : *« include files from each collection in the same collection root »*). Elles viennent soit de `ansible-galaxy collection install`, soit d'un `git clone` (ansible.posix : *« we're installing with git to work around Galaxy being a huge PITA »*), soit des `collection_sources` git d'antsibull-nox.

### 3.2 Invocations ansible-test réellement utilisées
```bash
ansible-test sanity --color -v --junit --docker [--base-branch …] [--allow-disabled]      # ansible.posix
ansible-test units --color -v --docker default [--coverage] [--changed]                  # libvirt, rabbitmq
ansible-test integration --color -v --retry-on-error <cible> --docker <image>            # posix linux.sh
ansible-test integration -v --retry-on-error --continue-on-error --python X --docker default \
             --docker-network hashi_vault_default                                        # hashi_vault
ansible-test coverage xml -v --requirements --group-by command --group-by version        # rabbitmq/zabbix
ansible-test <cmd> --prime-containers                                                    # hashi_vault (pré-pull)
```
Conventions de pilotage : `ci_complete` / `ci_coverage` dans le message de commit, `--changed` pour les PR (détection de changements), `--coverage-check` par défaut, `--coverage` la nuit.

### 3.3 Matrices observées (octobre 2026)
* Séries ansible-core : **2.19, 2.20, 2.21** dans tous les dépôts actifs, plus `2.22` (RC1 le 13/10/2026), `milestone` et `devel`. Les plus conservateurs gardent 2.17 et 2.18 (hashi_vault, amazon.aws).
* Python : déduit de la série (exemple community.general, units 2.21 → 3.9 / 3.12 / 3.14). Pour sanity/units, `--docker default` couvre toutes les versions Python de l'image : `v2.21-4` contient 3.9 à 3.14.
* Fichiers `tests/sanity/ignore-2.X.txt` : un par série supportée, souvent jusqu'à `ignore-2.23.txt` (devel).

### 3.4 Changelog, lint, import, publication
* `changelogs/config.yaml` et fragments obligatoires (`antsibull-changelog lint`, ou l'action `ansible_validate_changelog`, ou le label `skip-changelog`).
* galaxy-importer : `python -m galaxy_importer.main --git-clone-path . --output-path /tmp` avec `CHECK_REQUIRED_TAGS=True` (`ansible-content-actions/build_import.yaml`), ou la session nox `build-import-check`.
* Publication : `release.yaml` (ansible-content-actions), qui publie sur Galaxy (`ANSIBLE_GALAXY_API_KEY`) et sur Automation Hub (`AH_TOKEN`).
* Docs : `ansible-community/github-docs-build` (`_shared-docs-build-pr.yml` / `-push.yml`), à base d'antsibull-docs.

## 4. Ce qui sort sur Internet (et cassera en airgap)

| Outil / étape | Accès réseau réalisé | Vérifié dans |
|---|---|---|
| `ansible-test --docker` | `docker pull quay.io/ansible/default-test-container:v2.21-4` (+ `base-test-container`, images de distribution, `ansible-test-utility-container:3.5.0`, `http-test-container:3.6.0`, `pypi-test-container:3.6.0`, `acme-…`, `openshift-origin`…). | `_data/completion/docker.txt`, `docker_util.py`, `commands/integration/cloud/*.py` |
| `ansible-test units/integration --requirements`, `--coverage` | `pip install` **dans le conteneur** (requirements de la collection, coverage, etc.) | `python_requirements.py`, `pypi_proxy.py` |
| `ansible-test --remote` | API Ansible Core CI (clé Red Hat) : **inutilisable on-prem** | `cli/environments.py` |
| Image `default-test-container` (construction) | clone `github.com/ansible/ansible` et pré-création des venvs sanity (`--prime-venvs`) | [Containerfile](https://github.com/ansible/default-test-container/blob/main/Containerfile), `files/prime.py` |
| ansible-test-gh-action | `pip install https://github.com/ansible/ansible/archive/<ref>.tar.gz`, `ansible-galaxy collection install` | [action.yml](https://github.com/ansible-community/ansible-test-gh-action/blob/main/action.yml) |
| antsibull-nox | **ansible-core depuis l'archive GitHub par défaut** (`ansible_core_source="git"`, non configurable dans le TOML), `collection_sources` en `git+https://github.com/…`, `pip install …/antsibull-nox/archive/main.tar.gz` dans `nox-prepare.sh` | `antsibull_nox/sessions/ansible_test.py`, `ansible.py` |
| tox-ansible | `ade install --acv stable-X.Y`, et ansible-dev-environment télécharge depuis `https://github.com/ansible/ansible/archive` | `tox_ansible/plugin.py`, `ansible_dev_environment/subcommands/installer.py` |
| ansible-lint | installe `requirements.yml` et rafraîchit les schémas, **sauf `--offline`** | `ansible-lint --help` |
| galaxy-importer | ansible-lint lancé hors ligne par défaut (`offline_ansible_lint=True`) ; `run_ansible_test=False` par défaut | `galaxy_importer/config.py` |
| ansible-galaxy | `galaxy.ansible.com` par défaut | `ansible.cfg [galaxy] server_list` |
| kind / molecule / services | `kindest/node`, `docker.io/library/mysql`, images de rôles, binaire kind (GitHub) | workflows |
| Cibles d'intégration | `apt`/`dnf`/`pip` dans les rôles `setup_*` | `tests/integration/targets/setup_*` |

## 5. Enseignements pour notre contexte (airgap, Jenkins + GitLab)

> **Note (v4 / v1.0.1)** : les points 1 et 2 ci-dessous sont les conclusions de la v3 (nox). Le *principe*
> est conservé (toute la logique en un seul endroit, la CI ne fait qu'orchestrer), mais il est désormais
> porté par le CLI bash `aci` des bibliothèques centrales, sans `noxfile.py` dans les collections
> (voir PROPOSITION §1 et §21.2). Les relevés de cette analyse (séries 2.19 → 2.22 observées en amont)
> décrivent l'existant upstream ; la matrice retenue pour AAP 2.6 est 2.16 + 2.18 (+ 2.20 optionnelle).

1. **Le pattern antsibull-nox est le bon** : toute la logique est dans le dépôt (`noxfile.py`) et l'outil de CI ne fait qu'appeler `nox -e <session>`. C'est ce qui permet à community.general de tourner à l'identique sur GHA, sur AZP et en local. Pour nous, la même chose vaudra pour Jenkins et GitLab.
2. En revanche, **antsibull-nox et tox-ansible téléchargent ansible-core depuis GitHub**, et les actions GHA réutilisables ne sont pas transposables. On garde donc le *principe* (nox), avec un `noxfile.py` maîtrisé qui installe ansible-core depuis PyPI, donc via Nexus.
3. `--docker default` reste la méthode de référence. Il faut seulement fournir les images `quay.io/ansible/*` **sous leur nom exact** et rediriger pip dans les conteneurs.
4. Les intégrations `--remote` (VM RHEL, FreeBSD, macOS, Windows de Red Hat) sont à remplacer par des conteneurs de distribution, ou par des VM internes déclarées dans un inventaire `--windows`/`--inventory`.
