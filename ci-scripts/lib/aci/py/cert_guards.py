"""Red Hat certification guards (internal helper of `aci certification`).

Explicit checks, with clear messages, of rules that the certification enforces:
  1. tests/sanity/ignore-X.Y.txt: for plugins/ and roles/ paths, only entries of the closed list are
     allowed (same logic as the ansible-lint "sanity" rule 26.4.0: test compared as is, files
     ignore-2.9 to ignore-2.12 not evaluated).
     Tracked exception: an "aci-derogation: <justification>" comment on the line -> warning
     (the Red Hat certification will still refuse it).
  2. .ansible-lint: profile absent or "production", no mandatory rule in skip_list / warn_list /
     .ansible-lint-ignore, exclude_paths covers neither plugins/ nor roles/ nor extensions/ (except extensions/molecule).
  3. meta/runtime.yml: requires_ansible present, lower bound in ACI_CERT_SUPPORTED_CORES.
Usage: python cert_guards.py <collection root>   (ACI_CERT_* variables from share/aci/certification.env)
Exit code 1 if there is at least one error.
"""
import glob
import os
import re
import sys

import yaml

root = sys.argv[1]
env = os.environ.get
allowed = set(env("ACI_CERT_SANITY_IGNORE_ALLOWED", "").split())
mandatory = env("ACI_CERT_LINT_MANDATORY_RULES", "").split()
protected = env("ACI_CERT_LINT_PROTECTED_PATHS", "").split()
allowed_excludes = [p.strip("/") for p in env("ACI_CERT_LINT_ALLOWED_EXCLUDES", "").split()]
cores = env("ACI_CERT_SANITY_CORES", "").split()
supported = env("ACI_CERT_SUPPORTED_CORES", "").split()
errors, warnings = [], []

# 1. sanity ignores
for path in sorted(glob.glob(os.path.join(root, "tests", "sanity", "ignore-*.txt"))):
    series = os.path.basename(path)[len("ignore-"):-len(".txt")]
    if series in ("2.9", "2.10", "2.11", "2.12"):
        continue  # not evaluated by the ansible-lint rule
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            body, _, comment = line.partition("#")
            if not body.strip():
                continue
            parts = body.split()
            if len(parts) < 2:
                errors.append(f"{os.path.relpath(path, root)}:{n}: invalid line '{line.strip()}'")
                continue
            if parts[0].split("/")[0] not in ("plugins", "roles"):
                continue  # the rule only checks plugins/ and roles/
            entry = parts[1]
            if entry in allowed:
                continue
            where = f"{os.path.relpath(path, root)}:{n}: ignore '{entry}' not in the list allowed by the certification"
            if "aci-derogation:" in comment:
                warnings.append(where + f" (derogation: {comment.split('aci-derogation:', 1)[1].strip()})")
            else:
                errors.append(where + " (fix the code, or add a '# aci-derogation: <reason>' comment for internal use)")

# 2. ansible-lint
cfg_path = next((p for p in (os.path.join(root, n) for n in (".ansible-lint", ".ansible-lint.yml", ".ansible-lint.yaml", ".config/ansible-lint.yml")) if os.path.isfile(p)), None)
cfg = {}
if cfg_path:
    with open(cfg_path, encoding="utf-8") as f:
        cfg = yaml.safe_load(f) or {}
    rel = os.path.relpath(cfg_path, root)
    if cfg.get("profile") not in (None, "production"):
        errors.append(f"{rel}: profile '{cfg.get('profile')}': the certification requires 'production'")
    for key, level in (("skip_list", errors), ("warn_list", errors)):
        for rule in cfg.get(key) or []:
            if str(rule) in mandatory or str(rule).split("[")[0] in [m for m in mandatory if "[" not in m]:
                level.append(f"{rel}: mandatory rule '{rule}' in {key} (cannot be skipped or ignored for certification)")
    for p in cfg.get("exclude_paths") or []:
        norm = str(p).strip("/").lstrip("./")
        if any(norm == a or norm.startswith(a + "/") for a in allowed_excludes):
            continue
        for prot in protected:
            if norm == prot or norm.startswith(prot + "/") or prot.startswith(norm + "/") or norm in ("", "."):
                errors.append(f"{rel}: exclude_paths '{p}' covers {prot}/ (forbidden for certification)")
                break
ignore_file = os.path.join(root, ".ansible-lint-ignore")
if os.path.isfile(ignore_file):
    with open(ignore_file, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            parts = line.partition("#")[0].split()
            if len(parts) >= 2 and (parts[1] in mandatory or parts[1].split("[")[0] in [m for m in mandatory if "[" not in m]):
                errors.append(f".ansible-lint-ignore:{n}: mandatory rule '{parts[1]}' ignored")

# 3. requires_ansible
runtime = os.path.join(root, "meta", "runtime.yml")
req = None
if os.path.isfile(runtime):
    with open(runtime, encoding="utf-8") as f:
        req = (yaml.safe_load(f) or {}).get("requires_ansible")
if not req:
    errors.append("meta/runtime.yml: requires_ansible missing (mandatory)")
else:
    m = re.search(r">=?\s*(\d+)\.(\d+)", str(req))
    if not m:
        errors.append(f"meta/runtime.yml: requires_ansible '{req}' has no >=X.Y lower bound")
    elif f"{m.group(1)}.{m.group(2)}" not in supported:
        errors.append(f"meta/runtime.yml: lower bound {m.group(1)}.{m.group(2)} of requires_ansible '{req}' "
                      f"not supported by AAP (accepted: {', '.join(supported)}; 2.19 = Technology Preview)")

for w in warnings:
    print(f"WARNING: {w}")
for e in errors:
    print(f"ERROR: {e}")
print(f"certification guards: {len(errors)} error(s), {len(warnings)} warning(s)")
sys.exit(1 if errors else 0)
