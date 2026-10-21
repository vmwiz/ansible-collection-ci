# Image runner (pods OpenShift, Jenkins et GitLab)

Construite **sur l'image de base d'entreprise UBI 9** (`ARG BASE_IMAGE`, défaut
`nexus.corp.local:8443/corp/ubi9-corp:9.8` : **placeholder**, adapter le préfixe de registre).

```bash
# contexte = RACINE du depot (l'image embarque ci-scripts/)
podman build -f infra/runner-image/Dockerfile --build-arg BASE_IMAGE=<registre>/corp/ubi9-corp:9.8 \
  -t nexus.corp.local:8443/ci/ansible-collection-runner:2026.10 \
  -t nexus.corp.local:8443/ci/ansible-collection-runner:aci-$(cat ci-scripts/VERSION) .
```
Deux tags : calendaire (`2026.10`, defaut des modeles) et version des scripts (`aci-1.0.1`). Le composant
GitLab verifie la version (`ACI_EXPECTED_VERSION`) ; la bibliotheque Jenkins utilise par defaut sa propre copie.

| ARG | Défaut | Rôle |
|---|---|---|
| `BASE_IMAGE` | `nexus.corp.local:8443/corp/ubi9-corp:9.8` | image de base (contrat ci-dessous) |
| `PYTHON_VERSIONS` | `3.12` | interpréteurs **ajoutés** depuis AppStream (le dernier porte le venv d'outils) ; `"3.12 3.14"` seulement pour tester 2.22 / `milestone` / `devel` ; le `python3` système (3.9) n'est pas touché |
| `SHELLCHECK_SOURCE` | `pip` | `pip` = `shellcheck-py` depuis Nexus ; `rpm` = `ShellCheck` d'EPEL 9 (miroir interne requis) ; `none` |

## Contrat de l'image de base

| Exigence | Pourquoi | Vérification |
|---|---|---|
| **`/etc/pip.conf`** (ou `/etc/xdg/pip/pip.conf`) avec `index-url` = proxy PyPI Nexus | fichier *global* : lu pour root, l'UID 1001 et **tout UID arbitraire** OpenShift ; `ansible-test --venv` **ignore** `PIP_INDEX_URL` pour ses venvs et ne lit que ce fichier. Pas de `~/.pip/pip.conf` ni de `~/.config/pip` (dépend du HOME) | `python3.12 -m pip config debug` |
| AC interne dans le **magasin système** (`/etc/pki/ca-trust/source/anchors` + `update-ca-trust`) | git, curl, ansible-galaxy, Python `ssl` | `curl https://nexus.corp.local` |
| `REQUESTS_CA_BUNDLE` et `SSL_CERT_FILE` = `/etc/pki/tls/certs/ca-bundle.crt` (et/ou `cert =` dans pip.conf) | pip 23.2 (amorcé par `ensurepip` dans les venvs ansible-test) et requests (Spotter, galaxy-importer) n'utilisent pas le magasin système sans cela | `env` |
| Dépôts microdnf vers le miroir interne avec **BaseOS ET AppStream** | `python3.12`, `git-core`, `jq`, `rsync`… sont dans AppStream ; `ShellCheck` seulement dans EPEL 9 (optionnel) | `microdnf repolist` |
| `microdnf`, `coreutils`, `bash` (UBI minimal) | construction | — |

## Ce que l'image ajoute
* `python3.12` et `python3.12-pip` (UBI 9.8 : 3.12.15). Pythons contrôleur ansible-test : 2.16 = 3.10-3.12,
  2.18 = 3.11-3.13, 2.20 = 3.12-3.14 → **3.12 couvre toute la matrice** (2.16 + 2.18 + 2.20 optionnelle), la
  certification et correspond au Python des EE AAP 2.6. `aci` choisit par série (`share/aci/python-map.txt`).
  2.22, `milestone` et `devel` exigent ≥ 3.13 : ajouter `python3.14` (`PYTHON_VERSIONS="3.12 3.14"` ;
  AppStream RHEL 9.8 n'a pas 3.13) ;
* `git-core`, `openssh-clients` (ssh-keygen requis par ansible-test), `tar`, `gzip`, `findutils`, `rsync`, `jq`, `which`, `diffutils`, `shadow-utils` ;
* venv `/opt/ansible-ci` (premier dans le `PATH`) : `PyYAML`, `shellcheck-py` (`requirements.txt`, versions figées) ;
* scripts **`aci`** (`ci-scripts/`) : `/opt/ansible-ci/bin/aci`, `lib/aci`, `share/aci`, `VERSION` ;
* utilisateur `ci` UID **1001**, GID **0**, `HOME=/home/ci` en `chgrp 0` + `chmod g=u` (UID arbitraire OpenShift).

Volontairement absents : moteur et CLI de conteneurs (les étapes `--docker`, intégration, Molecule et
introspection des EE tournent sur la VM `ansible-builder`), ansible-core (installé par `aci` dans des venvs
en cache, par série), AC et `pip.conf` (fournis par l'image de base). `ansible-test --venv` télécharge
normalement ses scripts `get-pip` sur Internet : `aci` dépose à la place `lib/aci/py/get_pip_offline.py`
(`ensurepip` + pip depuis Nexus), aucun dépôt Nexus supplémentaire n'est nécessaire.
Taille mesurée (v1.0.1, Python 3.12 seul) : **326 Mo** ; 388 Mo avec `PYTHON_VERSIONS="3.12 3.14"`.

## Test
L'image de base d'entreprise est émulée pour les essais par `tests/image-base-standin/` (hors livrable,
voir `tests/README.md`).
