# Jenkins: admin setup for the `ansible-ci` shared library

Everything is done once, in the Jenkins UI (**Manage Jenkins**); no extra plugin or file is needed. Site
values (Nexus URLs, Spotter, ci-tools-image, agent label, credential IDs) are **pipeline parameters with
defaults**, defined at the top of `jenkins-shared-library/vars/ansibleCollectionPipeline.groovy`: set the
defaults there once for your site, teams override them only when needed.

## 1. Plugins

Pipeline (`workflow-aggregator`), Pipeline: Declarative (`pipeline-model-definition`), Pipeline: Groovy
Libraries (`pipeline-groovy-lib`), Git, Kubernetes, Credentials Binding, Plain Credentials, JUnit,
Timestamper, AnsiColor.

## 2. Global Pipeline Library

*Manage Jenkins > System > Global Trusted Pipeline Libraries > Add*:

| Field | Value |
|---|---|
| Name | `ansible-ci` |
| Default version | `v2` (moving tag = latest 2.x) |
| Allow default version to be overridden | checked (lets a team pin `@Library('ansible-ci@v2.1.0')`) |
| Include @Library changes in job recent changes | as you like |
| Retrieval method | Modern SCM > Git, repository of the library (e.g. `https://gitlab.corp.local/ci/ansible-ci-jenkins.git`) with a read-only credential |
| Behaviours | *Discover branches* **and** *Discover tags* (tags are used as versions) |

A *global* library is trusted code (it runs outside the Groovy sandbox): only CI maintainers may write to
its repository.

## 3. Credentials

*Manage Jenkins > Credentials > System > Global credentials > Add Credentials*, kind **Secret text**:

| ID (default parameter value) | Secret | Parameter |
|---|---|---|
| `spotter-api-token` | API token of the private Spotter instance | `spotterCredentialsId` |
| `nexus-galaxy-hosted-token` | Nexus token allowed to publish to the Galaxy hosted repository | `galaxyCredentialsId` |

The pipeline only receives credential **IDs**; the secret values never appear in a Jenkinsfile. A team
with its own token creates another Secret text credential (folder-level credentials work too) and passes
its ID, e.g. `spotterCredentialsId: 'my-team-spotter'`.

## 4. Kubernetes cloud (OpenShift)

*Manage Jenkins > Clouds > New cloud > Kubernetes*: the OpenShift API URL, the agents namespace, a
service account credential, the Jenkins URL and tunnel reachable from the pods. **No pod template is
needed**: the library ships its own (`resources/ansible-ci/pod.yaml`, SCC `restricted-v2`) and puts the
`ciToolsImage` parameter into it. The `jnlp` container keeps the image configured in the cloud (point it to
your Nexus mirror of `jenkins/inbound-agent`). If several Kubernetes clouds exist, the pipeline uses the
default one (the first).

## 5. ansible-builder agents (Podman VM)

Prepare the VMs with `../ansible-builder-vm/site.yml`, then *Manage Jenkins > Nodes > New node*
(permanent agent, SSH or inbound), label **`ansible-builder`** (parameter `builderLabel`), one executor
per parallel container stage (each `ansible-test --docker` run starts 2-3 containers). If a real `docker`
binary is installed next to podman, set `ANSIBLE_TEST_PREFER_PODMAN=1` in the node environment.

## 6. Jobs

One **Multibranch Pipeline** per collection (branch + pull request + tag discovery): the changelog check runs
on pull requests (`changeRequest()`), `Publish` on tag builds (`buildingTag()`).

## 7. Validation

`../../tests/jenkins-e2e/run-e2e.sh` (bench, not shipped) starts Jenkins 2.580.1, applies this setup with
init scripts (`tests/jenkins-e2e/init.groovy.d/`), loads the library from a local git repository and runs
the example collection with default and overridden parameters. The bench has no Kubernetes cluster: the
OpenShift pod is replaced by a static agent, and the rendered pod YAML is checked separately.
