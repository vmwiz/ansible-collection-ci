// ansible-galaxy collection publish de dist/*.tar.gz vers galaxyPublishUrl (Nexus ansible-hosted).
// Jeton : credential "Secret text" galaxyCredentialsId. A appeler sur un tag uniquement.
// Aide : ansibleCollectionPublish.txt
def call(Map opts = [:]) {
    Map o = new LinkedHashMap(opts)
    String credId = o.remove('credentialsId') ?: o.galaxyCredentialsId ?: env.ACI_GALAXY_CREDENTIALS_ID ?: 'nexus-galaxy-hosted-token'
    o.remove('galaxyCredentialsId')
    withCredentials([string(credentialsId: credId, variable: 'ACI_GALAXY_TOKEN')]) {
        aciRun(step: 'ansibleCollectionPublish', command: 'publish', opts: o)
    }
}
