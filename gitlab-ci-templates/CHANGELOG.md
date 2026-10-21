# Changelog - composant GitLab ansible-collection (ansible-ci)

Versions SemVer, tags `x.y.z` (format exige par le catalogue CI/CD), alignees sur la bibliotheque Jenkins
(`v1.0.0`) et sur `ci-scripts/VERSION` :
* patch : correctifs sans changement d'input ni de comportement par defaut ;
* mineure : nouvel input (avec defaut), nouveau job desactive par defaut, mise a jour d'outil compatible ;
* majeure : input renomme/supprime, defaut modifie (ex. matrice ansible-core), version majeure de `aci`.

## 1.0.1 - 2026-10-21

* Correctif : `molecule-images` par defaut `ubuntu2404 fedora40` (alias valides en ansible-core 2.18).
* `ACI_EXPECTED_VERSION` 1.0.1 ; image runner : Python 3.12 seul (326 Mo), python3.14 optionnel.
* `tests/` du composant reduit a la validation (rendu + schema) et a la collection d'essai (copie
  synchronisee par `tools/sync.sh`) ; l'execution des jobs sur le banc est dans `tests/gitlab-jobs/`
  du depot source.

## 1.0.0 - 2026-10-20

* Premiere version : controles statiques, ansible-test sanity/units (venv dans les pods, docker sur la
  VM ansible-builder), integration, molecule, Spotter prive, publication Nexus sur tag.
* Alignement AAP 2.6 : matrice par defaut ansible-core 2.16 + 2.18 (Python 3.12), `ansible-core-optional`
  (2.20 = AAP 2.7, non bloquant), `target-ees` (introspection des EE, echec immediat si incompatible).
* Certification Red Hat (reference partner-certification-checker 6.0.0) : garde-fous, galaxy-importer 0.4.39,
  ansible-lint 26.4.0 `--profile=production`, sanity Python 3.12 sur stable-2.16/2.18/2.20.
* Fragment de changelog obligatoire sur MR (`changelog-skip-token`).
* POC non teste : units dans les EE (`ee-tests`).
