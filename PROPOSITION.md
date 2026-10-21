# Proposition v4 : bibliothèques CI pour tester et valider des collections Ansible (airgap, Jenkins et GitLab, AAP 2.6)

*Version 4, 20/10/2026 ; révision 1.0.1 du 21/10/2026 (nettoyage : Python 3.12 seul requis, fichiers
obsolètes retirés, banc de test isolé dans `tests/`).*

**Ce qui change par rapport à la v3**
* **nox est retiré.** La logique ne vit plus dans chaque dépôt (`noxfile.py`). Elle est dans **deux
  bibliothèques centrales**, que les équipes appellent avec quelques variables :
  * une *Shared Library* Jenkins, en Groovy déclaratif ou scripté ;
  * un *composant* GitLab CI/CD avec `spec:inputs`.
* Les deux exécutent **les mêmes scripts bash `aci`**.
* **Alignement AAP 2.6** :
  * matrice par défaut ansible-core **2.16 + 2.18** en Python **3.12**, plus **2.20 en option** pour
    préparer AAP 2.7 ;
  * matrice dérivée des EE réellement déployées (`targetEEs`) ;
  * étape **certification Red Hat** ;
  * **fragment de changelog obligatoire** sur les PR/MR.
* La v3 (nox) n'est plus livrée ; elle reste consultable dans l'historique git (tag `v3-nox`).

## 0. En bref

```groovy
// Jenkinsfile
@Library('ansible-ci@v1') _
ansibleCollectionPipeline()
```
```yaml
# .gitlab-ci.yml
include:
  - component: $CI_SERVER_FQDN/ci/ansible-collection-ci/ansible-collection@1
```

Ces deux lignes déclenchent tout le pipeline :
* lint, docs, build, galaxy-importer, scan de sécurité, certification Red Hat ;
* fragment de changelog sur les PR/MR ;
* ansible-test sanity et units sur ansible-core 2.16 et 2.18, avec Python 3.12 ;
* publication sur Nexus à chaque tag.

Le tout tourne en airgap derrière Nexus : pods OpenShift `restricted-v2` et VM `ansible-builder` (podman).

## 1. Principes directeurs

1. **La logique est centrale et versionnée.** Une collection ne contient plus de code CI : seulement
   un `Jenkinsfile` ou un `.gitlab-ci.yml` de quelques lignes. Une correction ou une mise à jour d'outil
   se publie une seule fois (tags `v1.x.y`) et arrive dans tous les dépôts qui suivent `v1`.
2. **Un seul moteur pour les deux CI.** Le CLI bash `aci` (`ci-scripts/`) fait tout le travail : venvs
   par série, Nexus, ansible-test, rapports. Jenkins (Groovy) et GitLab (YAML) se contentent
   d'**orchestrer** : stages, parallélisme, agents, credentials, JUnit. Les règles métier ne sont écrites
   qu'une fois, et testées avec shellcheck et des tests de fumée.
3. **`ansible-test` reste le moteur de test** (sanity / units / integration), comme dans 100 % des
   collections étudiées ([ANALYSE](ANALYSE.md)).
4. **Rien ne sort sur Internet.** PyPI, images, collections, EE et RPM passent par Nexus. Les outils qui
   téléchargent depuis GitHub (antsibull-nox, tox-ansible, ansible-test-gh-action) sont écartés.
5. **On s'aligne sur la plateforme cible** (AAP 2.6) et sur la **certification Red Hat**, avec les mêmes
   versions d'outils que le `partner-certification-checker`.
6. **Les erreurs de configuration sont détectées tôt.** Les paramètres sont validés avant d'allouer un
   agent ; le message liste toutes les erreurs et propose une correction. Les EE incompatibles sont
   refusées dès la première étape.

## 2. Architecture

```mermaid
flowchart LR
  subgraph repo[Dépôt ansible-collection-ci - mainteneurs CI]
    aci[ci-scripts/ : CLI bash aci 1.0.0<br/>+ helpers Python, versions figées,<br/>certification.env]
    jsl[jenkins-shared-library/<br/>vars/ src/ resources/]
    glc[gitlab-ci-templates/<br/>templates/ansible-collection]
    img[infra/runner-image<br/>UBI 9 + py3.12 + aci]
    vm[infra/ansible-builder-vm<br/>podman + aci]
  end
  aci -- tools/sync.sh --> jsl
  aci -- COPY --> img
  aci -- playbook --> vm
  col[Collection<br/>Jenkinsfile 2 lignes / .gitlab-ci.yml 3 lignes]
  col -->|@Library ansible-ci@v1| jk[Jenkins]
  col -->|include: component @1| gl[GitLab CI]
  jsl --> jk
  glc --> gl
  subgraph OCP[OpenShift restricted-v2]
    pod[pod runner : statique, certification,<br/>sanity/units --venv]
  end
  subgraph VMB[VM ansible-builder]
    pdm[podman : introspection EE,<br/>--docker, integration, molecule]
  end
  jk & gl --> pod & pdm
  pod & pdm -. PyPI, Galaxy, images, EE .-> nx[(Nexus)]
  pod -. HTTPS .-> sp[Spotter privé]
```

| Brique | Rôle | Livraison des scripts `aci` |
|---|---|---|
| `ci-scripts/` | **Source unique** : `bin/aci` (dispatcher), `lib/aci/common.sh`, `lib/aci/cmd/*.sh` (une commande par fichier), `lib/aci/py/*.py`, `share/aci/` (contraintes, configurations, `python-map.txt`, `certification.env`) | — |
| `jenkins-shared-library/` | `ansibleCollectionPipeline` (déclaratif) + 18 étapes granulaires + pod `restricted-v2` | **copie embarquée** dans `resources/` (`tools/sync.sh`, contrôlée par `--check`), déposée sur l'agent par `libraryResource` : la version des scripts = la version de la bibliothèque |
| `gitlab-ci-templates/` | composant `ansible-collection` (46 inputs) | **dans l'image runner** `/opt/ansible-ci/bin/aci` (un composant ne livre que du YAML ; évaluation au §7.3) |
| `infra/runner-image/` | image des pods (Jenkins et GitLab) | `COPY ci-scripts` |
| `infra/ansible-builder-vm/` | VM podman (agent Jenkins, runner GitLab `shell`) | copie par le playbook |

Commandes `aci` : `lint`, `docs`, `build`, `importer`, `certification [sanity-cores]`, `changelog-check`,
`ee-introspect`, `sanity`, `units`, `integration`, `security-scan`, `spotter`, `molecule`, `prime-images`,
`publish`, `ee-units` (POC), `venv`, `info`. L'interface se fait par variables `ACI_*`, que les deux
bibliothèques positionnent : `ACI_CORE`, `ACI_CORE_VERSIONS`, `ACI_PRERELEASE`, `ACI_TEST_MODE`,
`ACI_PYTHON`, `ACI_CORE_PIN`, `ACI_PYPI_ENDPOINT`, `ACI_GALAXY_*`… En local, un développeur lance la même
chose : `ACI_CORE=2.18 /opt/ansible-ci/bin/aci sanity`.

## 3. Alignement AAP 2.6

### 3.1 Matrice par défaut

| Série | Rôle | Python contrôleur upstream | Python utilisé |
|---|---|---|---|
| **2.16** | AAP 2.6 (défaut de la plateforme) | 3.10 – 3.12 | **3.12** (celui des EE) |
| **2.18** | AAP 2.5 / 2.6 / 2.7 | 3.11 – 3.13 | **3.12** |
| 2.20 | AAP 2.7, **optionnelle** (`ansibleCoreOptional: ['2.20']` / `ansible-core-optional: '2.20'`), non bloquante | 3.12 – 3.14 | **3.12** |

Les plages viennent de `CONTROLLER_PYTHON_VERSIONS` des branches `stable-2.16/2.18/2.20`
d'ansible-test : 3.12 est bien dans la plage de 2.16. Elles sont centralisées dans `share/aci/python-map.txt`,
où 3.12 est listé en premier pour toutes les séries qui l'acceptent (2.16 → 2.21). L'image runner et la VM
n'ont donc besoin que de **python3.12**. 2.21 reste possible par paramètre ; 2.22, `milestone` et `devel`
(contrôleur ≥ 3.13) exigent d'ajouter python3.14 à l'image (`PYTHON_VERSIONS="3.12 3.14"`), par exemple pour
une série nocturne non bloquante. Sans lui, `aci` s'arrête avec « aucun Python contrôleur pour ansible-core
2.22 sur cet agent ».

### 3.2 Matrice dérivée des EE (`targetEEs` / `target-ees`)
1. Sur la VM : `podman run --rm --pull=missing --network none --entrypoint ansible <EE> --version`.
   On lit `ansible [core X.Y.Z]` et `python version = A.B`. L'image n'est pas modifiée et n'a pas de réseau.
2. `ee_matrix.py` vérifie, pour chaque EE, que :
   * la série est connue ;
   * le Python est dans la plage contrôleur de la série ;
   * la version satisfait `requires_ansible` (`meta/runtime.yml`).

   Sinon **échec immédiat**, avec un message par EE, par exemple
   « hub.corp.local/ee-legacy:bad : Python 3.10 hors plage contrôleur d'ansible-core 2.18 (3.11, 3.12, 3.13) ».
3. **Jenkins** : la matrice sanity/units est remplacée par celle des EE. Chaque branche est épinglée sur
   la **version exacte** (`ansible-core==2.16.19`) et le **Python** de l'EE.
