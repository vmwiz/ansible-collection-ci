// ansible-test sanity, mode venv (agent sans moteur de conteneurs) ou docker (VM ansible-builder).
// Aide : ansibleTestSanity.txt (Jenkins > Pipeline Syntax > Global Variables Reference)
def call(Map opts = [:]) {
    aciRun(step: 'ansibleTestSanity', command: 'sanity', opts: opts, junit: 'reports/sanity-@CORE@/junit/*.xml')
}
