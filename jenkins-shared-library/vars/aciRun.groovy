import org.corp.ansibleci.Config

// INTERNE. Execute `aci <command>` avec l'environnement ACI_* issu de la configuration, puis publie
// les rapports JUnit. Utilise par toutes les etapes granulaires.
//   step    : nom de l'etape appelante (messages d'erreur)
//   command : sous-commande aci (lint, sanity, ...)
//   opts    : Map de l'utilisateur (cles du pipeline + options propres a l'etape)
//   keys    : options propres a l'etape admises en plus des cles communes
//   env     : variables supplementaires (List 'K=V')
//   junit   : motif des rapports JUnit (relatif au workspace) ; peut contenir @CORE@
//   junitInformational : true -> les constats publies ne rendent pas le build UNSTABLE (le seuil du
//             scanner decide : securityFailOn, spotterBlocking)
def call(Map spec) {
    Map opts = spec.opts ?: [:]
    List common = ['core', 'testMode', 'args', 'python', 'corePin']
    boolean inPipeline = env.ACI_CONFIGURED == 'true'
    Map res = Config.resolve(opts, libraryResource('org/corp/ansibleci/aci/share/aci/python-map.txt'),
                             inPipeline, common + (spec.keys ?: []))
    if (res.errors) {
        error(Config.errorMessage(spec.step, res.errors))
    }
    Map cfg = res.cfg
    String core = cfg.core ?: env.ACI_CORE ?: env.ACI_CORE_DEFAULT ?: cfg.defaultCore
    if (core && !cfg.supportedCores.contains(core)) {
        error(Config.errorMessage(spec.step, ["core '${core}' inconnu : series prises en charge ${cfg.supportedCores.join(', ')}"]))
    }
    String mode = cfg.testMode ?: env.ACI_TEST_MODE ?: 'venv'
    if (mode == 'auto') mode = aciBranches.testMode([testMode: 'auto', fullTestBranches: Config.DEFAULTS.fullTestBranches])

    String aci = aciInstall(cfg)
    String tmp = pwd(tmp: true)
    List e = Config.toEnv(cfg)
    if (core) e << "ACI_CORE=${core}"
    if (cfg.python) e << "ACI_PYTHON=${cfg.python}"     // venv : Python controleur ; docker : Python cible
    if (cfg.corePin) e << "ACI_CORE_PIN=${cfg.corePin}" // version exacte (EE cible)
    e << "ACI_TEST_MODE=${mode}"
    e << "ACI_SRC=${pwd()}"
    e << "ACI_WORK=${tmp}/aci-work"
    if (!inPipeline && opts.pythonMap) {
        writeFile file: "${tmp}/aci-python-map.txt", text: Config.renderPythonMap(cfg.pythonMapResolved)
        e << "ACI_PYTHON_MAP=${tmp}/aci-python-map.txt"
    }
    e += (spec.env ?: [])

    if (spec.returnStdout) {
        String out = ''
        withEnv(e) { out = sh(label: "aci ${spec.command}", script: "${aci} ${spec.command}${argsOf(cfg.args)}", returnStdout: true).trim() }
        return out
    }
    String args = argsOf(cfg.args)
    try {
        withEnv(e) {
            sh label: "aci ${spec.command}${core ? ' (ansible-core ' + (cfg.corePin ?: core) + ')' : ''}", script: "${aci} ${spec.command}${args}"
        }
    } finally {
        if (spec.junit) {
            junit allowEmptyResults: true, skipMarkingBuildUnstable: spec.junitInformational ?: false,
                  testResults: spec.junit.replace('@CORE@', core ?: 'default')
        }
    }
}

String argsOf(Object a) {
    String args = ''
    if (a instanceof List) {
        args = a.collect { ' \'' + it.toString().replace('\'', '\'"\'"\'') + '\'' }.join('')
    } else if (a) {
        args = ' ' + a   // chaine : mots shell tels quels (Jenkinsfile de confiance de l'equipe)
    }
    return args
}
