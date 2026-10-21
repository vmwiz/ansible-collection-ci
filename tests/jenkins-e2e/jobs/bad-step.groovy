@Library('ansible-ci@v1') _
node('ansible-runner') { ansibleTestSanity(cor: '2.20') }
