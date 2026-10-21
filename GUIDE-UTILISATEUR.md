# Guide utilisateur : CI d'une collection Ansible (Jenkins ou GitLab)

Ce guide s'adresse aux équipes qui développent des collections. Pour le détail technique, voir
[PROPOSITION.md](PROPOSITION.md).

## 1. Avant de commencer (une fois par collection)

* `meta/runtime.yml` : `requires_ansible: '>=2.16.0'`. AAP 2.6 supporte ansible-core 2.16 et 2.18. Une
  borne à 2.19 est refusée, car 2.19 n'a été qu'une tech preview.
* `galaxy.yml` :
  * `tags:` doit contenir au moins un tag (exigé par la certification) ;
  * `build_ignore: [Jenkinsfile, .gitlab-ci.yml, reports, dist]`.
* `.gitignore` : `reports/`, `dist/`, `tests/output/`.
* Modules, plugins et tests Python : ajouter l'en-tête exigé par la sanity 2.16 et par la certification :
  ```python
  from __future__ import (absolute_import, division, print_function)
  __metaclass__ = type
  ```
* `.ansible-lint` : `profile: production` (ou pas de profil). Ne mettez aucune règle obligatoire en
  `skip_list` et n'excluez ni `plugins/` ni `roles/`.
* `changelogs/config.yaml` (antsibull-changelog). Chaque PR/MR qui modifie la collection ajoute un
  fragment `changelogs/fragments/<num>-<sujet>.yml` :
  ```yaml
  minor_changes:
    - hello - ajout de l'option ``greeting``.
  ```
  Exemption : mettre le label ou le mot **`skip-changelog`** dans le titre de la PR/MR.
* `tests/sanity/ignore-2.16.txt` (et suivants) : seules les entrées autorisées par la certification sont
  acceptées. Une dérogation exceptionnelle se trace par un commentaire `# aci-derogation: <motif>` sur la
  ligne.

## 2. Jenkins

Créez un job **Multibranch Pipeline** sur le dépôt. Il est nécessaire pour les PR et pour le contrôle du
changelog.

### 2.1 Jenkinsfile minimal

```groovy
@Library('ansible-ci@v1') _

ansibleCollectionPipeline()
```

Ce Jenkinsfile lance :
* lint, docs, build + galaxy-importer, scan de sécurité, certification Red Hat ;
* fragment de changelog sur les PR ;
* sanity et units sur ansible-core 2.16 et 2.18, en Python 3.12 ;
* publication sur Nexus lors d'un tag dont le nom est égal à la version de `galaxy.yml`.

### 2.2 Jenkinsfile complet (exemples d'options courantes)

```groovy
@Library('ansible-ci@v1.0.0') _          // version figée ; '@v1' = dernière 1.x

ansibleCollectionPipeline(
    // Matrice : AAP 2.6 (défaut) + 2.20 non bloquante pour préparer AAP 2.7
    ansibleCoreVersions : ['2.16', '2.18'],          // toujours entre quotes
    ansibleCoreOptional : ['2.20'],
    // ...ou bien la matrice dérivée des EE réellement utilisées (remplace ansibleCoreVersions) :
    // targetEEs : ['hub.corp.local/ansible-automation-platform-26/ee-minimal-rhel9:latest',
    //              'hub.corp.local/ansible-automation-platform/ee-minimal-rhel9:2.18'],

    // Étapes optionnelles
    integration      : true,
    integrationImages: ['default', 'ubuntu2404'],
    molecule         : true,
    moleculeImages   : ['ubuntu2404', 'fedora40'],
    spotter          : true,
    spotterEndpoint  : 'https://spotter.corp.local/api',
    spotterBlocking  : false,

    // ansible-test
    testMode         : 'auto',            // venv (pod) sur les branches, docker (VM) sur main/tags
    fullTestBranches : ['main', 'stable-1'],
    sanityArgs       : '',
    coverage         : false,

    // Seuils
    securityFailOn   : 'high',
    changelogSkipToken: 'skip-changelog',

    // Divers
    timeoutMinutes   : 120,
    extraEnv         : [MY_TEST_ENDPOINT: 'https://api.corp.local'],
)
```

Toute faute de frappe arrête le build tout de suite, avec la liste des erreurs. Exemple :
`paramètre inconnu 'lnt' (vouliez-vous dire 'lint' ?)`. La liste complète des paramètres est dans
*Pipeline Syntax > Global Variables Reference > ansibleCollectionPipeline*.

### 2.3 Pipeline scripté (étapes à la carte)

