"""Remplacant airgap des scripts get-pip d'ansible-test (mode ANSIBLE_TEST_MODE=venv).

Contexte (ansible_test/_util/target/setup/requirements.py, fonction bootstrap) : ansible-test cree
ses venvs SANS pip (`python -m venv --without-pip`) puis execute
~/.ansible/test/cache/get_pip_<X_Y>.py, telecharge sinon depuis
https://ci-files.testing.ansible.com/ansible-test/get-pip-<X.Y>.py (Internet).

Ce fichier a deux usages :
  * `python get_pip_offline.py --seed` (appele par le noxfile) : lit la version de pip voulue par
    l'ansible-test installe et se copie sous ce nom de cache s'il n'y a rien ;
  * execute par ansible-test a la place de get-pip : installe pip avec `ensurepip` (roue fournie
    par la distribution, sans reseau) puis le met a la version demandee depuis l'index de
    /etc/pip.conf (Nexus). Les options propres a get-pip (--no-setuptools, --no-wheel) sont ignorees.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys

GET_PIP_ONLY = {"--no-setuptools", "--no-wheel"}


def seed() -> None:
    import ansible_test  # venv de la session nox

    src = os.path.join(os.path.dirname(ansible_test.__file__), "_internal", "python_requirements.py")
    with open(src, encoding="utf-8") as f:
        versions = sorted(set(re.findall(r"pip='([0-9.]+)'", f.read())))
    if not versions:
        sys.exit(f"version de pip introuvable dans {src}")
    cache = os.path.expanduser("~/.ansible/test/cache")
    os.makedirs(cache, exist_ok=True)
    for version in versions:
        dest = os.path.join(cache, "get_pip_%s.py" % version.replace(".", "_"))
        if os.path.exists(dest):
            print(f"get-pip {version} : deja en cache ({dest})")
        else:
            shutil.copyfile(__file__, dest)
            print(f"get-pip {version} : remplacant hors ligne depose ({dest})")


def bootstrap(args: list[str]) -> None:
    subprocess.check_call([sys.executable, "-m", "ensurepip", "--default-pip"])
    pip_args = [a for a in args if a not in GET_PIP_ONLY]
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--upgrade", *pip_args])


if __name__ == "__main__":
    if sys.argv[1:] == ["--seed"]:
        seed()
    else:
        bootstrap(sys.argv[1:])
