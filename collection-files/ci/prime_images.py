"""
Pre-tire les images de conteneur attendues par ansible-test depuis un miroir interne (Nexus)
puis les re-tague sous leur nom d'origine (quay.io/ansible/...).

Pourquoi : ansible-test lit ses images dans ansible_test/_data/completion/docker.txt (non
surchargeable) et, avant chaque `docker pull`, verifie si l'image existe deja localement
("Skipping pull of existing image"). En re-taguant l'image miroir sous le nom quay.io attendu,
ansible-test fonctionne sans acces internet tout en conservant la semantique des alias
(`--docker default` -> toutes les versions Python de l'image).

Usage (dans le venv contenant ansible-core) :
    python ci/prime_images.py default [utility] [http] [ubuntu2404 ...] [image:tag ...]

Variables :
    ANSIBLE_TEST_IMAGE_MIRROR  registre miroir de quay.io, ex. "nexus.corp.local:8444"
                               (proxy Docker Nexus dont l'URL distante est https://quay.io)
    CONTAINER_ENGINE           "docker" (defaut) ou "podman"
    DRY_RUN=1                  affiche les commandes sans les executer
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

import ansible_test  # fourni par ansible-core

AT_ROOT = Path(ansible_test.__file__).resolve().parent
COMPLETION = AT_ROOT / "_data" / "completion" / "docker.txt"
# Images "support" codees en dur dans ansible-test (verifiees dans ansible-core 2.21) :
EXTRA_SOURCES = {
    "utility": AT_ROOT / "_internal" / "docker_util.py",  # ansible-test-utility-container (sondes cgroup/audit)
    "http": AT_ROOT / "_internal" / "commands" / "integration" / "cloud" / "httptester.py",
    "pypi": AT_ROOT / "_internal" / "pypi_proxy.py",
    "acme": AT_ROOT / "_internal" / "commands" / "integration" / "cloud" / "acme.py",
}
IMAGE_RE = re.compile(r"quay\.io/ansible/[a-z0-9._/-]+:[A-Za-z0-9._-]+")


def completion_images() -> dict[str, list[str]]:
    """alias -> [images] (un alias 'default' peut avoir 2 lignes : collection et ansible-core)."""
    result: dict[str, list[str]] = {}
    for line in COMPLETION.read_text().splitlines():
        parts = line.split()
        if not parts:
            continue
        alias = parts[0]
        opts = dict(p.split("=", 1) for p in parts[1:] if "=" in p)
        if "context" in opts and opts["context"] != "collection":
            continue  # on teste une collection, pas ansible-core
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
            images.append(name)  # image explicite
        else:
            print(f"[prime_images] alias inconnu ignore : {name}", file=sys.stderr)
    return list(dict.fromkeys(images))


def run(cmd: list[str]) -> None:
    print("+ " + " ".join(cmd), flush=True)
    if os.environ.get("DRY_RUN") != "1":
        subprocess.run(cmd, check=True)


def main() -> int:
    mirror = os.environ.get("ANSIBLE_TEST_IMAGE_MIRROR", "").rstrip("/")
    engine = os.environ.get("CONTAINER_ENGINE", "docker")
    images = resolve(sys.argv[1:] or ["default"])
    if not mirror:
        print("[prime_images] ANSIBLE_TEST_IMAGE_MIRROR vide : rien a faire.")
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
