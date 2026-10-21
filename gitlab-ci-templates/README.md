# Composant GitLab CI/CD `ansible-collection` (ansible-ci 1.x)

Pipeline de test et de validation d'une collection Ansible pour GitLab, en airgap derrière Nexus,
aligné sur AAP 2.6. Il exécute **les mêmes étapes et les mêmes scripts `aci`** que la bibliothèque
Jenkins (`../jenkins-shared-library`). Les deux sont générés à partir de `../ci-scripts`.

## Utilisation

```yaml
# .gitlab-ci.yml de la collection : c'est tout
include:
  - component: $CI_SERVER_FQDN/ci/ansible-collection-ci/ansible-collection@1
```

Le guide `../GUIDE-UTILISATEUR.md` contient aussi l'exemple complet (`examples/complet.gitlab-ci.yml`).

* **Version** : `@1` = dernière 1.x publiée (recommandé) ; `@1.0.0` = version figée ; `@~latest` est à éviter.
  Les tags suivent `x.y.z` (SemVer). La règle de compatibilité est décrite dans `CHANGELOG.md`.
* **Prérequis** : GitLab ≥ 17.0 (composants et `spec:inputs` en GA). Aucune fonction plus récente n'est
  utilisée (pas de `$[[ component.version ]]`, qui demande 18.7, ni de fonction `split`).
* **Sans le catalogue** (projet non publié, autre instance) : on peut inclure le même fichier avec
  `include:project`, qui accepte aussi `inputs:`. Il n'y a qu'un seul modèle à maintenir.
  ```yaml
  include:
    - project: ci/ansible-collection-ci
      ref: 1.0.0
      file: /templates/ansible-collection/template.yml
      inputs: {ansible-core-optional: '2.20'}
  ```

## Runners attendus

| Tag (input) | Exécuteur | Rôle |
|---|---|---|
| `ansible-runner` (`runner-tags`) | Kubernetes/OpenShift, pods `restricted-v2`, image `runner-image` | Contrôles statiques, sanity/units en `venv`, certification, publication |
| `ansible-builder` (`builder-tags`) | runner **shell** sur la VM avec podman | `aci-ee-introspect`, sanity/units en `docker`, intégration, molecule, POC EE |

Les venvs vont dans `~/.cache/ansible-ci`. Le `cache:` de GitLab n'est **pas** utilisé, parce qu'il
impose un chemin dans le projet que lint et sanity analyseraient (problème constaté sur le banc). Pour
accélérer les pods, montez un volume persistant sur `/home/ci/.cache/ansible-ci` dans la config du
runner Kubernetes (`[[runners.kubernetes.volumes.pvc]]`). La VM garde son cache d'elle-même.

## Scripts dans l'image (`/opt/ansible-ci/bin/aci`) : évaluation et recommandation

Un composant GitLab ne peut livrer que du YAML. Les scripts doivent donc arriver par un autre chemin.

| Option | Pour | Contre |
|---|---|---|
| **A. Intégrés à l'image runner** (`/opt/ansible-ci`) et installés sur la VM (`infra/ansible-builder-vm`) | Aucun accès réseau en job ; version figée par le tag d'image ; mêmes fichiers que Jenkins ; testé | Une évolution des scripts impose une nouvelle image |
| B. Job qui clone le projet de scripts (`CI_JOB_TOKEN`) | Scripts découplés de l'image | Accès au projet à autoriser (allowlist du job token) ; un clone par job ; deux versions à aligner |
| C. Scripts en ligne dans le YAML (`!reference`) | Tout tient dans le composant | Bash dupliqué, impossible à tester avec shellcheck ; limites de taille ; divergence avec Jenkins |

**Recommandation : A.**
* Le composant fixe `ACI_EXPECTED_VERSION`. `aci` **refuse** une image dont la version majeure diffère
  et **signale** un écart de version mineure.
* Publiez l'image runner avec **deux tags** : le tag calendaire (`2026.10`) et le tag de version des
  scripts (`aci-1.0.0`).
* À chaque version du composant, mettez à jour la valeur par défaut de `runner-image` dans le même
  commit. `tests/validate.sh` vérifie la cohérence avec `ci-scripts/VERSION`.

## Jobs créés

