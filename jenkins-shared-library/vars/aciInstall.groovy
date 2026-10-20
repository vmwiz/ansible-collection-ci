// INTERNE. Depose les scripts bash `aci` de la bibliotheque (resources/org/corp/ansibleci/aci) dans
// <workspace>@tmp/aci-<version>/ et renvoie la commande a executer. Fait une seule fois par workspace
// et par version : le tag de la bibliotheque (@Library('ansible-ci@v1.2.0')) fige donc aussi les scripts.
// scriptsFrom: 'agent' -> utilise l'installation de l'image runner / de la VM (/opt/ansible-ci/bin/aci).
def call(Map cfg = [:]) {
    String from = cfg.scriptsFrom ?: env.ACI_SCRIPTS_FROM ?: 'library'
    if (from == 'agent') {
        return "\"${cfg.agentScriptsPath ?: env.ACI_AGENT_SCRIPTS ?: '/opt/ansible-ci/bin/aci'}\""
    }
    String base = 'org/corp/ansibleci/aci'
    String version = libraryResource("${base}/VERSION").trim()
    String dir = "${pwd(tmp: true)}/aci-${version}"
    if (!fileExists("${dir}/.complete")) {
        List files = libraryResource("${base}/MANIFEST").readLines().findAll { it.trim() }
        for (int i = 0; i < files.size(); i++) {
            writeFile file: "${dir}/${files[i]}", text: libraryResource("${base}/${files[i]}"), encoding: 'UTF-8'
        }
        writeFile file: "${dir}/.complete", text: version
    }
    // appel via bash : pas besoin du bit x (writeFile ne le pose pas, @tmp peut etre noexec)
    return "bash \"${dir}/bin/aci\""
}
