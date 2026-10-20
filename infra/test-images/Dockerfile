# syntax=docker/dockerfile:1
# OPTIONNEL - image ansible-test "durcie airgap" derivee de l'image officielle.
# Utile si l'on ne veut pas dependre de --pypi-endpoint (option masquee d'ansible-test) ou si les
# cibles d'integration installent des paquets OS (apt) : on fige alors CA + pip + apt sur Nexus.
#
# Le tag DOIT correspondre exactement a celui de ansible_test/_data/completion/docker.txt de la
# version d'ansible-core testee (ex. 2.21.x -> default-test-container:v2.21-4) :
#   python -c "import ansible_test,os;print(open(os.path.join(os.path.dirname(ansible_test.__file__),'_data/completion/docker.txt')).read())"
#
#   docker build --build-arg UPSTREAM=nexus.corp.local:8444/ansible/default-test-container:v2.21-4 \
#     -t nexus.corp.local:8443/airgap-quay/ansible/default-test-container:v2.21-4 .
#   docker push nexus.corp.local:8443/airgap-quay/ansible/default-test-container:v2.21-4
#
# Puis dans le CI : ANSIBLE_TEST_IMAGE_MIRROR=nexus.corp.local:8443/airgap-quay
# (ci/prime_images.py remplace le prefixe "quay.io" par ce miroir, tire l'image et la re-tague
#  quay.io/ansible/default-test-container:v2.21-4 pour ansible-test).

ARG UPSTREAM=nexus.corp.local:8444/ansible/default-test-container:v2.21-4
FROM ${UPSTREAM}

ARG APT_MIRROR=https://nexus.corp.local/repository/ubuntu-proxy

COPY certs/ /usr/local/share/ca-certificates/corp/
COPY pip.conf /etc/pip.conf

# Les images de base ansible-test sont basees sur Ubuntu (voir ansible/base-test-container)
RUN set -eux; \
    update-ca-certificates; \
    for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list; do \
      [ -f "$f" ] && sed -i -E "s#https?://(archive|security|ports)\.ubuntu\.com/ubuntu(-ports)?#${APT_MIRROR}#g" "$f" || true; \
    done
ENV PIP_CERT=/etc/ssl/certs/ca-certificates.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