| Job | Stage | Quand |
|---|---|---|
| `aci-ee-introspect` | `.pre` | `target-ees` non vide. Échoue tout de suite en cas d'incompatibilité (requires_ansible, plage Python, séries ≠ `ansible-core-versions`) |
| `aci-changelog` | statique | Pipeline de MR. Exemption par label ou titre `skip-changelog` |
| `aci-certification` | statique | Garde-fous + galaxy-importer 0.4.39 + ansible-lint 26.4.0 `--profile=production` |
| `aci-lint`, `aci-docs`, `aci-build` (+ importer), `aci-security`, `aci-spotter` | statique | Selon les inputs. `aci-spotter` en `allow_failure` par défaut |
| `aci-sanity-venv` / `aci-units-venv` `[ACI_CORE]` | test | Branches hors branche par défaut (ou `test-mode: venv`) |
| `aci-sanity-docker` / `aci-units-docker` `[ACI_CORE]` | test | Tag, pipeline planifié, branche par défaut (ou `test-mode: docker`) |
| `aci-optional-cores` | test | `ansible-core-optional`, non bloquant |
| `aci-certification-sanity` | test | Sanity en Python 3.12 sur stable-2.16/2.18/2.20 (filtrées par requires_ansible) non couvertes en 3.12 |
| `aci-integration` `[image]`, `aci-molecule` | test | `integration` / `molecule` |
| `aci-ee-units` | test | POC **non testé** (`ee-tests` + `target-ees`), non bloquant |
| `aci-publish` | deploy | Tag + `publish`. Attend la réussite de tous les stages précédents |

Les jobs de test n'attendent pas les contrôles statiques (`needs`). Ils attendent seulement
l'introspection des EE, si elle existe. Une série listée dans `ansible-core-prerelease` qui échoue sort
avec le code 3 (`allow_failure: exit_codes: [3]`).

## Inputs

| Input | Type | Defaut | Description |
|---|---|---|---|
| `stage-static` | string | `'build'` | Stage des controles statiques (lint, docs, build, certification, securite...). |
| `stage-test` | string | `'test'` | Stage ansible-test (sanity, units, integration) et molecule. |
| `stage-publish` | string | `'deploy'` | Stage de publication (sur tag). |
| `runner-image` | string | `'nexus.corp.local:8443/ci/ansible-collection-runner:2026.10'` | Image runner (contient /opt/ansible-ci/bin/aci et Python 3.12). Son tag fige les scripts. |
| `runner-tags` | array | `['ansible-runner']` | Tags du runner Kubernetes/OpenShift (pods restricted-v2, sans moteur de conteneurs). |
| `builder-tags` | array | `['ansible-builder']` | Tags du runner shell de la VM ansible-builder (podman, runner shell) - mode docker, integration, molecule, EE. |
| `aci-path` | string | `'/opt/ansible-ci/bin/aci'` | Chemin des scripts aci dans l'image runner et sur la VM ansible-builder. |
| `ansible-core-versions` | array | `['2.16', '2.18']` | Series testees, entre quotes. Avec target-ees, doit lister exactement les series des EE. |
| `ansible-core-optional` | string | `''` | Series en plus, non bloquantes, separees par des espaces (ex. "2.20" pour AAP 2.7). |
| `ansible-core-prerelease` | string | `''` | Series de ansible-core-versions en pre-version (rc), echec non bloquant (code 3). |
| `ansible-core-default` | string | `''` | Serie des etapes non matricielles (defaut - derniere serie non pre-version). |
| `target-ees` | string | `''` | Images EE cibles separees par des espaces ; introspection (fail-early) et version exacte par serie. |
| `lint` | boolean | `true` | yamllint + ansible-lint + antsibull-changelog lint |
| `docs` | boolean | `true` | antsibull-docs lint-collection-docs |
| `build` | boolean | `true` | ansible-galaxy collection build |
| `galaxy-importer` | boolean | `true` | galaxy-importer sur le tarball (exige build) |
| `security-scan` | boolean | `true` | ansible-security-scanner |
| `certification` | boolean | `true` | Controles certification Red Hat (partner-certification-checker 6.0.0) |
| `certification-sanity` | boolean | `true` | Sanity py3.12 sur stable-2.16/2.18/2.20 non couvertes par la matrice |
| `changelog-check` | boolean | `true` | Fragment changelog obligatoire sur MR |
| `changelog-skip-token` | string | `'skip-changelog'` | Label ou mot du titre de MR qui exempte du fragment |
| `sanity` | boolean | `true` |  |
| `units` | boolean | `true` |  |
| `integration` | boolean | `false` | ansible-test integration --docker (VM ansible-builder) |
| `molecule` | boolean | `false` | molecule test (VM ansible-builder) |
| `spotter` | boolean | `false` | Steampunk Spotter (instance privee, spotter-endpoint obligatoire) |
| `ee-tests` | boolean | `false` | POC non teste - units dans les EE de target-ees |
| `publish` | boolean | `true` | Publication sur tag vers Nexus (ACI_GALAXY_TOKEN) |
| `test-mode` | string | `'auto'` | auto = docker sur tag, planification et branche par defaut ; venv sinon. Valeurs : auto, venv, docker. |
| `sanity-args` | string | `''` | Arguments ansible-test sanity supplementaires |
| `units-args` | string | `''` | Arguments ansible-test units supplementaires |
| `integration-args` | string | `''` | Arguments ansible-test integration supplementaires |
| `integration-images` | array | `['default']` | Images ansible-test --docker de l'integration (une job par image). |
| `docker-network` | string | `''` | ansible-test --docker-network |
| `coverage` | boolean | `false` |  |
| `molecule-images` | string | `'ubuntu2404 fedora40'` | Images molecule separees par des espaces |
| `pip-index-url` | string | `''` | Vide = /etc/pip.conf de l image (seul lu par ansible-test --venv) |
| `pypi-endpoint` | string | `'https://nexus.corp.local/repository/pypi-group/simple'` | Index PyPI des conteneurs ansible-test |
| `image-mirror` | string | `'nexus.corp.local:8444'` | Miroir des images quay.io/ansible |
| `galaxy-server-url` | string | `'https://nexus.corp.local/repository/ansible-group/'` |  |
| `galaxy-publish-url` | string | `'https://nexus.corp.local/repository/ansible-hosted/'` |  |
| `security-fail-on` | string | `'high'` | Valeurs : high, critical, none. |
| `spotter-endpoint` | string | `''` | URL API de l instance Spotter privee |
| `spotter-allow-failure` | boolean | `true` |  |
| `spotter-ansible-version` | string | `'2.20'` |  |
| `spotter-display-level` | string | `'error'` | Valeurs : hint, warning, error. |

