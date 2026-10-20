// ansible-galaxy collection build -> dist/<ns>-<nom>-<version>.tar.gz.
// Aide : ansibleCollectionBuild.txt (Jenkins > Pipeline Syntax > Global Variables Reference)
def call(Map opts = [:]) {
    aciRun(step: 'ansibleCollectionBuild', command: 'build', opts: opts)
}
