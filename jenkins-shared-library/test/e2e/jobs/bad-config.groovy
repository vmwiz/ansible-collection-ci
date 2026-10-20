// Doit echouer AVANT tout agent, avec la liste des erreurs.
@Library('ansible-ci@v1') _
ansibleCollectionPipeline(ansibleCoreVersions: [2.20, '2.18'], lnt: false, testMode: 'vm', spotter: true)
