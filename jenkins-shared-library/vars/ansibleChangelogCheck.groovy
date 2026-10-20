// Fragment changelogs/fragments/*.yml obligatoire sur une PR (multibranche : CHANGE_ID/CHANGE_TARGET),
// puis antsibull-changelog lint. Exemption : changelogSkipToken (defaut 'skip-changelog') dans le titre de la PR.
// Aide : ansibleChangelogCheck.txt
def call(Map opts = [:]) {
    Map o = new LinkedHashMap(opts)
    String token = o.remove('skipToken') ?: o.remove('changelogSkipToken') ?: env.ACI_CHANGELOG_SKIP ?: 'skip-changelog'
    aciRun(step: 'ansibleChangelogCheck', command: 'changelog-check', opts: o, env: ["ACI_CHANGELOG_SKIP=${token}"])
}
