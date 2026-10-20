// antsibull-docs lint-collection-docs (documentation des plugins et roles).
// Aide : ansibleCollectionDocs.txt (Jenkins > Pipeline Syntax > Global Variables Reference)
def call(Map opts = [:]) {
    aciRun(step: 'ansibleCollectionDocs', command: 'docs', opts: opts)
}
