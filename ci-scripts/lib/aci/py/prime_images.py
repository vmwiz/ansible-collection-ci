"""
Pre-pulls the container images expected by ansible-test from an internal mirror (Nexus)
and re-tags them with their original name (quay.io/ansible/...).

Why: ansible-test reads its images from ansible_test/_data/completion/docker.txt (not
overridable) and, before every `docker pull`, checks whether the image already exists locally
("Skipping pull of existing image"). By re-tagging the mirrored image with the expected quay.io
name, ansible-test works without Internet access while keeping the alias semantics
(`--docker default` -> all Python versions of the image).

Internal usage (called by `aci prime-images`, inside the venv that contains ansible-core):
    python prime_images.py default [utility] [http] [ubuntu2404 ...] [image:tag ...]

Variables:
    ACI_IMAGE_MIRROR           mirror registry of quay.io, e.g. "nexus.corp.local:8444"
                               (Nexus Docker proxy whose remote URL is https://quay.io)
    ACI_CONTAINER_ENGINE       "podman" (default) or "docker"
    ACI_DRY_RUN=1              prints the commands without running them
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

import ansible_test  # provided by ansible-core

AT_ROOT = Path(ansible_test.__file__).resolve().parent
COMPLETION = AT_ROOT / "_data" / "completion" / "docker.txt"
# "Support" images hard-coded in ansible-test (checked in ansible-core 2.21):
EXTRA_SOURCES = {
    "utility": AT_ROOT / "_internal" / "docker_util.py",  # ansible-test-utility-container (cgroup/audit probes)
    "http": AT_ROOT / "_internal" / "commands" / "integration" / "cloud" / "httptester.py",
    "pypi": AT_ROOT / "_internal" / "pypi_proxy.py",
    "acme": AT_ROOT / "_internal" / "commands" / "integration" / "cloud" / "acme.py",
}
IMAGE_RE = re.compile(r"quay\.io/ansible/[a-z0-9._/-]+:[A-Za-z0-9._-]+")


def completion_images() -> dict[str, list[str]]:
    """alias -> [images] (a 'default' alias may have 2 lines: collection and ansible-core)."""
    result: dict[str, list[str]] = {}
    for line in COMPLETION.read_text().splitlines():
        parts = line.split()
        if not parts:
            continue
        alias = parts[0]
        opts = dict(p.split("=", 1) for p in parts[1:] if "=" in p)
        if "context" in opts and opts["context"] != "collection":
            continue  # we test a collection, not ansible-core
        image = opts.get("image")
        if image:
            result.setdefault(alias, []).append(image)
            if "alias" in opts:
                result.setdefault(opts["alias"], []).append(image)
    return result


def resolve(names: list[str]) -> list[str]:
    known = completion_images()
    images: list[str] = []
    for name in names:
        if name in known:
            images += known[name]
        elif name in EXTRA_SOURCES:
            src = EXTRA_SOURCES[name]
            if src.is_file():
                images += IMAGE_RE.findall(src.read_text())
        elif "/" in name and ":" in name:
            images.append(name)  # explicit image
        else:
            print(f"[prime_images] unknown alias ignored: {name}", file=sys.stderr)
    return list(dict.fromkeys(images))


def run(cmd: list[str]) -> None:
    print("+ " + " ".join(cmd), flush=True)
    if os.environ.get("ACI_DRY_RUN") != "1":
        subprocess.run(cmd, check=True)


def main() -> int:
    mirror = os.environ.get("ACI_IMAGE_MIRROR", "").rstrip("/")
    engine = os.environ.get("ACI_CONTAINER_ENGINE", "podman")
    images = resolve(sys.argv[1:] or ["default"])
    if not mirror:
        print("[prime_images] ACI_IMAGE_MIRROR empty: nothing to do (ansible-test will pull the images itself).")
        return 0
    for image in images:
        if image.startswith("quay.io/"):
            mirrored = mirror + image[len("quay.io"):]
        else:
            mirrored = f"{mirror}/{image}"
        run([engine, "pull", mirrored])
        run([engine, "tag", mirrored, image])
    return 0


if __name__ == "__main__":
    sys.exit(main())
