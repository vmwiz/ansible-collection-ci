// ansible-test units --requirements, mode venv ou docker.
// Aide : ansibleTestUnits.txt (Jenkins > Pipeline Syntax > Global Variables Reference)
def call(Map opts = [:]) {
    aciRun(step: 'ansibleTestUnits', command: 'units', opts: opts, junit: 'reports/units-@CORE@/junit/*.xml')
}
