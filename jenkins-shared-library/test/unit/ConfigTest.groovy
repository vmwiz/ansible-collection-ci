// Tests unitaires de org.corp.ansibleci.Config (Groovy 2.4, comme Jenkins) : test/unit/run.sh
import org.corp.ansibleci.Config

String map = new File(args[0]).text
int n = 0
def check = { String name, Closure c -> c(); n++; println "ok   ${name}" }
def resolve = { Map m -> Config.resolve(m, map) }

check('defauts sans erreur') {
    def r = resolve([:])
    assert r.errors == []
    assert r.cfg.ansibleCoreVersions == ['2.16', '2.18']   // AAP 2.6
    assert r.cfg.defaultCore == '2.18'
    assert r.cfg.integrationCoreVersions == ['2.18']
    assert r.cfg.certification && r.cfg.changelogCheck && !r.cfg.eeTests
    assert r.cfg.supportedCores.containsAll(['2.16', '2.18', '2.20', '2.22', 'devel', 'milestone'])
}
check('cle inconnue avec suggestion') {
    def r = resolve([lnt: false, molecul: true])
    assert r.errors.any { it.contains("parametre inconnu 'lnt'") && it.contains("'lint'") }
    assert r.errors.any { it.contains("'molecule'") }
}
check('types') {
    def r = resolve([lint: 'yes', ansibleCoreVersions: [2.20], timeoutMinutes: '10', extraEnv: 'X'])
    assert r.errors.size() == 4
    assert r.errors.any { it.contains('2.20 sans guillemets') }
}
check('serie inconnue / doublon / defaut absent') {
    def r = resolve([ansibleCoreVersions: ['2.17', '2.20', '2.20'], ansibleCoreDefault: '2.21'])
    assert r.errors.any { it.contains("ansible-core '2.17' inconnu") }
    assert r.errors.any { it.contains('doublons') }
    assert r.errors.any { it.contains("ansibleCoreDefault '2.21'") }
}
check('choix et URL') {
    def r = resolve([testMode: 'vm', securityFailOn: 'low', pipIndexUrl: 'nexus/simple'])
    assert r.errors.size() == 3
    assert r.errors.any { it.contains('venv | docker | auto') }
}
check('regles croisees') {
    def r = resolve([spotter: true, build: false])
    assert r.errors.any { it.contains('spotterEndpoint') }
    assert r.errors.any { it.contains('galaxyImporter: true exige build') }
    assert r.errors.any { it.contains('publish: true exige build') }
    assert resolve([spotter: true, spotterEndpoint: 'https://spotter.corp.local/api']).errors == []
}
check('liste personnalisee -> serie par defaut') {
    def r = resolve([ansibleCoreVersions: ['2.19', '2.20']])
    assert r.cfg.defaultCore == '2.20'
    assert Config.toEnv(r.cfg).contains('ACI_CORE_DEFAULT=2.20')
}
check('pythonMap surcharge') {
    def r = resolve([ansibleCoreVersions: ['2.23'], pythonMap: ['2.23': ['3.15']], ansibleCorePrerelease: ['2.23']])
    assert r.errors == [] : r.errors
    assert Config.renderPythonMap(r.cfg.pythonMapResolved).contains('2.23 3.15\n')
    assert r.cfg.defaultCore == '2.23'
}
check('toEnv') {
    def env = Config.toEnv(resolve([securityReportSeverity: 'high', extraEnv: [FOO: 'bar'], moleculeImages: ['a', 'b']]).cfg)
    assert env.contains('ACI_SECURITY_SEVERITY=HIGH')
    assert env.contains('FOO=bar')
    assert env.contains('ACI_MOLECULE_IMAGES=a b')
    assert env.contains('ACI_PRERELEASE=')
    assert env.contains('ACI_CORE_VERSIONS=2.16 2.18')
    assert env.contains('ACI_GALAXY_URL=https://nexus.corp.local/repository/ansible-group/')
    assert !env.any { it.startsWith('ACI_PIP_INDEX_URL=') }      // null -> /etc/pip.conf
    assert env.every { it instanceof String }
}
check('mode partiel (etapes granulaires)') {
    def r = Config.resolve([core: '2.20', testMode: 'docker', sanityArgs: '--test pep8'], map, true, ['core', 'testMode', 'args'])
    assert r.errors == []
    assert Config.toEnv(r.cfg) == ['ACI_SANITY_ARGS=--test pep8']
    assert Config.resolve([cor: '2.20'], map, true, ['core']).errors[0].contains("'core'")
}
check('message erreur') {
    String m = Config.errorMessage('ansibleCollectionPipeline', ['a', 'b'])
    assert m.startsWith('ansibleCollectionPipeline : configuration invalide\n  - a\n  - b')
}
check('ansibleCoreOptional (AAP 2.7) : non bloquant') {
    def r = resolve([ansibleCoreOptional: ['2.20']])
    assert r.errors == []
    def m = Config.matrix(r.cfg)
    assert m.collect { it.core } == ['2.16', '2.18', '2.20'] && m.last().optional && !m[0].optional
    assert Config.label(m.last()) == 'ansible-core 2.20 [non bloquant]'
    assert r.cfg.defaultCore == '2.18'
    assert Config.toEnv(r.cfg).contains('ACI_CORE_VERSIONS=2.16 2.18 2.20')
    assert resolve([ansibleCoreOptional: ['2.18']]).errors.any { it.contains('figure deja') }
}
check('targetEEs : exclusif, matrice derivee') {
    assert resolve([targetEEs: ['hub/ee:2.16'], ansibleCoreVersions: ['2.16']]).errors.any { it.contains('exclusifs') }
    assert resolve([eeTests: true]).errors.any { it.contains('eeTests: true exige targetEEs') }
    def r = resolve([targetEEs: ['hub.corp/ee-minimal-rhel9:2.16', 'hub.corp/ee-minimal-rhel9:2.18']])
    assert r.errors == []
    def rows = Config.parseEeMatrix('2.16 3.12 2.16.19 hub.corp/ee-minimal-rhel9:2.16\n2.18 3.12 2.18.19 hub.corp/ee-minimal-rhel9:2.18\n')
    Config.applyEeMatrix(r.cfg, rows)
    assert r.cfg.ansibleCoreVersions == ['2.16', '2.18'] && r.cfg.defaultCore == '2.18' && r.cfg.integrationCoreVersions == ['2.18']
    def m = Config.matrix(r.cfg)
    assert m.size() == 2 && m[0].pin == '2.16.19' && m[0].python == '3.12'
    assert Config.label(m[0]) == 'ansible-core 2.16.19 py3.12 (ee-minimal-rhel9:2.16)'
}
check('exemple complet du GUIDE-UTILISATEUR') {
    def r = resolve([ansibleCoreVersions: ['2.16', '2.18'], ansibleCoreOptional: ['2.20'], integration: true,
        integrationImages: ['default', 'ubuntu2404'], molecule: true, moleculeImages: ['ubuntu2404', 'fedora40'],
        spotter: true, spotterEndpoint: 'https://spotter.corp.local/api', spotterBlocking: false, testMode: 'auto',
        fullTestBranches: ['main', 'stable-1'], sanityArgs: '', coverage: false, securityFailOn: 'high',
        changelogSkipToken: 'skip-changelog', timeoutMinutes: 120, extraEnv: [MY_TEST_ENDPOINT: 'https://api.corp.local']])
    assert r.errors == [] : r.errors
    def e = resolve([targetEEs: ['hub.corp.local/ansible-automation-platform-26/ee-minimal-rhel9:latest']])
    assert e.errors == [] : e.errors
}
println "${n} tests OK"
