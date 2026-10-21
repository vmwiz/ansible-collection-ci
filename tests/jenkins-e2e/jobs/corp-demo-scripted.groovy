// Pipeline SCRIPTE avec les etapes granulaires (tag fige v1.0.0).
@Library('ansible-ci@v1.0.0') _

node('ansible-runner') {
    stage('checkout') { git url: 'file:///repos/corp.demo.git', branch: 'main' }
    withAnsibleCi(ansibleCoreVersions: ['2.16', '2.18'], pypiEndpoint: 'https://nexus.corp.local/root/pypi/+simple/') {
        stage('build') { ansibleCollectionBuild(); galaxyImporter() }
        stage('certification') {
            def cores = ansibleCertification(sanityCores: true)
            echo "series sanity de certification : ${cores}"
            ansibleCertification()
        }
        stage('changelog (hors PR : ignore)') { ansibleChangelogCheck() }
        stage('sanity 2.16') {
            withAnsibleCore('2.16') { ansibleTestSanity(testMode: 'venv', args: ['--test', 'pep8', '--test', 'yamllint']) }
        }
        stage('units') { ansibleTestUnits(core: '2.18') }
    }
    stage('securite (hors withAnsibleCi : defauts)') { ansibleSecurityScan(securityFailOn: 'none') }
    stage('spotter export') { spotterScan(exportOnly: true) }
}
