"""Garde-fous de certification Red Hat (helper interne de `aci certification`).

Controles explicites, avec messages clairs, de regles que la certification applique :
  1. tests/sanity/ignore-X.Y.txt : pour les chemins plugins/ et roles/, seules les entrees de la liste
     fermee sont admises (meme logique que la regle ansible-lint "sanity" 26.4.0 : test compare tel quel,
     fichiers ignore-2.9 a ignore-2.12 non evalues).
     Derogation tracee : commentaire "aci-derogation: <justification>" sur la ligne -> avertissement
     (la certification Red Hat, elle, la refusera quand meme).
  2. .ansible-lint : profile absent ou "production", aucune regle obligatoire dans skip_list / warn_list /
     .ansible-lint-ignore, exclude_paths ne couvre ni plugins/ ni roles/ ni extensions/ (sauf extensions/molecule).
  3. meta/runtime.yml : requires_ansible present, borne basse dans ACI_CERT_SUPPORTED_CORES.
Usage : python cert_guards.py <racine collection>   (variables ACI_CERT_* de share/aci/certification.env)
Sortie 1 si au moins une erreur.
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

# 1. ignores sanity
for path in sorted(glob.glob(os.path.join(root, "tests", "sanity", "ignore-*.txt"))):
    series = os.path.basename(path)[len("ignore-"):-len(".txt")]
    if series in ("2.9", "2.10", "2.11", "2.12"):
        continue  # non evalues par la regle ansible-lint
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            body, _, comment = line.partition("#")
            if not body.strip():
                continue
            parts = body.split()
            if len(parts) < 2:
                errors.append(f"{os.path.relpath(path, root)}:{n}: ligne invalide '{line.strip()}'")
                continue
            if parts[0].split("/")[0] not in ("plugins", "roles"):
                continue  # la regle ne controle que plugins/ et roles/
            entry = parts[1]
            if entry in allowed:
                continue
            where = f"{os.path.relpath(path, root)}:{n}: ignore '{entry}' hors liste autorisee par la certification"
            if "aci-derogation:" in comment:
                warnings.append(where + f" (derogation : {comment.split('aci-derogation:', 1)[1].strip()})")
            else:
                errors.append(where + " (corriger le code, ou commentaire '# aci-derogation: <raison>' pour un usage interne)")

# 2. ansible-lint
cfg_path = next((p for p in (os.path.join(root, n) for n in (".ansible-lint", ".ansible-lint.yml", ".ansible-lint.yaml", ".config/ansible-lint.yml")) if os.path.isfile(p)), None)
cfg = {}
if cfg_path:
    with open(cfg_path, encoding="utf-8") as f:
        cfg = yaml.safe_load(f) or {}
    rel = os.path.relpath(cfg_path, root)
    if cfg.get("profile") not in (None, "production"):
        errors.append(f"{rel}: profile '{cfg.get('profile')}' : la certification impose 'production'")
    for key, level in (("skip_list", errors), ("warn_list", errors)):
        for rule in cfg.get(key) or []:
            if str(rule) in mandatory or str(rule).split("[")[0] in [m for m in mandatory if "[" not in m]:
                level.append(f"{rel}: regle obligatoire '{rule}' dans {key} (ni sautee ni ignoree en certification)")
    for p in cfg.get("exclude_paths") or []:
        norm = str(p).strip("/").lstrip("./")
        if any(norm == a or norm.startswith(a + "/") for a in allowed_excludes):
            continue
        for prot in protected:
            if norm == prot or norm.startswith(prot + "/") or prot.startswith(norm + "/") or norm in ("", "."):
                errors.append(f"{rel}: exclude_paths '{p}' couvre {prot}/ (interdit en certification)")
                break
ignore_file = os.path.join(root, ".ansible-lint-ignore")
if os.path.isfile(ignore_file):
    with open(ignore_file, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            parts = line.partition("#")[0].split()
            if len(parts) >= 2 and (parts[1] in mandatory or parts[1].split("[")[0] in [m for m in mandatory if "[" not in m]):
                errors.append(f".ansible-lint-ignore:{n}: regle obligatoire '{parts[1]}' ignoree")

# 3. requires_ansible
runtime = os.path.join(root, "meta", "runtime.yml")
req = None
if os.path.isfile(runtime):
    with open(runtime, encoding="utf-8") as f:
        req = (yaml.safe_load(f) or {}).get("requires_ansible")
if not req:
    errors.append("meta/runtime.yml : requires_ansible absent (obligatoire)")
else:
    m = re.search(r">=?\s*(\d+)\.(\d+)", str(req))
    if not m:
        errors.append(f"meta/runtime.yml : requires_ansible '{req}' sans borne basse >=X.Y")
    elif f"{m.group(1)}.{m.group(2)}" not in supported:
        errors.append(f"meta/runtime.yml : borne basse {m.group(1)}.{m.group(2)} de requires_ansible '{req}' "
                      f"non supportee par AAP (accepte : {', '.join(supported)} ; 2.19 = Technology Preview)")

for w in warnings:
    print(f"ATTENTION : {w}")
for e in errors:
    print(f"ERREUR : {e}")
print(f"garde-fous certification : {len(errors)} erreur(s), {len(warnings)} avertissement(s)")
sys.exit(1 if errors else 0)
