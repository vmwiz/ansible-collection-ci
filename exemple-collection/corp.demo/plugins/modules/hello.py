#!/usr/bin/python
# -*- coding: utf-8 -*-
# Copyright: (c) 2026, coreOps
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)
from __future__ import annotations

DOCUMENTATION = r"""
module: hello
short_description: Say hello
version_added: 1.0.0
description:
  - Returns a greeting.
author:
  - coreOps (@coreops)
options:
  name:
    description: Who to greet.
    type: str
    default: world
"""

EXAMPLES = r"""
- name: Greet
  corp.demo.hello:
    name: Gilles
"""

RETURN = r"""
msg:
  description: The greeting.
  returned: always
  type: str
  sample: Hello Gilles
"""

from ansible.module_utils.basic import AnsibleModule


def main():
    module = AnsibleModule(argument_spec=dict(name=dict(type="str", default="world")), supports_check_mode=True)
    module.exit_json(changed=False, msg="Hello %s" % module.params["name"])


if __name__ == "__main__":
    main()
