# Image runner (pods OpenShift, Jenkins et GitLab)

Construite **sur l'image de base d'entreprise UBI 9** (`ARG BASE_IMAGE`, défaut
`nexus.corp.local:8443/corp/ubi9-corp:9.8` : **placeholder**, adapter le préfixe de registre).

```bash
podman build --build-arg BASE_IMAGE=<registre>/corp/ubi9-corp:9.8 \
  -t nexus.corp.local:8443/ci/ansible-collection-runner:2026.10 infra/runner-image
```

| ARG | Défaut | Rôle |
|---|---|---|
| `BASE_IMAGE` | `nexus.corp.local:8443/corp/ubi9-corp:9.8` | image de base (contrat ci-dessous) |
| `PYTHON_VERSIONS` | `3.12 3.14` | interpréteurs **ajoutés** depuis AppStream (le dernier porte le venv d'outils) ; le `python3` système (3.9) n'est pas touché |
| `SHELLCHECK_SOURCE` | `pip` | `pip` = `shellcheck-py` depuis Nexus ; `rpm` = `ShellCheck` d'EPEL 9 (miroir interne requis) ; `none` |

## Contrat de l'image de base

| Exigence | Pourquoi | Vérification |
|---|---|---|
| **`/etc/pip.conf`** (ou `/etc/xdg/pip/pip.conf`) avec `index-url` = proxy PyPI Nexus | fichier *global* : lu pour root, l'UID 1001 et **tout UID arbitraire** OpenShift ; `ansible-test --venv` **ignore** `PIP_INDEX_URL` pour ses venvs et ne lit que ce fichier. Pas de `~/.pip/pip.conf` ni de `~/.config/pip` (dépend du HOME) | `python3.12 -m pip config debug` |
| AC interne dans le **magasin système** (`/etc/pki/ca-trust/source/anchors` + `update-ca-trust`) | git, curl, ansible-galaxy, Python `ssl` | `curl https://nexus.corp.local` |
| `REQUESTS_CA_BUNDLE` et `SSL_CERT_FILE` = `/etc/pki/tls/certs/ca-bundle.crt` (et/ou `cert =` dans pip.conf) | pip 23.2 (amorcé par `ensurepip` dans les venvs ansible-test) et requests (Spotter, galaxy-importer) n'utilisent pas le magasin système sans cela | `env` |
| Dépôts microdnf vers le miroir interne avec **BaseOS ET AppStream** | `python3.12`, `python3.14`, `git-core`, `jq`, `rsync`… sont dans AppStream ; `ShellCheck` seulement dans EPEL 9 (optionnel) | `microdnf repolist` |
| `microdnf`, `coreutils`, `bash` (UBI minimal) | construction | — |

## Ce que l'image ajoute
* `python3.12` + `python3.14` et leurs `-pip` (UBI 9.8 : 3.12.15 et 3.14.8 ; AppStream a aussi 3.11, mais pas 3.13). Pythons contrôleur ansible-test : 2.19 = 3.11-3.13 → **3.12** ; 2.20/2.21 = 3.12-3.14 et 2.22 = 3.13-3.15 → **3.14**. Le noxfile choisit par série ;
* `git-core`, `openssh-clients` (ssh-keygen requis par ansible-test), `tar`, `gzip`, `findutils`, `rsync`, `jq`, `which`, `diffutils`, `shadow-utils` ;
* venv `/opt/ansible-ci` en Python 3.14 (premier dans le `PATH`) : `nox`, `PyYAML`, `shellcheck-py` (`requirements.txt`, versions figées) ;
* utilisateur `ci` UID **1001**, GID **0**, `HOME=/home/ci` en `chgrp 0` + `chmod g=u` (UID arbitraire OpenShift).

Retiré par rapport à la version Debian : AC et `pip.conf` (fournis par la base), CLI docker (aucun moteur
dans les pods ; la VM utilise son podman), scripts `get-pip` (remplacés par `ci/get_pip_offline.py`,
déposé à l'exécution par le noxfile : `ensurepip` + pip depuis Nexus, plus de dépôt raw `ansible-ci-files`).

## Test (`standin/`)
`standin/Containerfile` émule `ubi9-corp:9.8` (UBI 9 minimal, python3 3.9, AC de test, `pip.conf`).
Générer d'abord une AC de test `standin/corp-test-ca.crt` (openssl) ; ce dossier ne sert qu'aux essais.
