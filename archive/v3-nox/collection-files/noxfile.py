# -*- coding: utf-8 -*-
"""
noxfile.py - logique CI d'une collection Ansible, partagee entre Jenkins et GitLab CI.

Principe : les pipelines (Jenkinsfile / .gitlab-ci.yml) ne contiennent AUCUNE logique
metier ; ils appellent uniquement `nox -s <session>`. Le meme fichier fonctionne en local.

Concu pour un environnement airgap :
  * PyPI       -> via PIP_INDEX_URL / /etc/pip.conf (Nexus pypi-proxy/group)
  * Galaxy     -> via ci/ansible.cfg (Nexus format "Ansible", >= 3.93) passe en ANSIBLE_CONFIG
                  uniquement aux appels ansible-galaxy
  * Conteneurs -> les images quay.io/ansible/* attendues par ansible-test sont tirees depuis
                  le miroir Nexus puis re-taggees sous leur nom d'origine (ci/prime_images.py),
                  ansible-test ne tente alors plus de les telecharger.
  * pip DANS les conteneurs ansible-test -> option (cachee mais supportee) --pypi-endpoint.

Sessions (nox -l pour la liste) :
  lint, docs, build, galaxy-importer, publish,
  security-scan (ansible-security-scanner, 100 % local), spotter (instance Spotter privee),
  molecule (optionnel : roles / scenarios multi-noeuds, podman requis),
  images-<core>, sanity-<core>, units-<core>, integration-<core>

Deux familles d'agents :
  * SANS moteur de conteneurs (pod OpenShift restreint) : lint, docs, build, galaxy-importer,
    security-scan, spotter, et sanity/units avec ANSIBLE_TEST_MODE=venv ;
  * AVEC podman/docker (VM "ansible-builder") : sanity/units en mode docker, integration, molecule.

Variables d'environnement utiles :
  ANSIBLE_CORE_VERSIONS       "2.19 2.20 2.21 2.22"  matrice ansible-core (series X.Y)
  ANSIBLE_CORE_PRERELEASE     "2.22" (defaut)   series encore en pre-version (beta/rc acceptees)
  ANSIBLE_TEST_VENV_URL_REQS  "allow" : ne pas ignorer les tests sanity dont les exigences sont des URL
                              directes (2.22 : pylint -> dill @ github.com), ignores par defaut en venv
  ANSIBLE_CI_PYTHON_<X_Y>     force le Python controleur d'une serie (defaut : le plus recent supporte
                              ET present, ex. 2.19 -> 3.12, 2.20 a 2.22 -> 3.14 sur l'image UBI 9)
  ANSIBLE_CORE_DEFAULT        serie utilisee par lint/build/docs (defaut : la plus recente hors pre-version)
  ANSIBLE_TEST_IMAGE_MIRROR   ex. "nexus.corp.local:8444" (proxy docker de quay.io) ; vide = pas de re-tag
  ANSIBLE_TEST_PYPI_ENDPOINT  ex. "https://nexus.corp.local/repository/pypi-group/simple/"
  ANSIBLE_TEST_DOCKER         image/alias ansible-test pour integration (defaut "default")
  ANSIBLE_TEST_DOCKER_NETWORK reseau docker pour integration (optionnel)
  ANSIBLE_TEST_COVERAGE       "1" pour activer --coverage + rapport XML
  ANSIBLE_TEST_MODE           "docker" (defaut) ou "venv" (sanity/units sans moteur de conteneurs)
  ANSIBLE_TEST_PREFER_PODMAN  "1" : ansible-test choisit podman meme si un binaire docker existe
  SPOTTER_ENDPOINT            URL API de l'instance Spotter privee (ex. https://spotter.corp.local/api)
  SPOTTER_TOKEN               jeton API Spotter (credential CI) ; SPOTTER_CACERT : AC interne
  SPOTTER_ANSIBLE_VERSION     version cible pour Spotter (defaut 2.20, max accepte par la CLI 6.6)
  SPOTTER_EXPORT_ONLY         "1" : aucun appel reseau, export du payload (--export-payload)
  SECURITY_SCAN_SEVERITY      seuil d'affichage ansible-security-scanner (l'echec reste HIGH/CRITICAL)
  MOLECULE_IMAGES             alias ansible-test a pre-tirer pour Molecule (defaut "ubuntu2404 fedora43")
  CONTAINER_ENGINE            "docker" (defaut) ou "podman"
  ANSIBLE_CI_WORKDIR          repertoire de travail HORS depot (defaut : $TMPDIR/ansible-ci-<repo>)
  GALAXY_PUBLISH_SERVER       nom d'un serveur de ci/ansible.cfg (ex. nexus_hosted) ou URL
"""

