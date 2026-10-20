// yamllint + antsibull-changelog lint + ansible-lint --offline (dependances Galaxy via Nexus).
// Aide : ansibleLint.txt (Jenkins > Pipeline Syntax > Global Variables Reference)
def call(Map opts = [:]) {
    aciRun(step: 'ansibleLint', command: 'lint', opts: opts)
}
