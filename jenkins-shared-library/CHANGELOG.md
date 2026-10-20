# Changelog - bibliotheque Jenkins ansible-ci

SemVer. Tags `vX.Y.Z` immuables + branche mobile `v1` (= dernier tag 1.x, deplacee a chaque release).
Les Jenkinsfile utilisent `@Library('ansible-ci@v1')` (correctifs et evolutions compatibles automatiques)
ou `@Library('ansible-ci@v1.0.0')` (fige).
* patch : correctif, sans changement de parametre ni de comportement par defaut ;
* mineure : nouveau parametre (avec defaut), nouvelle etape granulaire, nouvel outil desactive par defaut ;
* majeure : parametre renomme/supprime, defaut modifie (matrice, etape activee), version majeure de `aci`.
Les etapes `aci*` (internes) ne font pas partie de l'API.

## v1.0.0 - 2026-10-20

* `ansibleCollectionPipeline(Map)` : pipeline declaratif complet, validation des parametres (cle inconnue
  avec suggestion, types, valeurs, regles croisees), matrice ansible-core en branches paralleles generees.
* Etapes granulaires pour pipelines scriptes : `withAnsibleCi`, `withAnsibleCore`, `ansibleLint`,
  `ansibleCollectionDocs`, `ansibleCollectionBuild`, `galaxyImporter`, `ansibleTestSanity`, `ansibleTestUnits`,
  `ansibleTestIntegration`, `ansibleSecurityScan`, `spotterScan`, `moleculeTest`, `primeAnsibleTestImages`,
  `ansibleCollectionPublish`, `ansibleEeIntrospect`, `ansibleCertification`, `ansibleChangelogCheck`,
  `ansibleEeUnits` (POC).
* Alignement AAP 2.6 : matrice par defaut ansible-core 2.16 + 2.18 (Python 3.12), `ansibleCoreOptional`
  (ex. 2.20 = AAP 2.7, non bloquant), `targetEEs` (matrice derivee des EE, echec immediat si incompatibles).
* Certification Red Hat (reference partner-certification-checker 6.0.0, versions dans
  `resources/org/corp/ansibleci/aci/share/aci/certification.env`).
* Fragment de changelog obligatoire sur les PR (jobs multibranche).
* Scripts `aci` 1.0.0 embarques (`resources/org/corp/ansibleci/aci`, copie de `ci-scripts/` par
  `tools/sync-aci.sh`).
