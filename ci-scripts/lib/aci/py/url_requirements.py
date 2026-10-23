"""Lists the ansible-test sanity tests whose pip requirements are direct URLs (internal helper).

Example: ansible-core 2.22, pylint test -> `dill @ https://github.com/...zip`. A PyPI proxy (Nexus)
cannot serve such requirements: in --venv mode, `aci sanity` skips these tests (--skip-test).
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
