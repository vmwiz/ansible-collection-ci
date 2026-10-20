# OpenShift : agents CI pour collections Ansible

| Fichier | Usage |
|---|---|
| `jenkins-agent-pod.yaml` | Modele de pod Jenkins (copie de `collection-files/ci/jenkins-agent-pod.yaml`), SCC `restricted-v2` |
| `nested-podman-pod.poc.yaml` | **POC** podman imbrique (OCP >= 4.20, SCC `nested-container`) - non valide |

## Ce qui tourne dans un pod restreint (sans moteur de conteneurs)
lint, docs, build, galaxy-importer, security-scan, spotter, `ansible-test sanity/units --venv`
(`ANSIBLE_TEST_MODE=venv`). Valide en simulant OpenShift : UID arbitraire (54321 puis 1000680000, GID 0, absent de
`/etc/passwd`), `--cap-drop ALL`, `no-new-privileges`, aucun socket.

Prerequis airgap specifiques au mode venv :
* ansible-test cree ses venvs sans pip puis execute `~/.ansible/test/cache/get_pip_<version>.py`
  (sinon telecharge depuis `https://ci-files.testing.ansible.com/ansible-test/`) : le noxfile y depose
  `ci/get_pip_offline.py` (`ensurepip` + pip a la version demandee depuis Nexus). Aucun depot raw necessaire ;
* ansible-test --venv ne transmet pas `PIP_INDEX_URL` a ses venvs : c'est `/etc/pip.conf` de l'image de base
  (UBI 9 d'entreprise, voir `infra/runner-image/README.md`) qui pointe vers Nexus.
* Valide en v3 avec l'image UBI 9 : UID 1000680000:0, `--cap-drop ALL`, reseau coupe sauf le faux Nexus.

## Ce qui ne peut PAS tourner dans un pod restreint
`ansible-test --docker` (y compris integration) et Molecule : il faut un moteur de conteneurs.
Options evaluees :

| Option | Realisme | Commentaire |
|---|---|---|
| VM `ansible-builder` + podman rootless (retenue) | **Eleve** | Valide de bout en bout (sanity/units/integration/molecule) |
| Socket Docker de l'hote / DinD privileged | Refuse | Interdit par la politique (SCC `privileged`) |
| Podman imbrique via user namespaces (`hostUsers: false` + SCC `nested-container`) | Moyen, POC | GA en OCP 4.20 (Technology Preview en 4.19). ansible-test lance `--privileged --pid host` et systemd : a valider |
| buildah dans le pod | Hors sujet | Construit des images, n'execute pas de conteneurs de test |
| OpenShift sandboxed containers (Kata) | Faible/couteux | Pods dans des micro-VM : privileges confines a la VM, mais virtualisation imbriquee ou noeuds bare-metal requis |
| `ansible-test integration` en `--venv`/`--local` dans le pod | Limite | Seulement pour des cibles qui ne modifient pas le systeme (modules API/reseau) |
