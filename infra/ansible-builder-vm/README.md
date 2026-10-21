# VM "ansible-builder" (podman rootless)

Agent Jenkins (label `ansible-builder`) / runner GitLab shell (tag `ansible-builder`) pour les etapes
qui ont besoin de conteneurs : `ansible-test --docker` (via podman), `integration`, `molecule`.

```bash
mkdir -p files && cp /chemin/ac-interne.crt files/corp-ca.crt
ansible-playbook -i "builder01.corp.local," -e builder_ci_user=jenkins site.yml   # ou gitlab-runner
```

Points verifies lors de la validation (podman 5.4, rootless, cgroup v2) :

* ansible-test detecte podman tout seul ; `ANSIBLE_TEST_PREFER_PODMAN=1` le force si un binaire
  `docker` est aussi present (il ignore deja un `docker` qui n'est qu'un alias de podman).
* Les conteneurs de test demarrent **systemd** (`--systemd always --cgroupns private`) : l'utilisateur
  doit disposer d'un sous-arbre cgroup v2 **delegue** (session systemd utilisateur, d'ou
  `loginctl enable-linger`). Sans delegation : `Failed to create /init.scope control group: Permission denied`
  puis `can only create exec sessions on running containers`.
  Controle : `cat /sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/cgroup.controllers`.
* Jobs lances sans session logind (runner GitLab via `su`) : definir `XDG_RUNTIME_DIR=/run/user/<uid>`.
* Python : `builder_python` (python3.12, porte aussi le venv d'outillage `/opt/ansible-ci`). 3.12 couvre
  2.16 (3.10-3.12), 2.18 (3.11-3.13), 2.20 (3.12-3.14) et la certification. `builder_extra_pythons` (vide par
  defaut) : ajouter `python3.14` seulement pour 2.22 / `milestone` / `devel` (AppStream RHEL 9.8 : pas de 3.13).
* `templates/registries-nexus.conf` : miroirs podman (quay.io, docker.io, ghcr.io) vers Nexus,
  depose dans `/etc/containers/registries.conf.d/`.
* Scripts `aci` : copies de `ci-scripts/` (meme version que l'image runner) dans `/opt/ansible-ci`
  (`/opt/ansible-ci/bin/aci`, chemin utilise par le composant GitLab et par Jenkins `scriptsFrom: 'agent'`).
  Lancer le playbook depuis un checkout du tag `v1.x.y` du depot. Par defaut Jenkins n'en a pas besoin
  (scripts fournis par la bibliotheque), GitLab si.
* Introspection des EE (`targetEEs` / `target-ees`) : la VM doit pouvoir tirer les images EE depuis le
  miroir Nexus de `registry.redhat.io` ou le Private Automation Hub (`podman login` du compte CI).
* `shellcheck` (sanity) n'est pas requis sur la VM : sanity tourne dans `default-test-container`.
