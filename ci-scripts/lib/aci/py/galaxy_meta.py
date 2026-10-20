"""Lit galaxy.yml (helper interne de `aci`).

    python galaxy_meta.py <galaxy.yml>               -> "namespace name version"
    python galaxy_meta.py <galaxy.yml> <deps.yml>    -> ecrit les dependances au format requirements.yml
                                                         (rien si aucune) et affiche le meme triplet
Python est de toute facon requis par ansible ; PyYAML est une dependance d'ansible-core.
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
