// ansible-test integration --docker <image> : agent avec podman/docker (VM ansible-builder).
// Aide : ansibleTestIntegration.txt
def call(Map opts = [:]) {
    Map o = new LinkedHashMap(opts)
    String image = o.remove('image') ?: 'default'
    String core = o.core ?: env.ACI_CORE ?: '@CORE@'
    aciRun(step: 'ansibleTestIntegration', command: 'integration', opts: o + [testMode: 'docker'],
           env: ["ACI_INTEGRATION_IMAGE=${image}"],
           junit: "reports/integration-${core}-${image}/junit/*.xml")
}
