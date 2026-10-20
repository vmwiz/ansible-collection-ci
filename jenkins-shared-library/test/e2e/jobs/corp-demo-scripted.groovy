// Pipeline SCRIPTE avec les etapes granulaires (tag fige v1.0.0).
@Library('ansible-ci@v1.0.0') _

node('ansible-runner') {
    stage('checkout') { git url: 'file:///repos/corp.demo.git', branch: 'main' }
    withAnsibleCi(ansibleCoreVersions: ['2.20', '2.21'], pypiEndpoint: 'https://nexus.corp.local/root/pypi/+simple/') {
        stage('build') { ansibleCollectionBuild(); galaxyImporter() }
        stage('sanity 2.20') {
            withAnsibleCore('2.20') { ansibleTestSanity(testMode: 'venv', args: ['--test', 'pep8', '--test', 'yamllint']) }
        }
        stage('units') { ansibleTestUnits(core: '2.21') }
    }
    stage('securite (hors withAnsibleCi : defauts)') { ansibleSecurityScan(securityFailOn: 'none') }
    stage('spotter export') { spotterScan(exportOnly: true) }
}
