# Bibliothèque partagée Jenkins `ansible-ci` (v1)

Elle teste, valide et publie des collections Ansible, en airgap derrière Nexus, en suivant AAP 2.6.
Les équipes écrivent deux lignes de Groovy ; tout le reste vient de la bibliothèque.

```groovy
@Library('ansible-ci@v1') _
ansibleCollectionPipeline()
```

## Structure

```
vars/                     étapes publiques (une .groovy + une aide .txt chacune) ; aci* = interne
  ansibleCollectionPipeline.groovy   pipeline déclaratif complet
  withAnsibleCi / withAnsibleCore    contexte pour les pipelines scriptés
  ansibleLint, ansibleCollectionDocs, ansibleCollectionBuild, galaxyImporter, ansibleCertification,
  ansibleChangelogCheck, ansibleTestSanity, ansibleTestUnits, ansibleTestIntegration, ansibleSecurityScan,
  spotterScan, moleculeTest, primeAnsibleTestImages, ansibleEeIntrospect, ansibleEeUnits (POC),
  ansibleCollectionPublish
src/org/corp/ansibleci/Config.groovy défauts, validation, matrice (méthodes @NonCPS, testées hors Jenkins)
resources/org/corp/ansibleci/
  aci/                    scripts bash `aci` (copie de ../ci-scripts, NE PAS MODIFIER ICI)
  pod/runner-pod.yaml     pod restricted-v2 (jnlp + runner)
test/                     unit/ (Config), validate-pod.sh
```

La logique métier est en bash (`aci`), partagée avec GitLab et avec l'image runner. Les étapes la
déposent sur l'agent avec `libraryResource`, dans `@tmp/aci-<version>`, puis appellent
`bash …/bin/aci <commande>`. Pour modifier un script : éditer `../ci-scripts`, lancer
`../tools/sync.sh`, puis committer les deux. `tools/sync.sh --check` (CI, banc) refuse une copie
divergente. La copie est voulue : Jenkins charge la bibliothèque depuis SCM (`git subtree split`), elle
ne peut pas lire `ci-scripts/` au moment de l'exécution.

## Choix techniques (vérifiés sur Jenkins 2.580.1)

* **Matrice dynamique** : la directive `matrix` exige des valeurs littérales. Le job `matrix-dynamic` du
  banc échoue avec « Expected string literal but got ${cores} ». La bibliothèque construit donc une
  `Map` de closures (`aciBranches.tests`) et l'exécute avec `parallel` dans une étape `script`. Il y a
  une branche par série, plus les sanity de certification manquantes. Les closures sont créées dans une
  boucle `for` avec des variables locales au corps de la boucle, ce qui évite la capture de la dernière
  valeur.
* **CPS** : `Config` est entièrement `@NonCPS` (calcul pur, sans étape Pipeline). Les étapes Jenkins
  (`sh`, `withEnv`, `parallel`…) restent dans `vars/`. Aucun `return` dans une closure `withEnv`.
* **Options déclaratives** : les valeurs calculées (`timeout`, `buildDiscarder`) passent par des
  variables locales. Un appel de méthode dans `options {}` est refusé.
* **Validation** : toute clé inconnue ou valeur invalide arrête le build **avant** d'allouer un agent.
  Le message liste toutes les erreurs et propose une correction, par exemple
  « paramètre inconnu 'lnt' (vouliez-vous dire 'lint' ?) ».
* **Séries optionnelles et pré-versions** : leur échec met le build en UNSTABLE (`catchError`), sans le
  faire échouer.
* **Bibliothèque globale** = code de confiance. Les Jenkinsfile des équipes restent dans la sandbox.

## Paramètres

La référence complète, avec les valeurs par défaut, se trouve dans `vars/ansibleCollectionPipeline.txt`
(affichée par Jenkins : *Pipeline Syntax > Global Variables Reference*) et dans `../PROPOSITION.md`.

## Versions

Voir `CHANGELOG.md` : tags `vX.Y.Z` immuables + branche mobile `v1`.

## Tests

| Test | Commande | Ce qui est vérifié |
|---|---|---|
| Unitaires `Config` | `test/unit/run.sh` | défauts AAP, validation, matrice, EE, toEnv (14 tests, groovy-all de jenkins.war) |
| Pod | `test/validate-pod.sh` | schéma Kubernetes 1.33 strict + exigences restricted-v2 |
| Bout en bout (banc, hors livrable) | `../tests/jenkins-e2e/run-e2e.sh` | Jenkins 2.580.1 réel, bibliothèque depuis un dépôt git local (`v1`, `v1.0.0`), agent runner en airgap |
