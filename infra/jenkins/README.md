# Agents Jenkins

Le `Jenkinsfile` utilise deux types d'agents :

## 1. Pods Kubernetes sur OpenShift (agent par defaut)

* Plugin **Kubernetes** configure avec un "cloud" pointant sur le cluster OpenShift
  (namespace dedie, p.ex. `ci-ansible`, ServiceAccount sans droits sur son propre namespace).
* Modele de pod : `ci/jenkins-agent-pod.yaml` (charge par `yamlFile`, copie dans `infra/openshift/`).
  Deux conteneurs : `jnlp` (agent Jenkins) et `runner` (image `ansible-collection-runner`).
  Compatible SCC `restricted-v2` : pas de `runAsUser`, non-root, `allowPrivilegeEscalation: false`,
  capabilities supprimees, aucun socket ni conteneur privilegie.
* Jenkins partage par beaucoup d'equipes : on peut aussi declarer ce modele de facon centrale
  (Manage Jenkins > Clouds > Pod templates, ou JCasC) et le referencer par `inheritFrom 'ansible-collection-runner'`
  au lieu de `yamlFile` : les equipes ne peuvent alors plus modifier images ni ressources.
* Images `jnlp` et `runner` tirees du Nexus ; si le controleur est en HTTPS avec l'AC interne,
  l'image `jnlp` doit l'avoir dans son truststore Java (cf. README du plugin Kubernetes).

## 2. VM "ansible-builder" (label `ansible-builder`)

* Agent SSH (ou inbound) sur une VM RHEL/Fedora/Debian avec **podman rootless**,
  preparee par `infra/ansible-builder-vm/site.yml`.
* Execute : `ansible-test --docker` (podman), `integration`, `molecule`, sanity multi-Python.
* Nombre d'executeurs = nombre de jobs paralleles (chaque job lance 2 a 3 conteneurs).

## Plugins et credentials

* Plugins : Pipeline, Kubernetes, JUnit, Credentials Binding, Workspace Cleanup, AnsiColor, Timestamper.
* Credentials : `nexus-galaxy-hosted-token` (secret text, publication),
  `spotter-api-token` (secret text, jeton de l'instance Spotter privee).

## Validation

Le `Jenkinsfile` a ete valide par `pipeline-model-converter/validate` sur Jenkins 2.580.1 avec les
plugins ci-dessus (dont kubernetes 4560.vc25b_83890c34). Avant commit :
`curl -X POST -F "jenkinsfile=<Jenkinsfile" https://jenkins.corp.local/pipeline-model-converter/validate`
(avec authentification et crumb) ou `ssh -p <port> jenkins declarative-linter < Jenkinsfile`.
