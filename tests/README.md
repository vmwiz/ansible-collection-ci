# Banc de test interne (hors livrable)

Ces fichiers ont servi à valider les bibliothèques **sans** cluster OpenShift, sans instance GitLab et sans
Nexus réels. Ils ne sont **pas publiés** avec la bibliothèque Jenkins ni avec le composant GitLab
(`git subtree split` ne prend que `jenkins-shared-library/` et `gitlab-ci-templates/`), et ils dépendent
d'un environnement de banc préparé à la main. Les tests rapides, eux, restent dans chaque livrable :
`ci-scripts/tests/`, `jenkins-shared-library/test/`, `gitlab-ci-templates/tests/validate.sh`.

| Dossier | Rôle |
|---|---|
| `jenkins-e2e/` | Jenkins 2.580.1 réel (`Containerfile.jenkins`, JCasC/init Groovy), agent statique = image runner + JDK 21 en UID arbitraire, Jenkinsfiles de banc (`corp-demo`, `ee`, `ee-bad`), jobs négatifs (`bad-config`, `bad-step`, `matrix-dynamic`), faux `podman` (`podman-shim.sh`) pour simuler l'introspection des EE. `run-e2e.sh` construit les dépôts git locaux, lance les builds et récupère les journaux. |
| `gitlab-jobs/` | `run-jobs.sh` exécute réellement les scripts des jobs rendus par `gitlab-ci-templates/tests/render.py`, chacun dans un clone neuf, dans l'image runner, en airgap ; `inputs/banc*.yml` = inputs du banc (devpi, EE simulées, cas d'écart EE). |
| `image-base-standin/` | Émulation de l'image de base d'entreprise `ubi9-corp:9.8` (UBI 9 minimal, AC de test, `/etc/pip.conf` vers le faux Nexus). |

Prérequis du banc (non scriptés, propres à la machine de test) : réseau podman `airgap` (`--internal`) et
`egress`, conteneur « Nexus » simulé (devpi pour PyPI + Galaxy v3 statique, alias `nexus.corp.local`, AC de
test), images `localhost/jk:test` et `localhost/ansible-collection-runner:<tag>`, dépôt git bare de
`corp.demo` pour `run-jobs.sh`. Voir `PROPOSITION.md` §15 pour le compte rendu.
