"""Liste les tests sanity d'ansible-test dont les exigences pip sont des URL directes (helper interne).

Exemple : ansible-core 2.22, test pylint -> `dill @ https://github.com/...zip`. Un proxy PyPI (Nexus)
ne peut pas servir ces exigences : en mode --venv, `aci sanity` ignore ces tests (--skip-test).
"""
import glob
import os
import re

import ansible_test

root = os.path.join(os.path.dirname(ansible_test.__file__), "_data", "requirements")
for path in sorted(glob.glob(os.path.join(root, "sanity.*.txt"))):
    with open(path, encoding="utf-8") as f:
        if re.search(r"^[^#\n]*@\s*https?://", f.read(), re.M):
            print(os.path.basename(path)[len("sanity."):-len(".txt")])
