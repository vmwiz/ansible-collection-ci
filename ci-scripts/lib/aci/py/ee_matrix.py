"""Matrice ansible-core / Python derivee des EE cibles (helper interne de `aci ee-introspect`).

Entree : repertoire contenant, pour chaque EE, <n>.image (reference) et <n>.out (sortie de
`ansible --version` dans l'EE). Verifie pour chaque EE :
  * serie ansible-core connue de la table python-map ;
  * Python de l'EE dans la plage controleur de cette serie (CONTROLLER_PYTHON_VERSIONS) ;
  * version exacte d'ansible-core couverte par requires_ansible (meta/runtime.yml).
Sortie : lignes "serie python version-exacte image" sur stdout ; code 1 et messages si incoherence.
Usage : python ee_matrix.py <dir> <python-map.txt> <racine collection>
"""
import glob
import os
import re
import sys

import yaml
from packaging.specifiers import SpecifierSet
from packaging.version import Version

work, map_path, root = sys.argv[1:4]
pymap = {}
with open(map_path, encoding="utf-8") as f:
    for line in f:
        parts = line.split("#")[0].split()
        if parts:
            pymap[parts[0]] = parts[1:]
req = None
runtime = os.path.join(root, "meta", "runtime.yml")
if os.path.isfile(runtime):
    with open(runtime, encoding="utf-8") as f:
        req = (yaml.safe_load(f) or {}).get("requires_ansible")
spec = SpecifierSet(req) if req else None

errors, rows = [], []
for out in sorted(glob.glob(os.path.join(work, "*.out"))):
    image = open(out[:-4] + ".image", encoding="utf-8").read().strip()
    text = open(out, encoding="utf-8", errors="replace").read()
    core = re.search(r"^ansible \[core ([0-9][^\]\s]*)\]", text, re.M)
    py = re.search(r"^\s*python version = (\d+)\.(\d+)", text, re.M)
    if not core or not py:
        errors.append(f"{image} : sortie de 'ansible --version' illisible :\n{text.strip()[:400]}")
        continue
    full = core.group(1)
    series = ".".join(full.split(".")[:2])
    python = f"{py.group(1)}.{py.group(2)}"
    if series not in pymap:
        errors.append(f"{image} : ansible-core {full} : serie {series} inconnue (python-map : {', '.join(pymap)})")
        continue
    if python not in pymap[series]:
        errors.append(f"{image} : Python {python} hors plage controleur d'ansible-core {series} ({', '.join(sorted(pymap[series]))})")
    if spec is not None and Version(full) not in spec:
        errors.append(f"{image} : ansible-core {full} non couvert par requires_ansible '{req}' (meta/runtime.yml)")
    rows.append(f"{series} {python} {full} {image}")

if not rows and not errors:
    errors.append("aucune EE analysee")
for e in errors:
    print(f"ERREUR : {e}", file=sys.stderr)
for r in rows:
    print(r)
sys.exit(1 if errors else 0)