from __future__ import annotations

import os
import shutil
import tempfile
from pathlib import Path

import nox
import yaml  # PyYAML : present dans l'image runner (voir infra/runner-image/Dockerfile)

nox.options.default_venv_backend = "venv"
nox.options.reuse_existing_virtualenvs = True
nox.options.error_on_external_run = True
nox.options.sessions = ["lint", "build"]

ROOT = Path(__file__).parent.resolve()
CI_DIR = ROOT / "ci"
REPORTS = ROOT / "reports"
DIST = ROOT / "dist"
# IMPORTANT : l'arbre de travail doit etre HORS du depot git. Sinon ansible-test detecte le depot
# parent, liste les fichiers via git (ou .nox/ est ignore) et saute toutes les cibles
# ("WARNING: All targets skipped").
WORK = Path(os.environ.get("ANSIBLE_CI_WORKDIR") or tempfile.gettempdir()) / f"ansible-ci-{ROOT.name}"

_GALAXY = yaml.safe_load((ROOT / "galaxy.yml").read_text(encoding="utf-8"))
NAMESPACE: str = _GALAXY["namespace"]
NAME: str = _GALAXY["name"]
VERSION: str = str(_GALAXY["version"])
TARBALL = DIST / f"{NAMESPACE}-{NAME}-{VERSION}.tar.gz"

CORE_VERSIONS = os.environ.get("ANSIBLE_CORE_VERSIONS", "2.19 2.20 2.21 2.22").split()
# 2.22 est en release candidate au 2026-10-20 : retirer de cette liste a sa GA.
CORE_PRERELEASE = set(os.environ.get("ANSIBLE_CORE_PRERELEASE", "2.22").split())
DEFAULT_CORE = os.environ.get(
    "ANSIBLE_CORE_DEFAULT", [c for c in CORE_VERSIONS if c not in CORE_PRERELEASE][-1]
)

# Pythons acceptes comme CONTROLEUR par ansible-test (CONTROLLER_PYTHON_VERSIONS de
# test/lib/ansible_test/_util/target/common/constants.py, branches stable-X.Y, releve 2026-10-20 ;
# coherent avec requires-python : 2.19 >=3.11, 2.20/2.21 >=3.12, 2.22 >=3.13).
CONTROLLER_PYTHONS = {
    "2.19": ("3.11", "3.12", "3.13"),
    "2.20": ("3.12", "3.13", "3.14"),
    "2.21": ("3.12", "3.13", "3.14"),
    "2.22": ("3.13", "3.14", "3.15"),
    "milestone": ("3.13", "3.14", "3.15"),
    "devel": ("3.13", "3.14", "3.15"),
}


def _controller_python(core: str) -> str:
    """Python le plus recent supporte par la serie ET present sur l'agent (sinon le plus recent supporte).
    Surcharge possible : ANSIBLE_CI_PYTHON_<X_Y>=3.12 (ex. ANSIBLE_CI_PYTHON_2_21)."""
    forced = os.environ.get("ANSIBLE_CI_PYTHON_" + core.replace(".", "_").upper())
    if forced:
        return forced
    supported = CONTROLLER_PYTHONS.get(core, CONTROLLER_PYTHONS["devel"])
    for version in reversed(supported):
        if shutil.which(f"python{version}"):
            return version
    return supported[-1]


DEFAULT_PYTHON = _controller_python(DEFAULT_CORE)

CONSTRAINTS = CI_DIR / "constraints.txt"
ANSIBLE_CFG = CI_DIR / "ansible.cfg"

