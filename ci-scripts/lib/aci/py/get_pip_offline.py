"""Airgapped replacement for the ansible-test get-pip scripts (venv mode: ACI_TEST_MODE=venv).

Context (ansible_test/_util/target/setup/requirements.py, bootstrap function): ansible-test creates
its venvs WITHOUT pip (`python -m venv --without-pip`) and then runs
~/.ansible/test/cache/get_pip_<X_Y>.py, otherwise downloaded from
https://ci-files.testing.ansible.com/ansible-test/get-pip-<X.Y>.py (Internet).

This file has two uses:
  * `python get_pip_offline.py --seed` (called by `aci sanity|units` in venv mode): reads the pip version
    wanted by the installed ansible-test and copies itself under that cache name if nothing is there;
  * run by ansible-test instead of get-pip: installs pip with `ensurepip` (wheel shipped by the
    distribution, no network) and then upgrades it to the requested version from the index in
    /etc/pip.conf (Nexus). Options specific to get-pip (--no-setuptools, --no-wheel) are ignored.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys

GET_PIP_ONLY = {"--no-setuptools", "--no-wheel"}


def seed() -> None:
    import ansible_test  # venv of the series (aci)

    src = os.path.join(os.path.dirname(ansible_test.__file__), "_internal", "python_requirements.py")
    with open(src, encoding="utf-8") as f:
        versions = sorted(set(re.findall(r"pip='([0-9.]+)'", f.read())))
    if not versions:
        sys.exit(f"pip version not found in {src}")
    cache = os.path.expanduser("~/.ansible/test/cache")
    os.makedirs(cache, exist_ok=True)
    for version in versions:
        dest = os.path.join(cache, "get_pip_%s.py" % version.replace(".", "_"))
        if os.path.exists(dest):
            print(f"get-pip {version}: already cached ({dest})")
        else:
            shutil.copyfile(__file__, dest)
            print(f"get-pip {version}: offline replacement installed ({dest})")


def bootstrap(args: list[str]) -> None:
    subprocess.check_call([sys.executable, "-m", "ensurepip", "--default-pip"])
    pip_args = [a for a in args if a not in GET_PIP_ONLY]
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--upgrade", *pip_args])


if __name__ == "__main__":
    if sys.argv[1:] == ["--seed"]:
        seed()
    else:
        bootstrap(sys.argv[1:])
