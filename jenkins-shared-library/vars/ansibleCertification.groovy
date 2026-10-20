// Controles de certification Red Hat (reference : partner-certification-checker, versions figees dans
// resources/.../aci/share/aci/certification.env) : garde-fous ignores sanity / .ansible-lint /
// requires_ansible, galaxy-importer (CHECK_REQUIRED_TAGS=True, RUN_ANSIBLE_LINT=False) et
// ansible-lint --profile=production, en Python 3.12 + ansible-core 2.16.19.
// sanityCores: true -> renvoie seulement la liste des series sanity de certification (filtrees par requires_ansible).
// Aide : ansibleCertification.txt
def call(Map opts = [:]) {
    Map o = new LinkedHashMap(opts)
    boolean coresOnly = o.remove('sanityCores') ?: false
    if (coresOnly) {
        o.args = ['sanity-cores']
        return aciRun(step: 'ansibleCertification', command: 'certification', opts: o, returnStdout: true).tokenize(' \n')
    }
    aciRun(step: 'ansibleCertification', command: 'certification', opts: o)
}