4. **GitLab** : la matrice d'un pipeline est statique. `ansible-core-versions` doit donc lister
   exactement les séries des EE ; le job d'introspection échoue en indiquant la valeur à mettre. Les jobs
   de test lisent l'artefact `reports/ee/matrix.txt` (version exacte et Python de l'EE).
5. **Tests dans l'EE** (units et intégration exécutées *dans* l'image de l'EE, avec ses bibliothèques) :
   étape **POC optionnelle**, `eeTests` / `ee-tests`, désactivée par défaut et **non testée** (pas d'accès à
   registry.redhat.io). Voir §16.

## 4. Étapes du pipeline

| Étape | Jenkins (étape) | GitLab (job) | `aci` | Agent | Quand |
|---|---|---|---|---|---|
| Introspection EE | `ansibleEeIntrospect` | `aci-ee-introspect` (`.pre`) | `ee-introspect` | VM | si `targetEEs` |
| Changelog | `ansibleChangelogCheck` | `aci-changelog` | `changelog-check` | pod | PR (multibranche) / MR |
| Certification | `ansibleCertification` | `aci-certification` | `certification` | pod | toujours (désactivable) |
| Lint | `ansibleLint` | `aci-lint` | `lint` (yamllint --strict, antsibull-changelog lint, ansible-lint --offline) | pod | toujours |
| Docs | `ansibleCollectionDocs` | `aci-docs` | `docs` (antsibull-docs lint-collection-docs --plugin-docs) | pod | toujours |
| Build + import | `ansibleCollectionBuild` + `galaxyImporter` | `aci-build` | `build`, `importer` | pod | toujours |
| Sécurité | `ansibleSecurityScan` | `aci-security` | `security-scan` (bloquant ≥ HIGH) | pod | toujours |
| Spotter | `spotterScan` | `aci-spotter` | `spotter` (instance privée) | pod | si `spotter` (non bloquant par défaut) |
| Sanity / units | `ansibleTestSanity` / `ansibleTestUnits` (branches parallèles) | `aci-{sanity,units}-{venv,docker}` (`parallel:matrix`) | `sanity`, `units` | pod (venv) / VM (docker) | toujours ; docker sur main/tags/planifié en mode `auto` |
| Séries optionnelles | branches « [non bloquant] » | `aci-optional-cores` | `sanity`, `units` | pod | si `ansibleCoreOptional` |
| Sanity de certification | branches « certification sanity X py3.12 » | `aci-certification-sanity` | `sanity` (Python 3.12) | pod / VM | séries 2.16/2.18/2.20 ≥ `requires_ansible` non déjà couvertes en 3.12 |
| Intégration | `ansibleTestIntegration` | `aci-integration` | `integration --docker <image>` | VM | si `integration` |
| Molecule | `moleculeTest` | `aci-molecule` | `prime-images`, `molecule` | VM | si `molecule` |
| EE units (POC) | `ansibleEeUnits` | `aci-ee-units` | `ee-units` | VM | si `eeTests` |
| Publication | `ansibleCollectionPublish` | `aci-publish` | `publish` (tag = version de galaxy.yml) | pod | tag |

Mode `auto` : `--venv` dans le pod (rapide, sans privilège) sur les branches et PR/MR ; `--docker default`
sur la VM (référence, tous les Python) sur la branche par défaut, les tags et les builds planifiés.

Les rapports sont écrits dans `reports/<étape>-<série>/` :
* JUnit publié par `junit` (Jenkins) et par `artifacts:reports:junit` (GitLab) ;
* `importer_result.json`, SARIF, `guards.txt`, `matrix.txt` ;
* ces fichiers sont archivés en plus des JUnit.

## 5. Certification Red Hat (référence : partner-certification-checker v6.0.0)

Toutes les versions sont dans **un seul fichier** de la bibliothèque, `share/aci/certification.env`
(surchargeable par `ACI_CERT_ENV`). On le met à jour quand le checker évolue :

```
ACI_CERT_CHECKER_VERSION=6.0.0      ACI_CERT_PYTHON=3.12           ACI_CERT_ANSIBLE_CORE=2.16.19
ACI_CERT_GALAXY_IMPORTER=0.4.39     ACI_CERT_ANSIBLE_LINT=26.4.0   ACI_CERT_EXTRA_PIP="distlib>=0.3.9"
ACI_CERT_IMPORTER_CHECK_REQUIRED_TAGS=True   ACI_CERT_IMPORTER_RUN_ANSIBLE_LINT=False
ACI_CERT_SANITY_CORES="2.16 2.18 2.20"       ACI_CERT_SANITY_PYTHON=3.12
ACI_CERT_SUPPORTED_CORES="2.16 2.18 2.20"    + liste des ignores autorisés, règles ansible-lint obligatoires
```

| Contrôle du checker | Reproduction | Écart |
|---|---|---|
| galaxy-importer 0.4.39, Python 3.12, `ansible-core==2.16.19`, `distlib>=0.3.9`, `CHECK_REQUIRED_TAGS=True`, `RUN_ANSIBLE_LINT=False`, `--git-clone-path` | venv dédié, épinglé, `python -m galaxy_importer.main --git-clone-path <arbre> --output-path reports/certification` | aucun (constaté dans le workflow v6.0.0) |
| ansible-lint 26.4.0 `--profile=production` | même version, même profil, `--offline` | `--offline` (airgap) |
| sanity `stable-2.16/2.18/2.20` filtrée par `requires_ansible` (regex `>=X.Y`), Python 3.12 | `aci certification sanity-cores` puis `aci sanity` en Python 3.12 pour les séries non couvertes par la matrice | le checker lance `ansible-test-gh-action` en docker ; ici, même mode que la matrice (venv sur les branches, docker sur main et les tags) |

**Garde-fous** ajoutés (`cert_guards.py`, rapport `reports/certification/guards.txt`), qui échouent avec un message explicite :
1. **Ignores sanity** : toute ligne de `tests/sanity/ignore-*.txt` hors de la liste fermée de la règle
   ansible-lint `sanity` est refusée :
   * liste autorisée : `validate-modules:missing-gplv3-license`, `action-plugin-docs`,
     `import-2.6/2.7/3.5`, `compile-2.6/2.7/3.5` (et leur forme `!skip`), `shebang`, `shellcheck`,
     `pylint:used-before-assignment` ;
   * seuls les chemins `plugins/` et `roles/` sont contrôlés, comme le fait la règle ;
   * **dérogation tracée** : un commentaire `# aci-derogation: <motif>` sur la ligne transforme l'erreur
     en avertissement.
2. **`.ansible-lint`** :
   * `profile` vaut `production` ou est absent ;
   * aucune des 10 règles obligatoires dans `skip_list`, `warn_list` ou `.ansible-lint-ignore` ;
   * aucun `exclude_paths` qui masque `plugins/`, `roles/` ou `extensions/` (sauf `extensions/molecule`).
3. **`requires_ansible`** : sa borne basse doit être une série supportée (2.16, 2.18 ou 2.20). Une borne
   2.19 (tech preview) est refusée.

## 6. Référence des paramètres (Jenkins ⇄ GitLab)

Les références complètes avec défauts sont `jenkins-shared-library/vars/ansibleCollectionPipeline.txt`
(également affichée par Jenkins) et le tableau d'inputs de `gitlab-ci-templates/README.md`. Résumé :

| Thème | Jenkins (`ansibleCollectionPipeline`) | GitLab (`inputs`) | Défaut |
|---|---|---|---|
| Matrice | `ansibleCoreVersions` | `ansible-core-versions` | `['2.16','2.18']` |
| Séries non bloquantes | `ansibleCoreOptional` | `ansible-core-optional` (chaîne) | aucune (conseillé : `2.20`) |
| Pré-versions | `ansibleCorePrerelease` (+ `prereleaseUnstable`) | `ansible-core-prerelease` | aucune |
| Série des étapes statiques | `ansibleCoreDefault` | `ansible-core-default` | dernière série non pré-version |
| EE cibles | `targetEEs` (exclusif avec `ansibleCoreVersions`) | `target-ees` (chaîne) | aucune |
| Python par série | `pythonMap` | — (`ACI_PYTHON_MAP`) | `share/aci/python-map.txt` |
| Étapes | `lint docs build galaxyImporter securityScan certification certificationSanity changelogCheck sanity units publish` | mêmes noms en kebab-case | `true` |
| Étapes optionnelles | `integration molecule spotter eeTests` | `integration molecule spotter ee-tests` | `false` |
| Exemption changelog | `changelogSkipToken` | `changelog-skip-token` | `skip-changelog` |
| Mode ansible-test | `testMode`, `fullTestBranches` | `test-mode` | `auto` |
| Arguments | `sanityArgs unitsArgs integrationArgs dockerNetwork coverage` | `sanity-args …` | vides / `false` |
| Intégration / Molecule | `integrationCoreVersions integrationImages moleculeImages` | `integration-images molecule-images` | `['default']`, `ubuntu2404 fedora40` |
| Agents | `agentType runnerImage jnlpImage podTemplateYaml podCloud runnerLabel builderLabel containerEngine` | `runner-image runner-tags builder-tags` | pod `kubernetes`, `ansible-runner`, `ansible-builder` |
| Scripts | `scriptsFrom` (`library` / `agent`), `agentScriptsPath` | `aci-path` | bibliothèque / `/opt/ansible-ci/bin/aci` |
| Nexus | `pipIndexUrl pypiEndpoint imageMirror galaxyServerUrl galaxyPublishUrl` | `pip-index-url pypi-endpoint image-mirror galaxy-server-url galaxy-publish-url` | URL `nexus.corp.local` (placeholders) |
| Secrets | `galaxyCredentialsId`, `spotterCredentialsId` (Secret text) | variables masquées `ACI_GALAXY_TOKEN`, `SPOTTER_TOKEN` | — |
| Scanners | `securityFailOn securityReportSeverity spotterEndpoint spotterCaCert spotterAnsibleVersion spotterDisplayLevel spotterBlocking` | `security-fail-on spotter-endpoint spotter-ansible-version spotter-display-level spotter-allow-failure` | `high`, —, `2.20`, `error`, non bloquant |
| Divers | `timeoutMinutes testTimeoutMinutes buildsToKeep failFast color extraEnv` | `stage-static stage-test stage-publish` | 90, 45, 20 |

