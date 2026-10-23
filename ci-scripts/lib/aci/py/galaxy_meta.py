"""Reads galaxy.yml (internal helper of `aci`).

    python galaxy_meta.py <galaxy.yml>               -> "namespace name version"
    python galaxy_meta.py <galaxy.yml> <deps.yml>    -> writes the dependencies in requirements.yml format
                                                         (nothing if none) and prints the same triplet
Python is required by Ansible anyway; PyYAML is an ansible-core dependency.
"""
import sys

import yaml

with open(sys.argv[1], encoding="utf-8") as f:
    meta = yaml.safe_load(f)
if len(sys.argv) > 2:
    deps = meta.get("dependencies") or {}
    if deps:
        with open(sys.argv[2], "w", encoding="utf-8") as f:
            yaml.safe_dump({"collections": [{"name": n, "version": str(v)} for n, v in deps.items()]}, f)
print(meta["namespace"], meta["name"], meta["version"])