# Fichiers de dependances de collections (conventions observees dans ansible-collections/*)
COLLECTION_REQUIREMENTS = {
    "lint": ["tests/requirements.yml"],
    "sanity": ["tests/requirements.yml"],
    "units": ["tests/requirements.yml", "tests/unit/requirements.yml"],
    "integration": ["tests/requirements.yml", "tests/integration/requirements.yml"],
    "molecule": ["tests/requirements.yml", "extensions/molecule/requirements.yml"],
}
# ansible-lint verifie aussi les playbooks Molecule : il lui faut leurs collections.
COLLECTION_REQUIREMENTS["lint"] = COLLECTION_REQUIREMENTS["molecule"]

TEST_MODE = os.environ.get("ANSIBLE_TEST_MODE", "docker")
if TEST_MODE not in ("docker", "venv"):
    raise RuntimeError(f"ANSIBLE_TEST_MODE={TEST_MODE!r} : valeurs possibles 'docker' ou 'venv'")

# Elements a ne pas copier dans l'arborescence ansible_collections/<ns>/<name>
_TOP_LEVEL_EXCLUDES = {".git", ".nox", ".tox", ".cache", "reports", "dist", ".venv"}


# --------------------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------------------
def _core_spec(core: str) -> list[str]:
    """Arguments pip pour installer une serie ansible-core X.Y depuis le proxy PyPI."""
    if core in ("devel", "milestone"):
        # Pas sur PyPI : fournir une URL interne (Nexus raw, miroir git...) via l'env.
        url = os.environ.get(f"ANSIBLE_CORE_SRC_{core.upper()}")
        if not url:
            raise RuntimeError(
                f"ansible-core '{core}' n'est pas publie sur PyPI : definir ANSIBLE_CORE_SRC_{core.upper()} "
                "(ex. tarball miroir dans un depot Nexus raw)."
            )
        return [url]
    major, minor = (int(x) for x in core.split("."))
    if core in CORE_PRERELEASE:
        # Un specificateur contenant une pre-version autorise les pre-versions d'ansible-core
        # seulement (pas de --pre global) ; ">=2.22" seul exclurait 2.22.0rc1 (PEP 440).
        return [f"ansible-core>={major}.{minor}.0a0,<{major}.{minor + 1}"]
    return [f"ansible-core>={major}.{minor},<{major}.{minor + 1}"]


def _yaml_files() -> list[str]:
    """Fichiers YAML du depot (hors .nox, dist, reports, tests/output...)."""
    files = []
    for path in sorted(ROOT.rglob("*")):
        rel = path.relative_to(ROOT)
        if rel.parts[0] in _TOP_LEVEL_EXCLUDES or rel.parts[:2] == ("tests", "output"):
            continue
        if path.is_file() and path.suffix in (".yml", ".yaml"):
            files.append(str(rel))
    return files


def _pip_constraints() -> list[str]:
    return ["-c", str(CONSTRAINTS)] if CONSTRAINTS.is_file() else []


def _galaxy_env() -> dict[str, str]:
    """ANSIBLE_CONFIG uniquement pour ansible-galaxy (ne pas polluer ansible-test)."""
    env = {}
    if "ANSIBLE_CONFIG" not in os.environ and ANSIBLE_CFG.is_file():
        env["ANSIBLE_CONFIG"] = str(ANSIBLE_CFG)
    return env


def _ignore(src: str, names: list[str]) -> set[str]:
    src_path = Path(src).resolve()
    ignored = {"__pycache__"} & set(names)
    if src_path == ROOT:
        ignored |= _TOP_LEVEL_EXCLUDES & set(names)
    if src_path == ROOT / "tests":
        ignored |= {"output"} & set(names)
    return ignored


