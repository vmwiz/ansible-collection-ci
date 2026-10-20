# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)
from __future__ import (absolute_import, division, print_function)

__metaclass__ = type

from ansible_collections.corp.demo.plugins.modules import hello


def test_module_has_main():
    assert callable(hello.main)
