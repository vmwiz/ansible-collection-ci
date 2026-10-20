#!/bin/sh
# BANC UNIQUEMENT. L'agent de test n'a pas de moteur de conteneurs et registry.redhat.io est inaccessible :
# ce faux `podman` repond a `podman run ... --entrypoint ansible <image> --version` (seul appel de
# `aci ee-introspect`) en executant le VRAI `ansible --version` d'un venv ansible-core de la version de l'EE.
for a; do case $a in --version) break ;; *) image=$a ;; esac; done
case $image in
  *:2.16) core=2.16.19 ;;
  *:2.18) core=2.18.19 ;;
  *:bad) printf 'ansible [core 2.18.19]\n  python version = 3.10.14 (main) [GCC 11] (/usr/bin/python3.10)\n'; exit 0 ;;
  *) echo "podman-shim : image inconnue $image" >&2; exit 125 ;;
esac
venv=$HOME/fake-ee/$core
[ -x "$venv/bin/ansible" ] || { python3.12 -m venv "$venv" && "$venv/bin/pip" install -q "ansible-core==$core"; } >&2
exec "$venv/bin/ansible" --version