**Secrets** : ne les passez jamais en input (les inputs apparaissent en clair dans la configuration).
Définissez-les comme variables CI/CD **masquées** :
* `ACI_GALAXY_TOKEN` : publication, variable **protégée** (tags protégés `*.*.*`) ;
* `SPOTTER_TOKEN` : Spotter.

**Pièges** :
* Les séries ansible-core doivent être écrites **entre quotes** (`'2.20'`). Sans quotes, YAML lit `2.20`
  comme le nombre 2.2, et `aci` refuse alors la série « inconnue ».
* Avec `target-ees`, `ansible-core-versions` doit lister exactement les séries des EE. La matrice
  GitLab est statique ; le job d'introspection indique la valeur à mettre.

## Tests (sans instance GitLab)

* `tests/validate.sh [schema.json]` :
  * rendu des inputs (`tests/render.py` émule types, options, regex, interpolation entière ou partielle,
    `!reference` et `extends`) ;
  * validation du rendu et de l'en-tête `spec` avec le **schéma officiel GitLab** (`tests/gitlab-ci-schema.json`,
    copie du `ci.json` de GitLab 19.6.0-pre) ;
  * vérification que les inputs invalides sont refusés ;
  * simulation des jobs créés pour chaque contexte (branche, branche par défaut, MR, tag) ;
  * validation des exemples.
* `../tests/gitlab-jobs/run-jobs.sh INPUTS CONTEXTE "jobs..."` (banc, hors livrable) : exécute **pour de vrai** les scripts des jobs rendus.
  Chaque job tourne dans un clone neuf, dans l'image runner, en airgap, avec un UID arbitraire ;
  l'introspection tourne sur l'hôte avec podman.
* `render.py` reste une **émulation**. La validation finale se fait dans GitLab : CI Lint
  (`/-/ci/lint`, ou l'API `POST /projects/:id/ci/lint`) et le pipeline du projet composant
  (`.gitlab-ci.yml`), qui inclut le composant `@$CI_COMMIT_SHA` sur `tests/collection` (copie de
  `exemple-collection/corp.demo` maintenue par `tools/sync.sh`).