def _prepare_tree(session: nox.Session, kind: str) -> tuple[Path, Path]:
    """
    ansible-test exige le chemin .../ansible_collections/<namespace>/<name>.
    On copie la collection dans un arbre propre a la session (parallelisable sans conflit)
    et on installe les dependances de collections A COTE (meme racine ansible_collections) :
    ansible-test les embarque alors automatiquement dans le conteneur de test.
    Retourne (racine contenant ansible_collections, chemin de la collection).
    """
    base = WORK / session.name
    dest = base / "ansible_collections" / NAMESPACE / NAME
    if base.exists():
        shutil.rmtree(base)
    shutil.copytree(ROOT, dest, ignore=_ignore, symlinks=True)

    req_files = [ROOT / p for p in COLLECTION_REQUIREMENTS.get(kind, [])]
    deps = _GALAXY.get("dependencies") or {}
    if deps:
        gen = base / "galaxy-deps.yml"
        gen.write_text(
            yaml.safe_dump({"collections": [{"name": n, "version": str(v)} for n, v in deps.items()]}),
            encoding="utf-8",
        )
        req_files.insert(0, gen)
    for req in req_files:
        if req.is_file():
            # ANSIBLE_COLLECTIONS_PATH=base : sinon une collection deja presente ailleurs
            # (~/.ansible/collections) est jugee "deja installee" et absente de l'arbre de test.
            session.run(
                "ansible-galaxy", "collection", "install", "-r", str(req), "-p", str(base),
                env={**_galaxy_env(), "ANSIBLE_COLLECTIONS_PATH": str(base)},
            )
    return base, dest


def _prime_images(session: nox.Session, *aliases: str) -> None:
    if not os.environ.get("ANSIBLE_TEST_IMAGE_MIRROR"):
        session.log("ANSIBLE_TEST_IMAGE_MIRROR vide : ansible-test tirera lui-meme les images.")
        return
    session.run("python", str(CI_DIR / "prime_images.py"), *aliases)


def _seed_get_pip(session: nox.Session) -> None:
    """Mode venv : ansible-test amorce pip avec un script get-pip telecharge sur Internet.
    On depose a sa place ci/get_pip_offline.py (ensurepip + pip depuis /etc/pip.conf)."""
    session.run("python", str(CI_DIR / "get_pip_offline.py"), "--seed")


_URL_REQS_SNIPPET = r"""
import glob, os, re, ansible_test
root = os.path.join(os.path.dirname(ansible_test.__file__), "_data", "requirements")
for path in sorted(glob.glob(os.path.join(root, "sanity.*.txt"))):
    with open(path, encoding="utf-8") as f:
        if re.search(r"^[^#\n]*@\s*https?://", f.read(), re.M):
            print(os.path.basename(path)[len("sanity."):-len(".txt")])
"""


def _venv_sanity_skips(session: nox.Session) -> list[str]:
    """Mode venv en airgap : certaines exigences sanity d'ansible-test sont des URL directes (ex. 2.22 :
    `dill @ https://github.com/...` pour pylint), que ni /etc/pip.conf ni Nexus PyPI ne peuvent servir.
    Ces tests sont ignores ici (ils tournent en mode docker, ou les venvs sont pre-construits dans
    default-test-container). ANSIBLE_TEST_VENV_URL_REQS=allow pour ne rien ignorer."""
    if os.environ.get("ANSIBLE_TEST_VENV_URL_REQS") == "allow":
        return []
    out = session.run("python", "-c", _URL_REQS_SNIPPET, silent=True) or ""
    tests = out.split()
    skips: list[str] = []
    for test in tests:
        session.warn(f"sanity '{test}' ignore en mode venv : exigence pip par URL directe (hors Nexus PyPI)")
        skips += ["--skip-test", test]
    return skips


def _ansible_test_common() -> list[str]:
    args = ["-v", "--color"]
    endpoint = os.environ.get("ANSIBLE_TEST_PYPI_ENDPOINT")
    if endpoint and TEST_MODE == "docker":
        # En mode venv, pip lit PIP_INDEX_URL / /etc/pip.conf : --pypi-endpoint est inutile.
        # Option masquee de ansible-test (argparse.SUPPRESS) mais implementee : ecrit ~/.pip/pip.conf
        # (index-url + trusted-host) dans le controleur et les cibles gerees par ansible-test.
        args += ["--pypi-endpoint", endpoint]
    return args


def _collect(session: nox.Session, dest: Path) -> None:
    out = dest / "tests" / "output"
    target = REPORTS / session.name
    if out.is_dir():
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(out, target)
        session.log(f"Rapports copies dans {target}")


