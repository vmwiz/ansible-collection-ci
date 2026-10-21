# Jenkins : bibliotheque partagee `ansible-ci` et agents

## 1. Declarer la bibliotheque (une fois, par l'administrateur)

Manage Jenkins > System > Global Trusted Pipeline Libraries (ou JCasC) :

```yaml
unclassified:
  globalLibraries:
    libraries:
      - name: ansible-ci
        defaultVersion: v1            # branche "mobile" v1 = derniere 1.x ; tags v1.0.0... pour figer
        allowVersionOverride: true    # @Library('ansible-ci@v1.0.0') autorise
        implicit: false
        retriever:
          modernSCM:
            scm:
              git:
                remote: https://gitlab.corp.local/ci/ansible-ci-jenkins.git
                credentialsId: gitlab-read-ansible-ci
```

Bibliotheque **globale** = code de confiance (hors sandbox) : seuls les mainteneurs CI ecrivent dans le depot.
Les Jenkinsfile des equipes, eux, restent dans la sandbox.

## 2. Agents

| Agent | Parametre | Utilise pour |
|---|---|---|
| Pod Kubernetes/OpenShift (defaut) | `agentType: 'kubernetes'` | controles statiques, certification, sanity/units `venv` |
| Noeud statique `ansible-runner` | `agentType: 'label'`, `runnerLabel` | idem, sans plugin Kubernetes |
| VM `ansible-builder` (podman rootless) | `builderLabel` | introspection des EE, `docker`, integration, molecule, POC EE |

* Pod : modele `resources/org/corp/ansibleci/pod/runner-pod.yaml` de la bibliotheque (conteneurs `jnlp` +
  `runner`, compatible SCC `restricted-v2` : pas de `runAsUser`, non-root, `drop: ALL`, pas d'escalade).
  Images : `runnerImage`, `jnlpImage` ; modele complet remplacable par `podTemplateYaml` ; cloud : `podCloud`.
* VM : agent SSH ou inbound, preparee par `infra/ansible-builder-vm/site.yml`. Nombre d'executeurs = nombre
  de branches paralleles (chaque branche docker lance 2 a 3 conteneurs).

## 3. Plugins et credentials

* Plugins : Pipeline (workflow-aggregator), Pipeline: Groovy Libraries, Git, Kubernetes (si pods), JUnit,
  Credentials Binding, AnsiColor, Timestamper.
* Credentials (Secret text) : `nexus-galaxy-hosted-token` (publication, `galaxyCredentialsId`),
  `spotter-api-token` (Spotter prive, `spotterCredentialsId`).
* Le controle du fragment de changelog s'active sur les PR de jobs **multibranche** (`CHANGE_ID`).

## 4. Validation effectuee (banc, Jenkins 2.580.1)

Bibliotheque chargee depuis un depot git local (`v1` et `v1.0.0`), agent statique `ansible-runner`
(image runner + JDK 21) en airgap : voir `tests/jenkins-e2e/` (banc, hors livrable) et le compte rendu dans
`PROPOSITION.md`. Le mode Kubernetes (pod restricted-v2) est valide par schema (`test/validate-pod.sh`),
pas sur un cluster.
