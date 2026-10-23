# syntax=docker/dockerfile:1
# CI "runner" image for Ansible collections: OpenShift pods (Jenkins / GitLab), WITHOUT a container engine.
# Built on the corporate UBI 9 base image, which already provides (contract, see README.md):
#   * the internal CA in the system store (/etc/pki/ca-trust) + REQUESTS_CA_BUNDLE / SSL_CERT_FILE;
#   * /etc/pip.conf pointing to the Nexus PyPI proxy (read for root as well as for an arbitrary UID);
#   * yum/microdnf repositories to the internal mirror, BaseOS AND AppStream (python3.12 is in AppStream).
#
# Build context = ROOT of the ansible-collection-ci repository (the image embeds ci-scripts/):
#   podman build -f infra/runner-image/Dockerfile \
#     --build-arg BASE_IMAGE=nexus.corp.local:8443/corp/ubi9-corp:9.8 \
#     -t nexus.corp.local:8443/ci/ansible-collection-runner:2026.10 .
#
# No docker CLI: the stages that need an engine run on the ansible-builder VM (host podman).
# ansible-core is NOT installed here: `aci` creates (and caches) one venv per matrix series.
# The `aci` scripts (ci-scripts/) are installed in /opt/ansible-ci: both the Jenkins pipeline and the
# GitLab component call /opt/ansible-ci/bin/aci, so the image tag pins the scripts version.

# PLACEHOLDER: registry prefix to adapt; "corp/ubi9-corp:9.8" = the corporate base image.
ARG BASE_IMAGE=nexus.corp.local:8443/corp/ubi9-corp:9.8
FROM ${BASE_IMAGE}

# ansible-test CONTROLLER Pythons (CONTROLLER_PYTHON_VERSIONS of the stable-X.Y branches):
#   2.16: 3.10-3.12; 2.18: 3.11-3.13; 2.20: 3.12-3.14; 2.22: 3.13-3.15.
# 3.12 covers the whole AAP 2.6 matrix (2.16, 2.18), 2.20 and the certification; it is also the Python
# of the EEs. It is the only one installed by default. Add 3.14 (RHEL 9.8 AppStream; no 3.13) only to
# test 2.22 / milestone / devel: --build-arg PYTHON_VERSIONS="3.12 3.14".
# Choice per series: ci-scripts/share/aci/python-map.txt. The RHEL 9 system python3 (3.9) is kept.
# The LAST one of the list hosts the tooling venv.
ARG PYTHON_VERSIONS="3.12"
# shellcheck: "pip" (shellcheck-py from Nexus, default), "rpm" (ShellCheck from EPEL 9 through the internal
# mirror) or "none" (the shellcheck sanity test is then skipped in --venv mode).
ARG SHELLCHECK_SOURCE=pip

USER 0

# 1) System packages (internal repositories of the base image)
#    git-core: ansible-test / galaxy; openssh-clients: ssh-keygen required by ansible-test;
#    tar/gzip/findutils/rsync/which/diffutils: collection build and scripts; shadow-utils: useradd.
RUN set -eux; \
    pkgs="git-core openssh-clients tar gzip findutils rsync jq which diffutils shadow-utils"; \
    for v in ${PYTHON_VERSIONS}; do pkgs="$pkgs python$v python$v-pip"; done; \
    if [ "${SHELLCHECK_SOURCE}" = "rpm" ]; then pkgs="$pkgs ShellCheck"; fi; \
    microdnf -y install --setopt=install_weak_deps=0 --nodocs $pkgs; \
    microdnf clean all; rm -rf /var/cache/yum /var/lib/dnf/history*

# 2) Minimal tooling venv (PyYAML for the aci scripts, shellcheck) - index: /etc/pip.conf
COPY infra/runner-image/requirements.txt /opt/ansible-ci/requirements.txt
RUN set -eux; \
    for v in ${PYTHON_VERSIONS}; do tools_py=$v; done; \
    "python${tools_py}" -m venv /opt/ansible-ci; \
    if [ "${SHELLCHECK_SOURCE}" = "pip" ]; then req=/opt/ansible-ci/requirements.txt; \
    else grep -v '^shellcheck-py' /opt/ansible-ci/requirements.txt > /tmp/req.txt; req=/tmp/req.txt; fi; \
    /opt/ansible-ci/bin/pip install --no-cache-dir --disable-pip-version-check -r "$req"; \
    rm -f /tmp/req.txt
# 2b) aci scripts (version: ci-scripts/VERSION)
COPY ci-scripts/VERSION /opt/ansible-ci/VERSION
COPY ci-scripts/bin/aci /opt/ansible-ci/bin/aci
COPY ci-scripts/lib/aci /opt/ansible-ci/lib/aci
COPY ci-scripts/share/aci /opt/ansible-ci/share/aci
RUN chmod 0755 /opt/ansible-ci/bin/aci && chmod -R a+rX /opt/ansible-ci/lib/aci /opt/ansible-ci/share/aci /opt/ansible-ci/VERSION
ENV PATH=/opt/ansible-ci/bin:${PATH} \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1

# 3) OpenShift-compatible non-root user: arbitrary UID, always a member of GID 0.
#    HOME belongs to group 0 with the owner's permissions (chgrp 0 + chmod g=u).
#    ansible-test --venv normally downloads get-pip from the Internet: `aci sanity|units` puts
#    get_pip_offline.py (ensurepip + pip from Nexus) in ~/.ansible/test/cache instead when needed.
RUN set -eux; \
    useradd --uid 1001 --gid 0 --home-dir /home/ci --create-home --shell /bin/bash ci; \
    chgrp -R 0 /home/ci; chmod -R g=u /home/ci
ENV HOME=/home/ci USER=ci LOGNAME=ci
USER 1001
WORKDIR /home/ci

# 4) Checks
RUN for v in ${PYTHON_VERSIONS}; do "/usr/bin/python$v" --version; done && aci version && git --version && ssh -V \
 && if [ "${SHELLCHECK_SOURCE}" != "none" ]; then shellcheck --version; fi
