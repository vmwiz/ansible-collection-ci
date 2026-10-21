# syntax=docker/dockerfile:1
# Image "runner" CI pour collections Ansible : pods OpenShift (Jenkins / GitLab), SANS moteur de conteneurs.
# Construite sur l'image de base d'entreprise UBI 9, qui fournit deja (contrat, voir README.md) :
#   * l'AC interne dans le magasin systeme (/etc/pki/ca-trust) + REQUESTS_CA_BUNDLE / SSL_CERT_FILE ;
#   * /etc/pip.conf vers le proxy PyPI Nexus (lu pour root comme pour un UID arbitraire) ;
#   * des depots yum/microdnf vers le miroir interne, BaseOS ET AppStream (python3.12 est dans AppStream).
#
# Contexte de build = RACINE du depot ansible-collection-ci (l'image embarque ci-scripts/) :
#   podman build -f infra/runner-image/Dockerfile \
#     --build-arg BASE_IMAGE=nexus.corp.local:8443/corp/ubi9-corp:9.8 \
#     -t nexus.corp.local:8443/ci/ansible-collection-runner:2026.10 .
#
# Pas de CLI docker : les etapes qui demandent un moteur tournent sur la VM ansible-builder (podman hote).
# ansible-core n'est PAS installe ici : `aci` cree (et met en cache) un venv par serie de la matrice.
# Les scripts `aci` (ci-scripts/) sont installes dans /opt/ansible-ci : c'est ce que lancent les
# composants GitLab (qui ne peuvent pas livrer de fichiers aux jobs) ; Jenkins utilise par defaut la
# copie embarquee dans la bibliotheque partagee (scriptsFrom: 'agent' pour utiliser celle-ci).

# PLACEHOLDER : prefixe de registre a adapter ; "corp/ubi9-corp:9.8" = image de base de Gilles.
ARG BASE_IMAGE=nexus.corp.local:8443/corp/ubi9-corp:9.8
FROM ${BASE_IMAGE}

# Pythons CONTROLEUR d'ansible-test (CONTROLLER_PYTHON_VERSIONS des branches stable-X.Y) :
#   2.16 : 3.10-3.12 ; 2.18 : 3.11-3.13 ; 2.20 : 3.12-3.14 ; 2.22 : 3.13-3.15.
# 3.12 couvre toute la matrice AAP 2.6 (2.16, 2.18), la serie optionnelle 2.20 et la certification ; c'est
# aussi le Python des EE. Il est le seul installe par defaut. Ajouter 3.14 (AppStream RHEL 9.8 ; pas de 3.13)
# uniquement pour tester 2.22 / milestone / devel : --build-arg PYTHON_VERSIONS="3.12 3.14".
# Choix par serie : ci-scripts/share/aci/python-map.txt. Le python3 systeme de RHEL 9 (3.9) est conserve.
# Le DERNIER de la liste porte le venv d'outils.
ARG PYTHON_VERSIONS="3.12"
# shellcheck : "pip" (shellcheck-py depuis Nexus, defaut), "rpm" (ShellCheck d'EPEL 9 via le miroir interne)
# ou "none" (le test sanity shellcheck est alors ignore en mode --venv).
ARG SHELLCHECK_SOURCE=pip

USER 0

# 1) Paquets systeme (depots internes de l'image de base)
#    git-core : ansible-test / galaxy ; openssh-clients : ssh-keygen exige par ansible-test ;
#    tar/gzip/findutils/rsync/which/diffutils : build de collection et scripts ; shadow-utils : useradd.
RUN set -eux; \
    pkgs="git-core openssh-clients tar gzip findutils rsync jq which diffutils shadow-utils"; \
    for v in ${PYTHON_VERSIONS}; do pkgs="$pkgs python$v python$v-pip"; done; \
    if [ "${SHELLCHECK_SOURCE}" = "rpm" ]; then pkgs="$pkgs ShellCheck"; fi; \
    microdnf -y install --setopt=install_weak_deps=0 --nodocs $pkgs; \
    microdnf clean all; rm -rf /var/cache/yum /var/lib/dnf/history*

# 2) Venv d'outillage minimal (PyYAML pour les scripts aci, shellcheck) - index : /etc/pip.conf
COPY infra/runner-image/requirements.txt /opt/ansible-ci/requirements.txt
RUN set -eux; \
    for v in ${PYTHON_VERSIONS}; do tools_py=$v; done; \
    "python${tools_py}" -m venv /opt/ansible-ci; \
    if [ "${SHELLCHECK_SOURCE}" = "pip" ]; then req=/opt/ansible-ci/requirements.txt; \
    else grep -v '^shellcheck-py' /opt/ansible-ci/requirements.txt > /tmp/req.txt; req=/tmp/req.txt; fi; \
    /opt/ansible-ci/bin/pip install --no-cache-dir --disable-pip-version-check -r "$req"; \
    rm -f /tmp/req.txt
# 2b) Scripts aci (meme version que la bibliotheque Jenkins / les composants GitLab : ci-scripts/VERSION)
COPY ci-scripts/VERSION /opt/ansible-ci/VERSION
COPY ci-scripts/bin/aci /opt/ansible-ci/bin/aci
COPY ci-scripts/lib/aci /opt/ansible-ci/lib/aci
COPY ci-scripts/share/aci /opt/ansible-ci/share/aci
RUN chmod 0755 /opt/ansible-ci/bin/aci && chmod -R a+rX /opt/ansible-ci/lib/aci /opt/ansible-ci/share/aci /opt/ansible-ci/VERSION
ENV PATH=/opt/ansible-ci/bin:${PATH} \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1

# 3) Utilisateur non-root compatible OpenShift : UID arbitraire, toujours membre du GID 0.
#    HOME appartient au groupe 0 avec les droits du proprietaire (chgrp 0 + chmod g=u).
#    ansible-test --venv telecharge normalement get-pip depuis Internet : `aci sanity|units` depose a la
#    place get_pip_offline.py (ensurepip + pip depuis Nexus) dans ~/.ansible/test/cache au besoin.
RUN set -eux; \
    useradd --uid 1001 --gid 0 --home-dir /home/ci --create-home --shell /bin/bash ci; \
    chgrp -R 0 /home/ci; chmod -R g=u /home/ci
ENV HOME=/home/ci USER=ci LOGNAME=ci
USER 1001
WORKDIR /home/ci

# 4) Verification
RUN for v in ${PYTHON_VERSIONS}; do "/usr/bin/python$v" --version; done && aci version && git --version && ssh -V \
 && if [ "${SHELLCHECK_SOURCE}" != "none" ]; then shellcheck --version; fi