```groovy
@Library('ansible-ci@v1') _

node('ansible-runner') {
    checkout scm
    withAnsibleCi(ansibleCoreVersions: ['2.16', '2.18']) {
        stage('build')         { ansibleCollectionBuild(); galaxyImporter() }
        stage('certification') { ansibleCertification() }
        stage('tests') {
            parallel '2.16': { withAnsibleCore('2.16') { ansibleTestSanity(); ansibleTestUnits() } },
                     '2.18': { withAnsibleCore('2.18') { ansibleTestSanity(); ansibleTestUnits() } }
        }
    }
}
```

Le chemin indiqué ici fonctionne sur un nœud statique `ansible-runner`. Dans un pod, il faut écrire le
`podTemplate` vous-même ; `ansibleCollectionPipeline` le fait pour vous.

### 2.4 Credentials (administrateur Jenkins)

`nexus-galaxy-hosted-token` (publication) et `spotter-api-token` (Spotter), de type *Secret text*.

## 3. GitLab

### 3.1 `.gitlab-ci.yml` minimal

```yaml
include:
  - component: $CI_SERVER_FQDN/ci/ansible-collection-ci/ansible-collection@1
```

Il contient les mêmes étapes que Jenkins. Les jobs de MR vérifient le fragment de changelog.

### 3.2 `.gitlab-ci.yml` complet

```yaml
workflow:            # un seul pipeline par MR
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS
      when: never
    - if: $CI_COMMIT_BRANCH || $CI_COMMIT_TAG || $CI_PIPELINE_SOURCE == "schedule"

include:
  - component: $CI_SERVER_FQDN/ci/ansible-collection-ci/ansible-collection@1.0.0
    inputs:
      runner-image: nexus.corp.local:8443/ci/ansible-collection-runner:2026.10
      ansible-core-versions: ['2.16', '2.18']       # entre quotes
      ansible-core-optional: '2.20'                 # AAP 2.7, non bloquant
      # target-ees: >-                              # matrice vérifiée contre les EE (mêmes séries exigées)
      #   hub.corp.local/ansible-automation-platform-26/ee-minimal-rhel9:latest
      #   hub.corp.local/ansible-automation-platform/ee-minimal-rhel9:2.18
      test-mode: auto
      integration: true
      integration-images: [default, ubuntu2404]
      molecule: true
      spotter: true
      spotter-endpoint: https://spotter.corp.local/api
      spotter-allow-failure: true
      security-fail-on: high
```

* **Variables CI/CD masquées** (Settings > CI/CD > Variables) :
  * `ACI_GALAXY_TOKEN`, **protégée**, avec des tags protégés `*.*.*` ;
  * `SPOTTER_TOKEN`.
* Ne mettez **jamais** de secret dans `inputs`.
* Vos propres jobs s'ajoutent normalement à côté de l'`include`. Les jobs du composant commencent par
  `aci-`.

## 4. Ce que vous verrez

| Étape | Échoue si… | Que faire |
|---|---|---|
| EE cibles | une EE n'a pas une version de core ou de Python compatible avec `requires_ansible` | corriger `requires_ansible` ou la liste d'EE |
| Changelog | une PR/MR modifie la collection sans fragment | ajouter `changelogs/fragments/*.yml`, ou le label `skip-changelog` |
| Certification | ignore sanity interdit, `.ansible-lint` non conforme, `requires_ansible` non supporté, galaxy-importer ou ansible-lint production en échec | voir `reports/certification/guards.txt`, `galaxy-importer.log` |
| Lint / Docs / Build | erreurs yamllint, ansible-lint, antsibull-docs, galaxy-importer | rapports dans `reports/` |
| Sécurité | constat HIGH ou CRITICAL | corriger, ou `# nosec: <règle> reason="…"` justifié |
| Sanity / units | ansible-test | JUnit dans l'onglet *Tests* ; les séries optionnelles et les pré-versions ne donnent qu'un UNSTABLE ou un avertissement |
| Publication | le tag est différent de la version de `galaxy.yml` | tagger `1.2.3` (ou `v1.2.3`) = `version: 1.2.3` |

En local, dans l'image runner : `ACI_CORE=2.18 /opt/ansible-ci/bin/aci sanity` (ou `lint`,
`certification`…).

## 5. Versions

* `@v1` (Jenkins) et `@1` (GitLab) : vous recevez automatiquement les correctifs et les évolutions
  compatibles.
* Une nouvelle version majeure, par exemple le passage par défaut à AAP 2.7, sera annoncée et à adopter
  explicitement.
* Historique : `jenkins-shared-library/CHANGELOG.md` et `gitlab-ci-templates/CHANGELOG.md`.