Validation :
* **Jenkins** : clé inconnue (avec suggestion par distance de Levenshtein), type (« '2.20' entre quotes »),
  valeur hors liste, série inconnue ou en double, règles croisées (`spotter` sans endpoint, `galaxyImporter`
  ou `publish` sans `build`, `targetEEs` avec `ansibleCoreVersions`, `eeTests` sans `targetEEs`). Tout est
  vérifié avant d'allouer un agent.
* **GitLab** : types, `options` et `regex` des inputs, au moment où le pipeline est créé.

## 7. Versionnement et publication

### 7.1 Règles
* **SemVer**, une seule version pour tout le dépôt : `ci-scripts/VERSION` = bibliothèque Jenkins =
  composant GitLab = tag d'image `aci-X.Y.Z`. Version actuelle : **1.0.1**.
* **Patch** : correctif. **Mineure** : nouveau paramètre ou nouvelle étape *désactivée par défaut*, mise à
  jour compatible d'un outil. **Majeure** : paramètre renommé, **défaut modifié** (matrice, étape activée
  par défaut), version majeure d'`aci`. Exemple : passer la matrice par défaut à 2.18 + 2.20 lors du
  passage à AAP 2.7 sera une **v2**.
* **Jenkins** : tags `vX.Y.Z` immuables + **branche mobile `v1`** (avancée à chaque release ; c'est le
  `defaultVersion` de la bibliothèque globale). Les équipes écrivent `@Library('ansible-ci@v1')`, ou
  figent une version avec `@v1.0.0`.
* **GitLab** : tags `X.Y.Z` (format exigé par le catalogue) + job `release`. Les équipes incluent `@1`
  (dernière 1.x) ou `@1.0.0`.
* `CHANGELOG.md` dans chaque bibliothèque.

### 7.2 Procédure de release (mainteneurs CI)
1. Modifier `ci-scripts/`, lancer `tools/sync.sh` puis `ci-scripts/tests/smoke.sh`,
   `ci-scripts/tests/guards.sh` et shellcheck.
2. Lancer `tools/sync.sh --check`, `jenkins-shared-library/test/unit/run.sh`, `test/validate-pod.sh`,
   `gitlab-ci-templates/tests/validate.sh`, puis le banc (`tests/jenkins-e2e/run-e2e.sh`,
   `tests/gitlab-jobs/run-jobs.sh`, voir `tests/README.md`).
3. Mettre à jour `VERSION`, les `CHANGELOG.md`, `ACI_EXPECTED_VERSION` et le `runner-image` par défaut
   du composant. `validate.sh` contrôle la cohérence.
4. Construire et pousser l'image runner (`2026.MM` + `aci-X.Y.Z`), puis relancer le playbook de la VM.
5. Publier :
   * `git tag vX.Y.Z` ;
   * `git subtree split --prefix jenkins-shared-library` → dépôt `ci/ansible-ci-jenkins`, avec le tag
     `vX.Y.Z` et le déplacement de la branche `v1` ;
   * `git subtree split --prefix gitlab-ci-templates` → projet composant `ci/ansible-collection-ci`, avec
     le tag `X.Y.Z` (job `release`).

### 7.3 Scripts dans l'image runner (`/opt/ansible-ci/bin`) : évaluation
Il y a trois options : scripts **intégrés à l'image**, **clonés par le job**, ou **inline dans le YAML**.
Le détail est au §« Scripts dans l'image » de `gitlab-ci-templates/README.md`.

**Recommandation : intégrés à l'image** pour GitLab.
* Le job n'a besoin d'aucun accès réseau supplémentaire.
* La version est figée par le tag d'image.
* Ce sont les mêmes fichiers que pour Jenkins, et ils sont testés.
* Garde-fou : le composant fixe `ACI_EXPECTED_VERSION`, et `aci` refuse une image d'une autre version
  majeure.

Pour **Jenkins**, on garde la copie embarquée dans la bibliothèque (`scriptsFrom: 'library'`) : une seule
référence (`@v1`) fixe à la fois le Groovy et le bash. `scriptsFrom: 'agent'` reste possible.

## 8. Onboarding d'une collection

1. `meta/runtime.yml` : `requires_ansible: '>=2.16.0'` (ou `>=2.18.0`) ; `galaxy.yml` : `tags`
   (obligatoires), `build_ignore: [Jenkinsfile, .gitlab-ci.yml, reports, dist]` ; `.gitignore` :
   `reports/ dist/ tests/output/`.
2. Fichiers Python : en-tête `from __future__ import (absolute_import, division, print_function)` +
   `__metaclass__ = type` (sanity 2.16 et certification).
3. `.ansible-lint` : `profile: production` (ou absent) ; `changelogs/config.yaml` (antsibull-changelog) ;
   `.yamllint` recommandé.
4. Ajouter le `Jenkinsfile` ou le `.gitlab-ci.yml` minimal (§0, `GUIDE-UTILISATEUR.md`).
   * **Jenkins** : job **multibranche** (pour les PR et le contrôle du changelog), credentials
     `nexus-galaxy-hosted-token` et `spotter-api-token`.
   * **GitLab** : variables masquées `ACI_GALAXY_TOKEN` (protégée) et `SPOTTER_TOKEN`, tags protégés
     `*.*.*`, pipelines de MR (`workflow:rules`).
5. Première exécution sur une branche. Corriger dans l'ordre : garde-fous de certification, lint, sanity.
6. Activer ensuite `integration`, `molecule` et `spotter`, puis `targetEEs` dès que les EE sont dans le
   miroir.

## 9. Migration depuis la v3 (nox)

| v3 (dans le dépôt de la collection) | v4 |
|---|---|
| `noxfile.py`, `ci/` | **à supprimer** (la logique est dans `aci`) |
| `Jenkinsfile` d'environ 200 lignes | `@Library('ansible-ci@v1') _` + `ansibleCollectionPipeline(...)` |
| `.gitlab-ci.yml` d'environ 250 lignes | `include: component …@1` (+ `inputs`) |
| `nox -s sanity-2.21` | `ACI_CORE=2.21 aci sanity` |
| `ANSIBLE_TEST_MODE=venv` | `ACI_TEST_MODE=venv` / `testMode: 'venv'` / `test-mode: venv` |
| `ANSIBLE_CORE_VERSIONS`, `ANSIBLE_CORE_PRERELEASE` | `ansibleCoreVersions` / `ansibleCorePrerelease` (inputs `ansible-core-*`) |
| `ANSIBLE_TEST_PYPI_ENDPOINT`, `ANSIBLE_TEST_IMAGE_MIRROR` | `pypiEndpoint`, `imageMirror` |
| `SPOTTER_ENDPOINT` (variable) | `spotterEndpoint` / `spotter-endpoint` (jeton inchangé) |
| matrice 2.19 → 2.22 | **2.16 + 2.18** (+ 2.20 optionnelle) : à adapter à `requires_ansible` |
| `build_ignore: [ci, noxfile.py, …, .nox]` | `build_ignore: [Jenkinsfile, .gitlab-ci.yml, reports, dist]` |
| image runner avec nox | même image sans nox, avec `/opt/ansible-ci/bin/aci` et Python 3.12 seul (326 Mo au lieu de 403) |

Procédure (une MR par collection) :
1. Supprimer `noxfile.py`, `ci/` et `.nox/`.
2. Remplacer le `Jenkinsfile` ou le `.gitlab-ci.yml`.
3. Ajuster `build_ignore`.
4. Ajouter un fragment de changelog ; l'étape `changelog` l'exige dès cette MR.
5. Corriger ce que les nouveaux contrôles détectent : en-têtes Python pour 2.16, ignores sanity hors
   liste, `.ansible-lint`.

## 10. Agents

| Étape | Pod OpenShift (`restricted-v2`, image runner, sans moteur de conteneurs) | VM `ansible-builder` (podman rootless) |
|---|---|---|
| lint, docs, build, galaxy-importer, certification, changelog, sécurité, spotter, publication | ✔ | |
| sanity/units **rapides** (`--venv`, Python 3.12 pour 2.16 et 2.18) | ✔ (branches, PR/MR) | |
| sanity/units **complètes** (`--docker default`, tous les Python) | | ✔ (branche par défaut, tags, planifié) |
| introspection des EE, intégration, Molecule, POC EE | | ✔ |

### 10.1 Pod Jenkins et runner GitLab
* **Jenkins** : `podTemplate` généré par la bibliothèque à partir de
  `resources/org/corp/ansibleci/pod/runner-pod.yaml`. Il contient les conteneurs `jnlp` et `runner`,
  `runAsNonRoot`, seccomp `RuntimeDefault`, `drop: ALL`, pas d'escalade, aucun `runAsUser` (l'UID est
  attribué par OpenShift) et un `emptyDir` pour `/tmp`. Les images se règlent par `runnerImage` et
  `jnlpImage`, le modèle complet par `podTemplateYaml`, le cloud par `podCloud`. Sans plugin Kubernetes :
  `agentType: 'label'`.
