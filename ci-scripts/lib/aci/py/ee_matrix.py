"""ansible-core / Python matrix derived from the target EEs (internal helper of `aci ee-introspect`).

Input: a directory holding, for each EE, <n>.image (reference) and <n>.out (output of
`ansible --version` inside the EE). Checks for each EE:
  * ansible-core series known in the python-map table;
  * EE Python within the controller range of that series (CONTROLLER_PYTHON_VERSIONS);
  * exact ansible-core version covered by requires_ansible (meta/runtime.yml).
Output: lines "series python exact-version image" on stdout; exit code 1 and messages on mismatch.
Usage: python ee_matrix.py <dir> <python-map.txt> <collection root>
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
        errors.append(f"{image}: unreadable 'ansible --version' output:\n{text.strip()[:400]}")
        continue
    full = core.group(1)
    series = ".".join(full.split(".")[:2])
    python = f"{py.group(1)}.{py.group(2)}"
    if series not in pymap:
        errors.append(f"{image}: ansible-core {full}: unknown series {series} (python-map: {', '.join(pymap)})")
        continue
    if python not in pymap[series]:
        errors.append(f"{image}: Python {python} outside the controller range of ansible-core {series} ({', '.join(sorted(pymap[series]))})")
    if spec is not None and Version(full) not in spec:
        errors.append(f"{image}: ansible-core {full} not covered by requires_ansible '{req}' (meta/runtime.yml)")
    rows.append(f"{series} {python} {full} {image}")

if not rows and not errors:
    errors.append("no EE analysed")
for e in errors:
    print(f"ERROR: {e}", file=sys.stderr)
for r in rows:
    print(r)
sys.exit(1 if errors else 0)