def _run_ansible_test(session: nox.Session, dest: Path, args: list[str]) -> None:
    coverage = os.environ.get("ANSIBLE_TEST_COVERAGE") == "1"
    if coverage:
        args = args + ["--coverage"]
    with session.chdir(dest):
        try:
            session.run("ansible-test", *args, *session.posargs)
            if coverage:
                session.run(
                    "ansible-test", "coverage", "xml", "-v", "--requirements",
                    "--group-by", "command", "--group-by", "version",
                )
        finally:
            _collect(session, dest)


# --------------------------------------------------------------------------------------
# Sessions "statiques"
# --------------------------------------------------------------------------------------
@nox.session(name="lint", python=DEFAULT_PYTHON)
def lint(session: nox.Session) -> None:
    """yamllint + ansible-lint (--offline) + antsibull-changelog lint."""
    session.install(*_core_spec(DEFAULT_CORE), "-r", str(CI_DIR / "requirements-lint.txt"), *_pip_constraints())
    cfg = ROOT / ".yamllint" if (ROOT / ".yamllint").is_file() else CI_DIR / "yamllint.yml"
    session.run("yamllint", "--strict", "-c", str(cfg), *_yaml_files())
    if (ROOT / "changelogs" / "config.yaml").is_file():
        session.run("antsibull-changelog", "lint")
    base, _dest = _prepare_tree(session, "lint")
    # --offline : pas d'installation de requirements.yml ni de rafraichissement des schemas (internet)
    session.run(
        "ansible-lint", "--offline", "--exclude", ".nox", "--exclude", "dist", "--exclude", "reports",
        *session.posargs,
        env={"ANSIBLE_COLLECTIONS_PATH": str(base)},
    )


@nox.session(name="docs", python=DEFAULT_PYTHON)
def docs(session: nox.Session) -> None:
    """Validation de la documentation des plugins (antsibull-docs lint-collection-docs)."""
    session.install(*_core_spec(DEFAULT_CORE), "-r", str(CI_DIR / "requirements-docs.txt"), *_pip_constraints())
    base, dest = _prepare_tree(session, "lint")
    session.run(
        "antsibull-docs", "lint-collection-docs", "--plugin-docs", str(dest),
        env={"ANSIBLE_COLLECTIONS_PATH": str(base)},
    )


@nox.session(name="build", python=DEFAULT_PYTHON)
def build(session: nox.Session) -> None:
    """ansible-galaxy collection build -> dist/<ns>-<name>-<version>.tar.gz"""
    session.install(*_core_spec(DEFAULT_CORE), *_pip_constraints())
    DIST.mkdir(exist_ok=True)
    session.run("ansible-galaxy", "collection", "build", "--force", "--output-path", str(DIST), str(ROOT))


@nox.session(name="galaxy-importer", python=DEFAULT_PYTHON)
def galaxy_importer(session: nox.Session) -> None:
    """Validation de l'artefact comme le ferait Galaxy / Automation Hub (galaxy-importer)."""
    if not TARBALL.is_file():
        session.error(f"{TARBALL} absent : lancer d'abord `nox -s build`.")
    session.install(*_core_spec(DEFAULT_CORE), "-r", str(CI_DIR / "requirements-import.txt"), *_pip_constraints())
    env = {}
    cfg = CI_DIR / "galaxy-importer.cfg"
    if cfg.is_file():
        env["GALAXY_IMPORTER_CONFIG"] = str(cfg)
    out = REPORTS / "galaxy-importer"
    out.mkdir(parents=True, exist_ok=True)
    with session.chdir(out):  # galaxy-importer ecrit importer_result.json dans le repertoire courant
        session.run("python", "-m", "galaxy_importer.main", str(TARBALL), env=env)


@nox.session(name="publish", python=DEFAULT_PYTHON)
def publish(session: nox.Session) -> None:
    """Publication de l'artefact vers le Nexus 'ansible-hosted' (ou un Automation Hub prive)."""
    server = os.environ.get("GALAXY_PUBLISH_SERVER")
    if not server:
        session.error("GALAXY_PUBLISH_SERVER non defini (nom de serveur de ci/ansible.cfg ou URL).")
    if not TARBALL.is_file():
        session.error(f"{TARBALL} absent : lancer d'abord `nox -s build`.")
    session.install(*_core_spec(DEFAULT_CORE), *_pip_constraints())
    # Le jeton est lu par ansible-galaxy dans ANSIBLE_GALAXY_SERVER_<NOM>_TOKEN (credential CI).
    session.run(
        "ansible-galaxy", "collection", "publish", str(TARBALL), "--server", server, *session.posargs,
        env=_galaxy_env(),
    )


