// galaxy-importer sur l'artefact de ansibleCollectionBuild (memes controles que Galaxy / Automation Hub).
// Aide : galaxyImporter.txt (Jenkins > Pipeline Syntax > Global Variables Reference)
def call(Map opts = [:]) {
    aciRun(step: 'galaxyImporter', command: 'importer', opts: opts)
}
