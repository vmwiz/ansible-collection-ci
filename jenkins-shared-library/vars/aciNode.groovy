import org.corp.ansibleci.Config

// INTERNE (utilise par ansibleCollectionPipeline). Ouvre un agent, recupere le depot et execute body
// avec l'environnement ACI_* de la configuration.
//   kind 'runner'  : pod OpenShift restricted-v2 (agentType 'kubernetes') ou noeud runnerLabel
//   kind 'builder' : VM builderLabel (podman : ansible-test --docker, molecule)
def call(Map cfg, String kind, Closure body) {
    Closure inner = {
        checkout scm
        dir('reports') { deleteDir() }
        List e = Config.toEnv(cfg) + ['ACI_CONFIGURED=true']
        if (cfg.pythonMap) {
            String f = "${pwd(tmp: true)}/aci-python-map.txt"
            writeFile file: f, text: Config.renderPythonMap(cfg.pythonMapResolved)
            e << "ACI_PYTHON_MAP=${f}"
        }
        try {
            withEnv(e) {
                if (cfg.color) { ansiColor('xterm') { body() } } else { body() }
            }
        } finally {
            if (fileExists('reports')) {
                archiveArtifacts allowEmptyArchive: true, artifacts: 'reports/**', excludes: '**/.tmp/**'
            }
        }
    }
    if (kind == 'builder') {
        node(cfg.builderLabel) { inner() }
    } else if (cfg.agentType == 'label') {
        node(cfg.runnerLabel) { inner() }
    } else {
        String yaml = cfg.podTemplateYaml ?: libraryResource('org/corp/ansibleci/pod/runner-pod.yaml')
                .replace('@RUNNER_IMAGE@', cfg.runnerImage).replace('@JNLP_IMAGE@', cfg.jnlpImage)
        Map pt = [yaml: yaml]
        if (cfg.podCloud) pt.cloud = cfg.podCloud
        podTemplate(pt) {
            node(POD_LABEL) {
                container('runner') { inner() }
            }
        }
    }
}