@nox.session(name="security-scan", python=DEFAULT_PYTHON)
def security_scan(session: nox.Session) -> None:
    """ansible-security-scanner : analyse statique 100 % locale (aucun appel reseau hors --*-comment)."""
    session.install("-r", str(CI_DIR / "requirements-security.txt"), *_pip_constraints())
    out = REPORTS / "security"
    out.mkdir(parents=True, exist_ok=True)
    # Le scanner n'a pas d'option d'exclusion : on analyse une copie propre (sans .nox/, dist/, reports/...).
    src = WORK / session.name / "src"
    if src.exists():
        shutil.rmtree(src)
    shutil.copytree(ROOT, src, ignore=_ignore, symlinks=True)
    common = ["ansible-security-scanner", "--directory", str(src), "--jobs", "4"]
    severity = os.environ.get("SECURITY_SCAN_SEVERITY")
    if severity:
        common += ["--severity", severity]
    # Rapports "informatifs" (exit 0), puis passe bloquante : code retour != 0 si HIGH/CRITICAL.
    session.run(*common, "--format", "sarif", "--output", str(out / "ansible-security-scanner.sarif"), "--exit-zero")
    if os.environ.get("GITLAB_CI"):
        session.run(*common, "--format", "gitlab-sast", "--output", str(out / "gl-sast-report.json"), "--exit-zero")
    session.run(*common, "--format", "junit", "--output", str(out / "ansible-security-scanner.xml"), *session.posargs)


@nox.session(name="spotter", python=DEFAULT_PYTHON)
def spotter(session: nox.Session) -> None:
    """Steampunk Spotter vers l'instance PRIVEE (SPOTTER_ENDPOINT + SPOTTER_TOKEN)."""
    session.install("-r", str(CI_DIR / "requirements-security.txt"), *_pip_constraints())
    out = REPORTS / "spotter"
    out.mkdir(parents=True, exist_ok=True)
    scan = [
        "--no-color", "scan", "--origin", "ci", "--no-progress", "--no-docs-url",
        "--ansible-version", os.environ.get("SPOTTER_ANSIBLE_VERSION", "2.20"),
        "--exclude-paths", ".nox", "--exclude-paths", "dist", "--exclude-paths", "reports",
    ]
    if os.environ.get("SPOTTER_EXPORT_ONLY") == "1":
        # Mode deconnecte : analyse locale + export, rien n'est envoye (a rejouer avec --import-payload).
        session.run("spotter", *scan, "--export-payload", str(out / "spotter-payload.json"), str(ROOT))
        return
    if not os.environ.get("SPOTTER_ENDPOINT"):
        session.error("SPOTTER_ENDPOINT non defini : sans lui la CLI vise le SaaS https://spotter.steampunk.si/api.")
    if not (os.environ.get("SPOTTER_TOKEN") or os.environ.get("SPOTTER_API_TOKEN")):
        session.error("SPOTTER_TOKEN absent (credential CI).")
    # SPOTTER_ENDPOINT, SPOTTER_TOKEN et SPOTTER_CACERT sont lus directement par la CLI.
    session.run(
        "spotter", *scan,
        "--display-level", os.environ.get("SPOTTER_DISPLAY_LEVEL", "error"),
        "--junit-xml", str(out / "spotter.xml"), "--sarif", str(out / "spotter.sarif"),
        *session.posargs, str(ROOT),
    )