* **GitLab** : runner Kubernetes (tag `ansible-runner`), `privileged = false`, `cap_drop = ["ALL"]`,
  helper `gitlab-runner-helper-ocp` depuis Nexus ; runner `shell` sur la VM (tag `ansible-builder`).
  Voir `infra/gitlab-runner/config.toml.example`.

### 10.2 VM `ansible-builder` : podman rootless (validé)
* ansible-test cherche `docker` puis `podman` (`DOCKER_COMMANDS`), ignore un `docker` qui n'est qu'un alias de podman ; `ANSIBLE_TEST_PREFER_PODMAN=1` inverse l'ordre.
* Les conteneurs de test démarrent systemd (`--systemd always --cgroupns private`) : il faut une **délégation cgroup v2** à l'utilisateur CI (session systemd utilisateur, `loginctl enable-linger`), des plages `/etc/subuid`/`/etc/subgid`, et `XDG_RUNTIME_DIR` pour les jobs lancés sans session logind (runner GitLab `shell`).
* Préparation automatisée : `infra/ansible-builder-vm/site.yml` (podman, python3.12, AC, `/etc/pip.conf`, `registries.conf` Nexus, linger, scripts `aci` dans `/opt/ansible-ci`).
* Une VM est un point unique : en prévoir 2 (labels identiques) et dimensionner les exécuteurs (un job = 2 à 3 conteneurs ; `default-test-container` occupe 1,55 Go).

### 10.3 Options pour se passer de la VM sur OpenShift
| Option | Statut | Évaluation |
|---|---|---|
| Socket hôte / DinD / `privileged` | Interdits par les SCC | Exclu |
| **Podman imbriqué avec user namespaces** (`hostUsers: false`, SCC `nested-container`) | **GA en OCP 4.20** ([release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/release_notes/ocp-4-20-release-notes)), Technology Preview en 4.19 | Piste la plus réaliste. ansible-test lance un conteneur `--privileged --pid host` et des conteneurs systemd : **POC indispensable** (`infra/openshift/nested-podman-pod.poc.yaml`, non validé) |
| buildah | — | Construit des images, ne lance pas de conteneurs de test : hors sujet |
| OpenShift sandboxed containers (Kata) | Produit supporté | Pods dans des micro-VM : il faut des nœuds bare-metal ou la virtualisation imbriquée ; lourd pour de la CI |
| `ansible-test integration --venv/--local` dans le pod | Possible | Seulement pour des cibles qui ne modifient pas le système (API, réseau) |

## 11. Dépôts Nexus à configurer

| Dépôt | Format / type | URL distante | Usage |
|---|---|---|---|
| `pypi-proxy` | PyPI proxy | `https://pypi.org` | ansible-core, ansible-lint, antsibull-*, galaxy-importer, dépendances de tests |
| `pypi-hosted` | PyPI hosted | — | outils internes, wheels patchés |
| `pypi-group` | PyPI group | proxy + hosted | **index unique** : `https://nexus.corp.local/repository/pypi-group/simple` |
| `quay-proxy` | Docker proxy (connecteur dédié, ex. port 8444) | `https://quay.io` | `quay.io/ansible/*-test-container`, `ansible-test-utility-container`, `quay.io/ansible-community/test-image:*` |
| `dockerhub-proxy` | Docker proxy | `https://registry-1.docker.io` | *optionnel* : images de service des cibles d'intégration / Molecule (mysql, postgres, vault…) |
| `ghcr-proxy` | Docker proxy (ex. port 8445) | `https://ghcr.io` | *optionnel* : images d'aide de certaines cibles (ex. `ghcr.io/ansible-collections/*`) |
| `docker-hosted` (+ `docker-group`, ex. port 8443) | Docker hosted / group | — | image de base UBI 9 d'entreprise, image runner, images Molecule internes éventuelles |
| `ansible-proxy` | **Ansible** proxy (Nexus ≥ 3.93.0) | `https://galaxy.ansible.com` | dépendances de collections |
| `ansible-hosted` | Ansible hosted | — | **publication** des collections internes |
| `ansible-group` | Ansible group | proxy + hosted | résolution unique pour `ansible-galaxy` |
| `ubuntu-proxy` | APT proxy | `http://archive.ubuntu.com/ubuntu` | *optionnel* : seulement si des cibles d'intégration installent des paquets dans les conteneurs ansible-test Ubuntu (aucune image n'est construite sur Debian/Ubuntu) |
| `raw-hosted` | Raw | — | *optionnel* : tarballs ansible-core `devel`/`milestone` (si testés, variables `ACI_CORE_SRC_DEVEL` / `ACI_CORE_SRC_MILESTONE`), binaires kind/helm. Les scripts `get-pip` ne sont **plus** nécessaires (§13) |
| `gitlab-registry-proxy` (ex. port 8446) | Docker proxy | `https://registry.gitlab.com` | image helper `gitlab-runner-helper-ocp` pour l'executor Kubernetes sur OpenShift |
| `redhat-registry-proxy` (ex. port 8447) | Docker proxy | `https://registry.redhat.io` (compte de service Red Hat) | **EE AAP** (`ansible-automation-platform-26/ee-minimal-rhel9`…) pour `targetEEs` ; ou Private Automation Hub |
| `rpm-proxy` / dépôts BaseOS-AppStream (+ EPEL 9 optionnel) | Yum proxy | dépôts RHEL 9 / UBI 9 | image de base UBI 9 d'entreprise et image runner (`python3.12` est dans **AppStream**) ; VM `ansible-builder` (podman, python3.12…) ; EPEL seulement si `ShellCheck` en RPM |

