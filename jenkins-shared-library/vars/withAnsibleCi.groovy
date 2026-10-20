// withAnsibleCi(galaxyServerUrl: '...', ansibleCoreVersions: ['2.20','2.21']) { ... etapes granulaires ... }
// Pour les pipelines scriptes : valide UNE fois la configuration (memes cles qu'ansibleCollectionPipeline,
// memes defauts) et la fournit a toutes les etapes du bloc. A appeler DANS un node.
// Aide : withAnsibleCi.txt
import org.corp.ansibleci.Config

def call(Map config = [:], Closure body) {
    Map res = Config.resolve(config, libraryResource('org/corp/ansibleci/aci/share/aci/python-map.txt'))
    if (res.errors) error(Config.errorMessage('withAnsibleCi', res.errors))
    Map cfg = res.cfg
    List e = Config.toEnv(cfg) + ['ACI_CONFIGURED=true']
    if (cfg.pythonMap) {
        String f = "${pwd(tmp: true)}/aci-python-map.txt"
        writeFile file: f, text: Config.renderPythonMap(cfg.pythonMapResolved)
        e << "ACI_PYTHON_MAP=${f}"
    }
    withEnv(e) { body() }
}