@nox.session(name="molecule", python=DEFAULT_PYTHON)
def molecule(session: nox.Session) -> None:
    """Scenarios Molecule ansible-native (extensions/molecule) - agent avec podman uniquement."""
    if not (ROOT / "extensions" / "molecule").is_dir():
        session.skip("Pas de extensions/molecule")
    if not shutil.which(os.environ.get("CONTAINER_ENGINE", "podman")):
        session.error("molecule exige podman (agent VM 'ansible-builder') : aucun moteur de conteneurs ici.")
    session.install(*_core_spec(DEFAULT_CORE), "-r", str(CI_DIR / "requirements-molecule.txt"), *_pip_constraints())
    # Cibles = images de distribution ansible-test (alias de docker.txt de la serie DEFAULT_CORE),
    # tirees du Nexus puis re-taggees : extensions/molecule/inventory.yml les reference par leur nom quay.io.
    _prime_images(session, *os.environ.get("MOLECULE_IMAGES", "ubuntu2404 fedora43").split())
    base, dest = _prepare_tree(session, "molecule")
    with session.chdir(dest):
        session.run(
            "molecule", "test", *(session.posargs or ["--all"]),
            env={"ANSIBLE_COLLECTIONS_PATH": str(base)},
        )


# --------------------------------------------------------------------------------------
# Sessions parametrees par serie ansible-core : images-X.Y, sanity-X.Y, units-X.Y, integration-X.Y
# --------------------------------------------------------------------------------------
def _register(core: str) -> None:
    # _core_spec() est evalue dans la session (pas a l'import) pour que `nox -l` fonctionne toujours.

    @nox.session(name=f"images-{core}", python=_controller_python(core))
    def images(session: nox.Session) -> None:
        """Pre-tire (depuis Nexus) et re-tague les images utilisees par ansible-test."""
        session.install(*_core_spec(core), *_pip_constraints())
        _prime_images(session, *(session.posargs or ["default"]))

    @nox.session(name=f"sanity-{core}", python=_controller_python(core))
    def sanity(session: nox.Session) -> None:
        """ansible-test sanity --docker default (toutes versions Python de l'image)."""
        session.install(*_core_spec(core), *_pip_constraints())
        if TEST_MODE == "venv":
            # Pod sans moteur de conteneurs : seule la version Python de l'agent est testee
            # (compile/import pour les autres versions sont ignores) -> fidelite reduite.
            _seed_get_pip(session)
            target = ["--venv", "--python", str(session.python), "--requirements", *_venv_sanity_skips(session)]
        else:
            _prime_images(session, "default", "utility")
            target = ["--docker", "default"]
        _base, dest = _prepare_tree(session, "sanity")
        _run_ansible_test(session, dest, ["sanity", *target, "--junit", *_ansible_test_common()])

    @nox.session(name=f"units-{core}", python=_controller_python(core))
    def units(session: nox.Session) -> None:
        """ansible-test units --docker default --requirements."""
        if not (ROOT / "tests" / "unit").is_dir():
            session.skip("Pas de tests/unit")
        session.install(*_core_spec(core), *_pip_constraints())
        if TEST_MODE == "venv":
            _seed_get_pip(session)
            target = ["--venv", "--python", str(session.python)]
        else:
            _prime_images(session, "default", "utility")
            target = ["--docker", "default"]
        _base, dest = _prepare_tree(session, "units")
        _run_ansible_test(session, dest, ["units", *target, "--requirements", *_ansible_test_common()])

    @nox.session(name=f"integration-{core}", python=_controller_python(core))
    def integration(session: nox.Session) -> None:
        """ansible-test integration --docker <ANSIBLE_TEST_DOCKER|default>. Posargs = cibles."""
        if not (ROOT / "tests" / "integration" / "targets").is_dir():
            session.skip("Pas de tests/integration/targets")
        if TEST_MODE == "venv":
            session.error("integration exige un moteur de conteneurs : l'executer sur l'agent 'ansible-builder'.")
        image = os.environ.get("ANSIBLE_TEST_DOCKER", "default")
        session.install(*_core_spec(core), *_pip_constraints())
        _prime_images(session, image, "utility")
        _base, dest = _prepare_tree(session, "integration")
        args = ["integration", "--docker", image, "--retry-on-error", "--continue-on-error", *_ansible_test_common()]
        network = os.environ.get("ANSIBLE_TEST_DOCKER_NETWORK")
        if network:
            args += ["--docker-network", network]
        _run_ansible_test(session, dest, args)


for _core in CORE_VERSIONS:
    _register(_core)
