# ansible-ci : bibliothèques CI pour collections Ansible (Jenkins + GitLab, airgap/Nexus, AAP 2.6)

Version **1.0.0** (v4 de la proposition). Une collection n'a plus de code CI, seulement deux à trois
lignes :

```groovy
@Library('ansible-ci@v1') _
ansibleCollectionPipeline()
```
```yaml
include:
  - component: $CI_SERVER_FQDN/ci/ansible-collection-ci/ansible-collection@1
```

| Chemin | Contenu |
|---|---|
| [PROPOSITION.md](PROPOSITION.md) | Architecture, alignement AAP 2.6, certification Red Hat, paramètres, versionnement, onboarding, migration v3 → v4, validation, limites, feuille de route |
| [GUIDE-UTILISATEUR.md](GUIDE-UTILISATEUR.md) | Pour les équipes : `Jenkinsfile` et `.gitlab-ci.yml` minimaux et complets à copier-coller, FAQ |
| [ANALYSE.md](ANALYSE.md) | Étude des CI de 23 collections `ansible-collections/*` |
| `ci-scripts/` | **Source unique** du CLI bash `aci` (`bin/aci`, `lib/aci/cmd/*.sh`, helpers Python, `share/aci/` : versions figées, `python-map.txt`, `certification.env`) + `tests/` (smoke, guards) |
| `jenkins-shared-library/` | Bibliothèque partagée : `vars/` (pipeline déclaratif + 18 étapes, aide `.txt`), `src/` (Config @NonCPS), `resources/` (copie d'`aci`, pod restricted-v2), `test/` (unitaires, pod, e2e Jenkins), `CHANGELOG.md` |
| `gitlab-ci-templates/` | Composant CI/CD `ansible-collection` (`templates/ansible-collection/template.yml`, 46 inputs), exemples, `tests/` (rendu + schéma GitLab + exécution réelle des jobs), `CHANGELOG.md` |
| `tools/sync-aci.sh` | Copie `ci-scripts/` dans la bibliothèque Jenkins (`--check` : vérifie la copie) |
| `infra/runner-image/` | Image runner UBI 9 + python3.12/3.14 + `aci` dans `/opt/ansible-ci` (contexte de build = racine du dépôt) |
| `infra/ansible-builder-vm/` | Playbook de la VM podman (agent Jenkins / runner GitLab shell), installe `aci` |
| `infra/jenkins/`, `infra/gitlab-runner/`, `infra/openshift/`, `infra/podman/`, `infra/test-images/` | Déclaration de la bibliothèque (JCasC), runners, options OpenShift, miroirs, images dérivées |
| `exemple-collection/corp.demo/` | Collection de démonstration (Jenkinsfile + .gitlab-ci.yml v4) |
| `archive/v3-nox/` | Version précédente (nox), aussi au tag git `v3-nox` |

## Mainteneurs CI : cycle de développement

```bash
# 1. Modifier ci-scripts/, puis
tools/sync-aci.sh && ci-scripts/tests/smoke.sh && ci-scripts/tests/guards.sh
shellcheck -x ci-scripts/bin/aci ci-scripts/lib/aci/*.sh ci-scripts/lib/aci/cmd/*.sh
# 2. Bibliothèque Jenkins
jenkins-shared-library/test/unit/run.sh          # Config (14 tests)
jenkins-shared-library/test/validate-pod.sh      # pod restricted-v2
jenkins-shared-library/test/e2e/run-e2e.sh       # Jenkins 2.580.1 réel + corp.demo (banc airgap)
# 3. Composant GitLab
gitlab-ci-templates/tests/validate.sh            # rendu + schéma officiel + jobs par contexte
gitlab-ci-templates/tests/run-jobs.sh gitlab-ci-templates/tests/inputs/banc.yml branch "aci-lint aci-certification"
# 4. Image runner
podman build -f infra/runner-image/Dockerfile --build-arg BASE_IMAGE=<registre>/corp/ubi9-corp:9.8 \
  -t nexus.corp.local:8443/ci/ansible-collection-runner:2026.10 .
```

## `aci` en local (image runner ou VM)

```bash
cd ma.collection
ACI_CORE=2.18 /opt/ansible-ci/bin/aci sanity          # venv par défaut ; ACI_TEST_MODE=docker sur la VM
/opt/ansible-ci/bin/aci certification                 # contrôles de certification Red Hat
/opt/ansible-ci/bin/aci help                          # toutes les commandes
```

| Variable | Rôle |
|---|---|
| `ACI_CORE`, `ACI_CORE_VERSIONS`, `ACI_CORE_DEFAULT`, `ACI_PRERELEASE`, `ACI_CORE_PIN` | Série, matrice, série par défaut, pré-versions, version exacte |
| `ACI_PYTHON`, `ACI_PYTHON_MAP` | Python contrôleur (cible en mode docker), table série → Python |
| `ACI_TEST_MODE` | `venv` (défaut) ou `docker` |
| `ACI_PYPI_ENDPOINT`, `ACI_PIP_INDEX_URL`, `ACI_IMAGE_MIRROR` | Nexus (conteneurs ansible-test, pip, images quay.io) |
| `ACI_GALAXY_URL`, `ACI_GALAXY_PUBLISH_URL`, `ACI_GALAXY_TOKEN` | Galaxy Nexus |
| `ACI_EE_MATRIX`, `ACI_EE_EXPECT_CORES` | Matrice issue des EE (GitLab) |
| `ACI_CERT_ENV`, `ACI_CHANGELOG_SKIP`, `ACI_TARGET_BRANCH` | Certification, changelog |
| `SPOTTER_ENDPOINT`, `SPOTTER_TOKEN`, `ACI_SPOTTER_EXPORT_ONLY` | Spotter privé |
| `ACI_CACHE`, `ACI_WORK`, `ACI_REPORTS` | Cache des venvs, arbre de travail (hors dépôt git), rapports |

Les placeholders à adapter sont `nexus.corp.local:844x`, `hub.corp.local`, `spotter.corp.local`,
`gitlab.corp.local`, ainsi que le `BASE_IMAGE` de l'image runner.
