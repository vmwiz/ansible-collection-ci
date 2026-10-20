// withAnsibleCore('2.20') { ansibleTestSanity(); ansibleTestUnits() }
// Fixe la serie ansible-core (et donc le Python controleur, d'apres la table python-map) pour le bloc.
// Aide : withAnsibleCore.txt
import org.corp.ansibleci.Config

def call(String version, Closure body) {
    Map known = Config.parsePythonMap(libraryResource('org/corp/ansibleci/aci/share/aci/python-map.txt'))
    if (!known.containsKey(version) && !env.ACI_PYTHON_MAP) {
        error("withAnsibleCore : serie '${version}' inconnue ; series prises en charge : ${known.keySet().join(', ')}")
    }
    withEnv(["ACI_CORE=${version}"]) { body() }
}