Points d'attention Nexus :
* activer les realms **Docker Bearer Token** et **Ansible Galaxy Bearer Token** ([doc Sonatype](https://help.sonatype.com/en/configure-ansible-with-nexus.html)). Le jeton Galaxy Nexus est `base64("user:password")` ;
* le support natif du format Ansible est arrivé avec **Nexus 3.93.0 (04/06/2026)** ([release notes](https://help.sonatype.com/en/sonatype-nexus-repository-3-93-0-release-notes.html)). Sur une version plus ancienne, voir les alternatives du §14 ;
* Docker Engine n'applique `registry-mirrors` qu'à `docker.io`. Pour quay.io et ghcr.io, il faut soit le **re-tag** (§12.2), soit Podman et `registries.conf` (fichier `infra/ansible-builder-vm/templates/registries-nexus.conf`, déployé par le playbook de la VM).

## 12. Images

### 12.1 Image runner (`infra/runner-image/`, détails dans son README)
* `FROM` l'image de base d'entreprise **UBI 9** (`ARG BASE_IMAGE`, défaut `nexus.corp.local:8443/corp/ubi9-corp:9.8`,
  placeholder). L'AC, `/etc/pip.conf` (Nexus) et les dépôts microdnf internes viennent de cette base.
* Ajoute **python3.12** depuis AppStream : il couvre 2.16, 2.18, 2.20 (optionnelle), la certification et
  correspond au Python des EE AAP. python3.14 n'est ajouté que sur demande (`PYTHON_VERSIONS="3.12 3.14"`)
  pour 2.22 / `devel` ; RHEL 9.8 ne fournit pas 3.13. Le `python3` système (3.9) est conservé tel quel.
* Ajoute `git-core`, `openssh-clients`, `tar`, `gzip`, `rsync`, `jq` ; un venv d'outils `/opt/ansible-ci`
  (PyYAML, shellcheck-py) ; les **scripts `aci`** (`/opt/ansible-ci/bin/aci`) ; l'utilisateur `ci`
  (UID 1001, GID 0, HOME en `g=u`, compatible avec un UID arbitraire OpenShift).
* Ni nox, ni moteur/CLI de conteneurs. **326 Mo** (v1.0.1 ; 388 Mo avec python3.14). Tags `2026.MM` et `aci-X.Y.Z`.
* ansible-core n'est pas dans l'image : `aci` crée un venv par série (`~/.cache/ansible-ci/venv`, verrou
  `flock`), depuis Nexus.

### 12.2 Images ansible-test : miroir et re-tag (choix retenu)
ansible-test lit ses images dans `ansible_test/_data/completion/docker.txt`. Ce fichier n'est pas surchargeable, et le tag dépend de la version d'ansible-core :

| ansible-core | `default` (collections) | `base` |
|---|---|---|
| 2.16.19 | `quay.io/ansible/default-test-container:8.12.0` | `base-test-container:5.10.0` |
| 2.18.19 | `default-test-container:10.9.0` | `base-test-container:7.7.0` |
| 2.20.10 (optionnelle) | `default-test-container:v2.20-4` | `v2.20-2` |

En revanche, **ansible-test ne tire pas une image déjà présente localement** (`docker_util.py` : *« Skipping pull of existing image »*). `aci prime-images` (`lib/aci/py/prime_images.py`) exploite ce comportement :
1. lecture de `docker.txt` dans le venv de la série, donc pour la bonne version d'ansible-core ;
2. `podman pull <ACI_IMAGE_MIRROR>/ansible/default-test-container:<tag>` depuis Nexus (`ACI_CONTAINER_ENGINE`) ;
3. `podman tag … quay.io/ansible/default-test-container:<tag>`.

La sémantique de l'alias `default` est ainsi conservée : sanity et units passent sur **toutes** les versions Python cibles de l'image de la série. Avec `--docker <image-perso>`, on n'aurait que la version Python du contrôleur.
Le script tire aussi **`ansible-test-utility-container`**. ansible-test l'utilise à chaque exécution `--docker` pour sonder les cgroups et l'audit, puis pour remonter `/sys/fs/cgroup` (`docker run --pid host --privileged … nsenter`, observé dans les logs). Sans lui, même la sanity échoue en airgap.

*Variante Podman* : `registries.conf` avec un miroir pour `quay.io`, `ANSIBLE_TEST_PREFER_PODMAN=1` et `ACI_IMAGE_MIRROR` (`imageMirror` / `image-mirror`) vide. Le re-tag devient alors inutile.

*Images dérivées* (AC + `/etc/pip.conf` + APT Nexus ajoutés aux images officielles, poussées sous le même tag) : non retenues et plus livrées depuis la v1.0.1. `--pypi-endpoint` suffit pour pip ; à reconsidérer seulement si des cibles d'intégration font de l'`apt` (feuille de route).

## 13. pip dans l'airgap

| Niveau | Mécanisme | Remarque |
|---|---|---|
| Runner et venvs `aci` | `PIP_INDEX_URL` (variable CI) + `/etc/pip.conf` | **Ne jamais** déposer `~/.pip/pip.conf` sur le runner : ansible-test refuse de l'écraser hors conteneur géré (*« Refusing to overwrite existing file »*, `pypi_proxy.py`) |
| Conteneurs ansible-test (contrôleur et cibles) | **`--pypi-endpoint <URL>`** (`pypiEndpoint` / `pypi-endpoint`, ajouté par `aci` en mode docker) | Option masquée (`argparse.SUPPRESS`), mais implémentée et transmise à l'invocation déléguée. ansible-test écrit `~/.pip/pip.conf` (`index-url` + `trusted-host`) dans le conteneur, puis le retire en fin de test |
| `ansible-test --venv` (pods OpenShift) | `/etc/pip.conf` de l'**image de base UBI 9** **uniquement** | ansible-test **ne transmet pas** `PIP_INDEX_URL` à ses venvs (constaté : pip est parti vers l'index de `/etc/pip.conf`). Amorçage de pip par `lib/aci/py/get_pip_offline.py` (ensurepip + Nexus, §12.1) |

Constats des essais :
* **sanity** n'installe rien, car les venvs sont pré-construits dans `default-test-container` (`files/prime.py` → `ansible-test sanity --prime-venvs`) ;
* **units `--requirements`** installe `tests/unit/requirements.txt` **dans le conteneur**. Sans `--pypi-endpoint`, pip part vers `pypi.org` et échoue en airgap ; avec, ça passe. Les deux cas ont été testés ;
* **integration** installe au minimum `requirements/ansible.txt` dans le conteneur contrôleur ;
* `PIP_INDEX_URL` défini dans le job **n'est pas propagé** dans les conteneurs ansible-test ;
* `trusted-host` est posé sur l'hôte de l'index, ce qui **désactive la vérification TLS** pour cet hôte dans les conteneurs de test. C'est acceptable pour un Nexus interne.

## 14. Collections Galaxy (dépendances et publication)

* `ansible.cfg` généré par `aci` (serveurs = `galaxyServerUrl`, `galaxyPublishUrl`), passé **uniquement** à `ansible-galaxy` via `ANSIBLE_CONFIG` pour ne pas perturber ansible-test : `server_list = nexus_group, nexus_hosted`.
* Jetons hors du dépôt : `ANSIBLE_GALAXY_SERVER_<NOM>_TOKEN` (positionné par `aci publish` à partir de `ACI_GALAXY_TOKEN`), ou `_USERNAME` / `_PASSWORD` pour une auth basique. Mécanisme vérifié dans `ansible/config/manager.py`.
* Les dépendances (`galaxy.yml: dependencies`, `tests/requirements.yml`, `tests/unit/requirements.yml`, `tests/integration/requirements.yml`, les conventions observées) sont installées **dans la même racine `ansible_collections`** que la collection, et ansible-test les embarque.
* Publication : `ansible-galaxy collection publish dist/<ns>-<name>-<ver>.tar.gz --server aci_publish`. `--server` accepte un **nom** de `server_list`, vérifié dans `ansible/cli/galaxy.py`.
* Alternatives si Nexus < 3.93 : **Private Automation Hub** (galaxy_ng) ; ou bien tarballs vendus dans un dépôt Nexus *raw* puis `ansible-galaxy collection install <fichier>.tar.gz --offline` (sur des tarballs **locaux**, `--offline` évite tout appel à un serveur de distribution ; l'option ne s'applique ni aux URL distantes ni aux dépôts Git) ; ou encore miroirs Git internes des collections (`git+https://gitlab.corp.local/…`, à la manière des `collection_sources` d'antsibull-nox).

## 15. Validation réalisée (v4, 20/10/2026)

Le banc est le même pour tous les essais :
* Nexus simulé : devpi pour PyPI, Galaxy v3 statique, le tout en HTTPS derrière `nexus.corp.local`
  avec une AC de test ;
* réseau `airgap` **interne**, sans route vers Internet ;
* image runner UBI 9 v4 ;
* UID `1000680000:0`, `--cap-drop ALL`, `no-new-privileges` ;
* collection `corp.demo` (module, filtre, rôle `motd`, Molecule), `requires_ansible: '>=2.16.0'`.

**Scripts `aci`** : `shellcheck` sans aucun avertissement sur tous les scripts. `ci-scripts/tests/smoke.sh`
est OK : série par défaut, spécificateurs pré-version et GA, `ACI_CORE_PIN`, 2.16 → python3.12, code 3
pour une pré-version. `ci-scripts/tests/guards.sh` : **14/14** (ignores hors liste, dérogation,
`.ansible-lint`, `requires_ansible` 2.19 refusé, changelog avec et sans fragment, avec label).

**Exécutions réelles dans l'image runner, en airgap** :
* `lint`, `docs`, `build`, `importer`, `security-scan`, `spotter` (export) ;
* sanity sur **2.16, 2.18 et 2.20** en Python 3.12 ; units sur 2.16 et 2.18 ;
* `certification` : garde-fous 0 erreur, galaxy-importer 0.4.39 OK, ansible-lint 26.4.0 profil
  `production` « passed » ; `sanity-cores` → `2.16 2.18 2.20`.

**Introspection des EE**, avec podman réel sur l'hôte du banc et des EE *simulées* (UBI 9 + Python 3.12 +
ansible-core 2.16.19 / 2.18.19, `ENTRYPOINT /bin/false`, `USER 1000`) :
* matrice correcte ;
* `requires_ansible: '>=2.18.0'` avec une EE 2.16 → échec immédiat ;
* image sans ansible → message clair ;
* Python hors plage → refusé.

**Jenkins 2.580.1 réel** (`tests/jenkins-e2e/run-e2e.sh`). La bibliothèque est chargée depuis un dépôt git local
(`defaultVersion v1`, tag `v1.0.0`) ; l'agent statique `ansible-runner` est l'image runner + JDK 21, en
airgap ; mode `venv`.

| Job | Résultat | Ce qui est démontré |
|---|---|---|
| `corp-demo` (Jenkinsfile de 7 lignes, `ansibleCoreOptional: ['2.20']`) | **SUCCESS**, 130 s | 7 contrôles statiques en parallèle (dont certification et changelog ignoré hors PR) ; 4 branches parallèles générées : 2.16, 2.18, 2.20 [non bloquant], certification sanity 2.20 py3.12 ; 2.16 et 2.18 dédupliquées ; JUnit 96 tests (1 constat MEDIUM informatif du scanner) |
| `corp-demo-ee` (`targetEEs`, 2 EE) | **SUCCESS**, 106 s | introspection puis branches « ansible-core 2.16.19 py3.12 (ee-minimal-rhel9:2.16) » et « 2.18.19 » épinglées sur la version exacte |
| `corp-demo-ee-bad` | **FAILURE attendu** dès l'introspection | « Python 3.10 hors plage contrôleur d'ansible-core 2.18 (3.11, 3.12, 3.13) » ; aucune autre étape lancée |
| `corp-demo-scripted` (`@v1.0.0`, étapes granulaires) | **SUCCESS** | `withAnsibleCi`, `withAnsibleCore`, `ansibleCertification(sanityCores: true)` → `[2.16, 2.18, 2.20]`, `ansibleChangelogCheck` (hors PR), build, importer, sanity, units, sécurité, Spotter export |
| `bad-config` | **FAILURE attendu** | toutes les erreurs listées en une fois : « paramètre inconnu 'lnt' (vouliez-vous dire 'lint' ?) », type, `testMode`, `spotterEndpoint` |
| `bad-step` | **FAILURE attendu** | « paramètre inconnu 'cor' (vouliez-vous dire 'core' ?) » |
| `matrix-dynamic` | **FAILURE attendu** | preuve que `matrix` refuse des axes calculés : « Expected string literal but got ${cores} » |

Dans le job `corp-demo-ee`, l'introspection passe par un **faux `podman`** (`tests/jenkins-e2e/podman-shim.sh`),
parce que l'agent de test n'a pas de moteur de conteneurs. Ce shim exécute le vrai `ansible --version` d'un
venv de la version de l'EE. Le vrai `podman run` des EE a été testé à part, sur l'hôte.

**Bibliothèque Jenkins, hors Jenkins** : `test/unit/run.sh` → **14/14**. Les tests couvrent les défauts
AAP, la validation, la matrice, `ansibleCoreOptional`, l'exclusivité de `targetEEs`, `parseEeMatrix`,
`applyEeMatrix` et `toEnv`. `test/validate-pod.sh` : schéma Kubernetes 1.33 strict + contraintes
`restricted-v2` OK.

**Composant GitLab, sans instance GitLab** :
* `tests/validate.sh` **16/16** :
  * rendu des inputs minimal, complet et banc (v1.0.0 ; minimal et complet depuis v1.0.1) ;
  * en-tête `spec` et rendu valides selon le **schéma officiel GitLab** (`ci.json` de 19.6.0-pre) ;
  * inputs invalides refusés : input inconnu, type, `options`, `regex` ;
  * jobs attendus par contexte : branche → venv ; branche par défaut et tag → docker ; MR → changelog ;
    tag → publication ;
  * exemples utilisateur valides ;
  * `ACI_EXPECTED_VERSION` = `ci-scripts/VERSION`.
* `tests/gitlab-jobs/run-jobs.sh` exécute **réellement** les scripts des jobs rendus, chacun dans un clone neuf, dans
  l'image runner, en airgap, avec un UID arbitraire :
  * tous OK : `aci-ee-introspect` (podman, EE simulées), `aci-certification`, `aci-lint`, `aci-docs`,
    `aci-build`, `aci-security`, `aci-sanity-venv` 2.16 et 2.18 (version exacte et Python de l'EE lus
    dans l'artefact), `aci-units-venv` 2.16 et 2.18, `aci-optional-cores` (2.20, sanity + units),
    `aci-certification-sanity` (2.20 seule, en Python 3.12) ;
  * `aci-changelog` sur MR : sans fragment → échec, avec fragment → OK ;
  * `aci-ee-introspect` avec `ansible-core-versions` ≠ séries des EE → échec avec la valeur à mettre.
* Trois défauts réels trouvés et corrigés grâce à ces essais (pièges 22 à 24).

**Infra** : playbook de la VM, `--syntax-check` + ansible-lint `production` OK. Les tâches d'installation
d'`aci` ont été exécutées en local (`aci version` → `aci 1.0.0`).

**Révision 1.0.1 (21/10/2026, nettoyage)** : shellcheck sur tous les scripts, `smoke.sh` 11/11 (dans
l'image), `guards.sh` 14/14, `test/unit/run.sh` 14/14, `validate-pod.sh` OK, `validate.sh` 15/15 (schéma
GitLab), extraits du guide et `.gitlab-ci.yml` de `corp.demo` valides, `tools/sync.sh --check` OK, ansible-lint
`production` sur `site.yml`. Image runner reconstruite avec Python 3.12 seul (**326 Mo**) : `aci version` →
1.0.1 ; 2.16 et 2.20 → python3.12 ; 2.22 → arrêt explicite (pas de Python ≥ 3.13). `aci units` et
`aci sanity` 2.20 en Python 3.12 OK dans cette image (index PyPI public, hors banc airgap). Le banc Jenkins
de bout en bout n'a **pas** été relancé pour 1.0.1 (changements : préférence Python, défauts Molecule,
documentation, emplacement des fichiers de test).

**Historique (v1 à v3.1, nox)** : voir `git show v3-nox:PROPOSITION.md` §11. Ces essais ont
validé en particulier la VM podman rootless en mode docker (sanity, units, intégration, Molecule) et
l'export Spotter hors réseau.

## 16. Limites et points non testés

* **Aucun cluster OpenShift ni aucune instance GitLab** sur le banc :
  * le pod Jenkins `restricted-v2` est validé par schéma et par émulation (UID arbitraire, `cap-drop`),
    pas sur un cluster ;
  * le composant est validé par le schéma officiel et par un rendu émulé (`render.py`), sans CI Lint ni
    pipeline GitLab réels. À faire en premier : CI Lint du composant + pipeline du projet composant ;
  * `@1` (version partielle) et la publication dans le catalogue ne sont pas testés.
* **Jenkins** : seul le mode **venv** sur agent statique a été rejoué en v4. Le mode **docker** (VM podman)
  passe par les mêmes commandes `aci`, validées en v2/v3, mais n'a pas été relancé depuis Jenkins v4.
  L'intégration et Molecule n'ont pas été relancés en v4 (les défauts Molecule `ubuntu2404 fedora40`
  de 1.0.1 et l'inventaire de `corp.demo` épinglé sur les tags 2.18 ne sont pas exécutés). Le contrôle du changelog sur une vraie PR
  multibranche n'est pas testé dans Jenkins ; il l'est par `guards.sh` et `run-jobs.sh` (MR).
* **EE** : introspection testée avec des EE **simulées**, pas avec les images `registry.redhat.io`
  (pas d'accès authentifié). Le numéro exact de core dans `ansible-automation-platform-26/ee-*` reste à
  constater chez vous ; c'est justement ce que fait l'introspection. L'étape **POC `ee-units`** (units
  dans l'EE, `--venv --venv-system-site-packages`, `--userns=keep-id`) est écrite mais **non exécutée**.
* **Certification** : reproduction fidèle des versions et options, mais le checker officiel lance la
  sanity avec `ansible-test-gh-action` en docker. Ici, la sanity de certification suit le mode de la
  matrice (venv sur les branches, docker sur main et les tags). La règle d'ignores est appliquée telle
  que la définit ansible-lint 26.4.0 ; la tolérance réelle des relecteurs Red Hat n'est pas connue.
* **Spotter** : jamais exécuté contre une vraie instance privée (export uniquement).
* GitLab : pas de cache de venvs sans volume persistant (premier job d'une série : environ 30 à 60 s de
  pip depuis Nexus).

## 17. Feuille de route (étude Red Hat, priorités P2 et P3)

Faits en v4 : tout le **P1**, c'est-à-dire la matrice AAP, `targetEEs` et son introspection, la
certification et les garde-fous. Seuls les tests units et intégration dans l'EE restent en POC. Le **P2-8**
(fragment de changelog) est aussi fait.

| # | Élément | Priorité | Proposition |
|---|---|---|---|
| 3 | Units et intégration **dans l'image de l'EE** | P1 (POC) | Valider `ee-units` chez vous (VM + miroir registry.redhat.io), puis en conteneur additionnel du pod OpenShift |
| 5 | Configuration galaxy-importer **partagée avec le Private Automation Hub** (`hub_galaxy_importer`) | P1/P2 | `share/aci/galaxy-importer.cfg` devient la source, déployée aussi sur le hub |
| 9 | **Lint des métadonnées** : version ≥ 1.0.0 au tag, `license`, `requirements.txt` sans pin ni ansible-core, `bindep.txt`, `tests/config.yml` (`python_requires`), liens README absolus | P2 | nouveau contrôle dans `cert_guards.py` (la borne `requires_ansible` est déjà vérifiée) |
| 10 | Dépendances résolues **certified/validated → community** (hub puis Nexus) | P2 | `galaxyServerUrl` multiple dans l'`ansible.cfg` généré |
| 11 | Étape **`ee-build`** : `ansible-builder build` depuis `ee-minimal` avec le tarball | P2 | VM ; prouve que `requirements.txt` et `bindep.txt` s'installent |
| 12 | **Smoke test `ansible-navigator run --eei <EE>`**, collection testée en tête du chemin | P2 | VM, après `ee-build` |
| 13 | Molecule ansible-native, modèle `cisco.ios` | P2 | déjà le format de `corp.demo` ; à généraliser dans le guide |
| 14 | Publication vers le **staging** du Private Automation Hub, puis approbation et signature ; quality gate sécurité avant promotion | P3 | `galaxyPublishUrl` = staging, promotion hors CI |
| 15 | **Nocturne** sur le tag EE roulant et la prochaine série de core (2.20, puis 2.21 et `devel`) | P3 | job planifié avec `targetEEs` roulants + `ansibleCoreOptional` |
| 16 | `changedTargetsOnly` (`ansible-test integration --changed`) | P3 | paramètre d'intégration |
| — | Passage à **AAP 2.7** (2.18 + 2.20 par défaut) | — | **v2** de la bibliothèque (changement de défaut, donc majeure) |

## 18. Pièges identifiés (✔ = rencontré pendant les essais)

1. ✔ **Arbre de travail dans le dépôt git** : si `ansible_collections/<ns>/<name>` est créé sous le dépôt (ex. un sous-dossier du checkout), ansible-test remonte jusqu'au `.git` parent, liste les fichiers via git (ignorés) et affiche *« WARNING: All targets skipped »* **en sortant en succès**. `aci` travaille donc dans `$TMPDIR/aci-<uid>/<repo>` (`ACI_WORK`).
2. ✔ **`--network host` sur le conteneur du job** : ansible-test réutilise ce réseau pour ses conteneurs et plante (*« Missing IP address for container »*). Utiliser le réseau bridge par défaut ou un réseau dédié.
3. ✔ **`ssh-keygen` absent** du runner : *« Required program "ssh-keygen" not found »*.
4. ✔ **`ansible-test-utility-container`** non mis en miroir : toute exécution `--docker` en a besoin.
5. ✔ **Shebang dans un script `.py` non-module** du dépôt (scripts CI dans le dépôt de la collection : il n'y en a plus en v4) : test sanity `shebang` en échec. Les scripts CI sont inclus dans la sanity.
6. Les **tags d'images changent avec les versions correctives** d'ansible-core (ex. `v2.21-3` → `v2.21-4`). `aci prime-images` les lit dynamiquement. Pour figer, épingler la version corrective d'ansible-core.
7. **antsibull-nox / tox-ansible / ansible-test-gh-action** téléchargent ansible-core depuis GitHub (`archive/stable-X.Y.tar.gz`). Ne pas les utiliser tels quels en airgap. Avec antsibull-nox, il faudrait passer `ansible_core_source="pypi"` par l'API Python, car le TOML ne l'expose pas.
8. **ansible-lint sans `--offline`** tente d'installer les `requirements.yml` et de rafraîchir les schémas.
9. Les **`--remote`** (VM Red Hat Core CI) n'existent pas on-prem. Les remplacer par des conteneurs de distribution, ou par des VM internes (`ansible-test integration --target ssh:<user>@<host>[:<port>]`, syntaxe vérifiée dans `ansible-test integration --help`).
10. **Cibles d'intégration** qui font `apt`/`dnf`/`pip` : `--pypi-endpoint` couvre pip ; pour `apt`/`dnf`, des rôles `setup_*` configurables (miroirs Nexus) ou, à défaut, des images dérivées (non livrées).
11. **Socket Docker = root sur l'agent** : réserver des runners/agents dédiés et éphémères. ansible-test lance un conteneur `--privileged --pid host` (sonde cgroup).
12. **`build_ignore`** dans `galaxy.yml` : exclure `Jenkinsfile`, `.gitlab-ci.yml`, `reports/`, `dist/` de l'artefact.
13. **galaxy-importer** écrit `importer_result.json` dans le répertoire courant. `aci importer` l'exécute dans `reports/galaxy-importer/`.
14. ✔ **podman rootless sans délégation cgroup** : les conteneurs ansible-test (systemd) meurent au démarrage (*« Failed to create /init.scope control group: Permission denied »*, puis *« can only create exec sessions on running containers »*). Corrigé en donnant à l'utilisateur un sous-arbre cgroup v2 délégué (session systemd : `loginctl enable-linger`).
15. ✔ **`ansible-test --venv` en airgap** : télécharge `get-pip-<v>.py` depuis `ci-files.testing.ansible.com` et ignore `PIP_INDEX_URL` → `get_pip_offline.py` déposé par `aci` + `/etc/pip.conf` (§12.1, §13).
21. **UBI 9** : `python3` = 3.9 ; AppStream a 3.11, 3.12 et 3.14 mais **pas 3.13** (3.12 pour 2.16 → 2.21 ; 3.14 seulement pour 2.22+) ; pas de ShellCheck hors EPEL ; chemin AC = `/etc/pki/tls/certs/ca-bundle.crt` (pas `/etc/ssl/certs/ca-certificates.crt` de Debian), corrigé dans `SPOTTER_CACERT`.
16. ✔ **ansible-security-scanner n'a pas d'option d'exclusion** : lancé à la racine, il analysait `.nox/` en v3 (286 fichiers au lieu de 21). `aci security-scan` scanne une copie propre.
17. ✔ **galaxy-importer** exige un `README.md` par rôle ; **antsibull-docs** exige `description` dans `meta/argument_specs.yml` (erreurs réelles détectées sur la démo).
18. ✔ **Spotter CLI 6.6.0** : `--ansible-version` n'accepte que 2.0 → 2.20 (`SPOTTER_ANSIBLE_VERSION`, défaut 2.20) ; code retour 1 dès qu'un résultat reste après filtrage `--display-level` (défaut retenu : `error`).
19. ✔ **Faux positif ansible-security-scanner** (règle `linux_cap_bpf_granted_to_container_or_service` déclenchée par `podman_container` + `systemd`) : suppression ciblée `# nosec: <rule_id> reason="…"` (un `# nosec` nu ne supprime rien).

22. ✔ **`cache:` GitLab dans le projet** : lint, yamllint et sanity analysent les venvs mis en cache sous le checkout (466 erreurs ansible-lint, `line-endings` sur les `RECORD`). Le composant n'utilise pas `cache:` ; volume persistant sur `~/.cache/ansible-ci` à la place.
23. ✔ **Input GitLab `array` interpolé seul dans `variables:`** : il reste un tableau YAML, refusé par le schéma (« is not of type 'boolean', 'number', 'string' »). Le composant écrit `"series $[[ inputs.ansible-core-versions ]]"` et `aci` extrait les séries.
24. ✔ **Checkout appartenant à un autre UID** (pod GitLab, conteneur) : `git` refuse le dépôt (*dubious ownership*). `aci changelog-check` passe `-c safe.directory=<checkout>` (portée « ligne de commande », respectée par git) sans modifier `~/.gitconfig`.
25. ✔ **ansible-core 2.16** : la sanity exige l'en-tête `from __future__ import (absolute_import, division, print_function)` + `__metaclass__ = type` dans les modules et tests Python (exigence aussi de la certification).
26. ✔ **Venvs ansible-test en parallèle sur un même agent** (`~/.ansible/test/venv` partagé) : « No such file … pip-25.2.dist-info ». `aci` donne un `HOME` par série ansible-core, protégé par `flock`.
27. ✔ **Jenkins `matrix`** : valeurs d'axes littérales uniquement (« Expected string literal but got ${cores} ») → branches `parallel` générées par la bibliothèque.

## 19. Sécurité et SBOM
* Scanners Ansible : §20 (ansible-security-scanner en local, bloquant à partir de HIGH ; Steampunk
  Spotter sur instance privée).
* ansible-lint profil `production` et garde-fous de certification (§5). `CHECK_REQUIRED_TAGS`.
* Bibliothèque Jenkins **globale** : seuls les mainteneurs CI y écrivent. Les Jenkinsfile restent dans la
  sandbox. Secrets uniquement par credentials ou variables masquées, jamais en paramètre ou en input.
* Nexus Firewall / IQ sur les dépôts proxy. Versions figées (`share/aci/constraints.txt`,
  `certification.env`), images datées.
* À prévoir : SBOM de l'artefact (`syft dist/*.tar.gz`) et `pip-audit` (jobs non bloquants) ; signature
  des collections avec le Private Automation Hub (feuille de route 14).

## 20. Scanners de sécurité

### 20.1 « ansible-security-scanner » — identification
* Le nom correspond exactement au paquet PyPI [**ansible-security-scanner**](https://pypi.org/project/ansible-security-scanner/) (0.1.41 du 25/08/2026, Apache-2.0, dépôt [cpeoples/ansible-security-scanner](https://github.com/cpeoples/ansible-security-scanner)) : analyse statique des YAML (playbooks, rôles, collections), **1 165 motifs** (31 fichiers) d'après l'outil lui-même, sorties SARIF / JUnit / GitLab SAST / CycloneDX. Retenu comme candidat le plus probable.
* **Incertitude** : projet jeune (créé le 29/04/2026), **un seul mainteneur** (125 commits), 11 étoiles, versions 0.1.x. Autres outils possibles derrière ce nom générique : [KICS](https://github.com/Checkmarx/kics) (Checkmarx, requêtes Ansible, v2.2.0 du 17/09/2026, binaire/conteneur), [ansible-risk-insight](https://pypi.org/project/ansible-risk-insight/) (0.2.11), les règles de sécurité d'ansible-lint. À confirmer avec l'équipe sécurité.
* **Verdict airgap : ✅ 100 % local.** Dépendances `httpx`, `jinja2`, `pyyaml`. Seules les options `--github-comment` / `--gitlab-comment` font des appels réseau (API GitLab interne via `CI_SERVER_URL`). Exécuté dans un namespace réseau vide : OK.
* Intégration (`aci security-scan`) : copie propre de la collection (pas d'option d'exclusion), SARIF + GitLab SAST en `--exit-zero`, puis passe JUnit **bloquante** (code ≠ 0 si HIGH/CRITICAL ; `--severity` ne filtre que l'affichage). Sur la démo, un faux positif a été supprimé par `# nosec: <rule_id> reason="…"`. Sur community.sops : 25 constats dont 1 CRITICAL a priori faux positif (bindep). Prévoir une phase de calibrage et une allowlist (`--allowlist`).

### 20.2 Steampunk Spotter — instance privée
* CLI [**steampunk-spotter**](https://pypi.org/project/steampunk-spotter/) 6.6.0 (14/10/2026), installée depuis le proxy PyPI Nexus (`share/aci/requirements-security.txt`, version figée).
* **L'analyse se fait côté serveur** : la CLI extrait tâches et métadonnées puis les envoie à l'API. Sans serveur, seul `--export-payload` fonctionne (*« this operation is fully offline. No actual scan was executed »*).
* **Verdict airgap : ✅ faisable avec l'instance Spotter on-prem** ([installation on-prem](https://spotter.steampunk.si/docs/onprem/), conçue pour l'airgap : installeur avec podman portable, licence, LDAP, TLS d'entreprise). ❌ Impossible avec le SaaS.
* Configuration vérifiée dans le code de la CLI (`spotter/client/utils.py`) :

| Besoin | Option / variable |
|---|---|
| Endpoint privé | `--endpoint` ou **`SPOTTER_ENDPOINT`** (ex. `https://spotter.corp.local/api`) ; sinon `~/.config/steampunk-spotter/spotter.json`, puis le SaaS par défaut |
| Jeton | `--token` ou **`SPOTTER_TOKEN`** (alias `SPOTTER_API_TOKEN`) ; ou `SPOTTER_USERNAME`/`SPOTTER_PASSWORD` |
| AC interne | `--cacert` ou **`SPOTTER_CACERT`** (`spotterCaCert`, défaut : bundle système) ; `-k`/`SPOTTER_INSECURE` à proscrire |
| Proxy HTTP | la CLI utilise `requests` : `HTTPS_PROXY`/`NO_PROXY` standards s'appliquent si nécessaire |
| Version ciblée | `--ansible-version` limité à 2.0 → 2.20 dans la CLI 6.6.0 → `spotterAnsibleVersion` / `spotter-ansible-version` = 2.20 |
| Rapports | `--junit-xml`, `--sarif` ; `--display-level error` ; code retour 1 s'il reste des résultats |

* **Flux réseau** : agent CI (pod OpenShift / runner) → instance Spotter privée, **HTTPS 443 uniquement**. Vérifié : avec un endpoint privé, la CLI n'appelle que cet hôte (`/api/v3/auth/verify/`, `/v2/…`, `/v3/configuration/`). Les URL `spotter.steampunk.si` restantes ne sont que des liens affichés (`--no-docs-url` les retire). Aucun flux vers Internet depuis la CI. Les flux propres à l'instance (mises à jour, licence) sont à confirmer avec l'éditeur.
* Pipelines : jeton dans le credential Jenkins `spotter-api-token` / variable GitLab masquée `SPOTTER_TOKEN` ; non bloquant au départ (`spotterBlocking: false`, `spotter-allow-failure: true`).
* Confidentialité : le payload contient les tâches **et leurs valeurs** (`--exclude-values`, `--exclude-metadata`, `--exclude-environment` réduisent l'envoi ; les secrets détectés sont masqués sauf `--skip-detect-secrets`). Sans enjeu majeur vers une instance interne.

## 21. Questions fréquentes

### 21.1 Pourquoi Molecule n'est-il pas le moteur principal ? Est-il abandonné ?
**Non, Molecule n'est ni abandonné ni déprécié.**
* Dépôt [ansible/molecule](https://github.com/ansible/molecule/releases) très actif : v26.10.0 le 12/10/2026, une version par mois environ (26.2 → 26.10 en 2026). Molecule fait partie d'[ansible-dev-tools](https://pypi.org/project/ansible-dev-tools/) (26.10.0 du 12/10/2026), la boîte à outils de développement maintenue par Red Hat.
* Ce qui a changé : depuis **Molecule 25.9.0 (15/09/2025)**, la configuration **« ansible-native »** est la voie recommandée ([doc](https://docs.ansible.com/projects/molecule/configuration/)) : plus de *driver*, des playbooks `create.yml`/`destroy.yml` écrits avec des collections normales (`containers.podman`, `amazon.aws`…), l'inventaire Ansible natif, la découverte des scénarios dans `extensions/molecule/` des collections, `shared_state`. Les drivers docker/podman/vagrant/… vivent dans [molecule-plugins](https://pypi.org/project/molecule-plugins/) (26.10.12) et sont documentés comme [« pre ansible-native »](https://docs.ansible.com/projects/molecule/pre-ansible-native/). Constat sur 26.10.0 : `molecule test --help` ne propose plus que `-d [default]`.
* **ansible-test et Molecule ne testent pas la même chose** :

| | ansible-test | Molecule |
|---|---|---|
| Cible | plugins/modules d'une collection | rôles, playbooks, scénarios multi-nœuds |
| Tests | sanity (exigée par Galaxy / Automation Hub / certification), units, cibles d'intégration | converge → **idempotence** → verify sur de vrais OS |
| Environnement | images officielles maîtrisées (matrice Python) | ce que l'on crée (conteneurs systemd, VM, cloud, équipements) |

* **Usage réel** (ANALYSE §1) : **4 des 23 collections étudiées**. community.zabbix et community.grafana pour leurs **rôles** ; cisco.ios et ansible.scm comme harnais d'intégration. Aucune ne remplace ansible-test par Molecule.
* **Recommandation** : ansible-test reste obligatoire ; **Molecule en étape optionnelle** dès qu'il y a des rôles, du multi-nœuds, du systemd ou de l'idempotence à prouver. Implémenté : `moleculeTest` / job `aci-molecule` (`aci molecule`, ignoré sans `extensions/molecule`), exécutée sur la VM `ansible-builder` en podman rootless, scénarios ansible-native (`exemple-collection/corp.demo/extensions/molecule`). Les cibles réutilisent les **images de distribution ansible-test** déjà en miroir (systemd inclus), tirées du Nexus par `aci`.

### 21.2 Pourquoi abandonner nox ? Pourquoi bash + Groovy/YAML ?
* Les équipes connaissent Jenkins (Groovy déclaratif et scripté) et GitLab CI. Elles ne connaissent pas
  nox. Avec un `noxfile.py` copié dans chaque dépôt, chaque correction devait être reportée dans N dépôts.
* Les bibliothèques centrales (Shared Library et composant) sont le mécanisme **natif** de réutilisation
  de chaque outil : versionnées, documentées dans l'outil (aide des étapes, catalogue CI/CD), validées
  avant l'exécution.
* La logique « métier » reste en **un seul exemplaire**, en bash (`aci`), sans dépendance Python pour
  orchestrer. Seuls quelques petits helpers Python sont appelés (lecture des images ansible-test, EE,
  garde-fous). Elle est testable avec shellcheck et des tests de fumée.
* Ce qu'on perd : l'exécution « `nox -s …` » en local. Elle est remplacée par
  `ACI_CORE=2.18 /opt/ansible-ci/bin/aci sanity`, dans l'image runner ou sur la VM.
* antsibull-nox et tox-ansible restent écartés en airgap (installation d'ansible-core depuis GitHub).
  Voir `git show v3-nox:PROPOSITION.md` §15.2.

### 21.3 Que contiennent les images ansible-test pré-chargées ?
Elles sont **choisies par ansible-test**, pas par nous : `ansible_test/_data/completion/docker.txt` associe des alias aux images. Chaque version d'ansible-core a ses tags. `aci prime-images` lit ce fichier dans le venv de la série.

| Famille | Contenu | Utilisée par | Taille amd64 (compressée ; décompressée) |
|---|---|---|---|
| `base-test-container` | Ubuntu, **toutes les versions Python** cibles supportées par la série, PowerShell 7.6, systemd, sshd, outils de build | base des deux suivantes ; alias `base` | `v2.21-4` : 462 Mo |
| `default-test-container` | base + **requirements sanity/units pré-installés** par version de Python (venvs `sanity.*` amorcés par `prime.py`, `get_pip_25_2.py` en cache) | `--docker default` pour une **collection** (`context=collection`) | `v2.21-4` : 565 Mo ; **1,55 Go** (Ubuntu 24.04.4 constaté au boot) |
| `ansible-core-test-container` | idem, réglé pour tester ansible-core lui-même | `context=ansible-core` (inutile ici) | — |
| `ubuntu-test-container`, `fedora-test-container`, `alpine-test-container` | une distribution, **une** version de Python, systemd (sauf alpine) | `integration --docker ubuntu2404 / fedora40 / alpine320…` (alias de 2.18), cibles Molecule | Ubuntu 24.04 : 242 Mo ; 666 Mo — Fedora 43 : 252 Mo ; 653 Mo — Alpine 3.23 : 158 Mo |
| `ansible-test-utility-container` | utilitaires de sonde (audit, cgroup) | **chaque** exécution `--docker` | 4 Mo ; 9 Mo |
| `http-test-container` / `pypi-test-container` / `acme-test-container` | serveur HTTP de test, proxy PyPI, ACME | cibles `needs/httptester`, `--pypi-proxy`, plugin cloud ACME | 33 Mo / 33 Mo / — |

Tags par version d'ansible-core (relevés le 20-21/10/2026 dans `docker.txt` et `docker_util.py` des versions installées ; 2.16 et 2.18 = matrice par défaut) :

| ansible-core | default / base | Ubuntu / Fedora / Alpine | utility |
|---|---|---|---|
| 2.16 | `default-test-container:8.12.0` / `base:5.10.0` | `ubuntu2204-test-container:6.3.0`, `alpine3-test-container:6.3.0` (pas de Fedora ni d'Ubuntu 24.04) | 2.0.0 |
| 2.18 | `default-test-container:10.9.0` / `base:7.7.0` | `ubuntu2204/2404-test-container:8.1.0`, `fedora40-…:8.1.0`, `alpine320-…:8.1.0` | 3.1.0 |
| 2.20 | `v2.20-4` / `v2.20-2` (3.9 → 3.14) | `ubuntu-test-container:24.04-v2.20-1`, `fedora-…:42-v2.20-1`, `alpine-…:3.22-v2.20-1` | 3.4.0 |
| 2.21 | `v2.21-4` / `v2.21-4` (3.9 → 3.14) | `24.04-v2.21-2`, `fedora 43-v2.21-2`, `alpine 3.23-v2.21-2` | 3.5.0 |
| 2.22 | `v2.22-8` / `v2.22-8` (3.9 → 3.15) | `24.04-v2.22-4`, `26.04-v2.22-4`, `fedora 44-v2.22-4`, `alpine 3.24-v2.22-4` | — |

Les lignes 2.21 et 2.22 sont données pour préparer les séries suivantes. Budget Nexus indicatif pour 3 séries : environ 2,5 Go compressés (3 × default + 2 distributions + utilitaires). Sources : [base-test-container](https://github.com/ansible/base-test-container), [default-test-container](https://github.com/ansible/default-test-container), API `quay.io/v2`.
