// Steampunk Spotter vers l'instance PRIVEE (spotterEndpoint), jeton lu dans un credential Jenkins
// de type "Secret text" (spotterCredentialsId). exportOnly: true -> payload JSON sans appel reseau.
// Aide : spotterScan.txt
def call(Map opts = [:]) {
    Map o = new LinkedHashMap(opts)
    boolean exportOnly = o.remove('exportOnly') ?: false
    String credId = o.remove('credentialsId') ?: o.spotterCredentialsId ?: env.ACI_SPOTTER_CREDENTIALS_ID ?: 'spotter-api-token'
    o.remove('spotterCredentialsId')
    if (exportOnly) {
        aciRun(step: 'spotterScan', command: 'spotter', opts: o, env: ['ACI_SPOTTER_EXPORT_ONLY=true'])
        return
    }
    if (!(o.spotterEndpoint ?: env.SPOTTER_ENDPOINT)) {
        error("spotterScan : spotterEndpoint requis (instance privee, ex. 'https://spotter.corp.local/api') ; sans lui la CLI vise le SaaS")
    }
    withCredentials([string(credentialsId: credId, variable: 'SPOTTER_TOKEN')]) {
        aciRun(step: 'spotterScan', command: 'spotter', opts: o, junit: 'reports/spotter/*.xml', junitInformational: true)
    }
}
