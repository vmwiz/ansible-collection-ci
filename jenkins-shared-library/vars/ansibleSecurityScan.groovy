// ansible-security-scanner (local) ; echec selon securityFailOn (high | critical | none).
// Aide : ansibleSecurityScan.txt (Jenkins > Pipeline Syntax > Global Variables Reference)
def call(Map opts = [:]) {
    aciRun(step: 'ansibleSecurityScan', command: 'security-scan', opts: opts, junit: 'reports/security/*.xml', junitInformational: true)
}
