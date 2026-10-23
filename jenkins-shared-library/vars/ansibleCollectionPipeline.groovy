/*
 * ansible-ci: the one CI pipeline for Ansible collections (airgapped, Nexus, AAP 2.6).
 * Fixed on purpose: every collection runs exactly the same stages. A collection Jenkinsfile is:
 *
 *   @Library('ansible-ci@v2') _
 *   ansibleCollectionPipeline()
 *
 * All the work is done by the `aci` CLI baked into the runner image and the ansible-builder VM
 * (/opt/ansible-ci/bin/aci). Site settings are set once by the Jenkins admins (infra/jenkins/jcasc.yaml):
 *   - global environment: ACI_GALAXY_URL, ACI_GALAXY_PUBLISH_URL, ACI_PYPI_ENDPOINT, ACI_IMAGE_MIRROR,
 *     SPOTTER_ENDPOINT (Spotter stage is skipped when unset), SPOTTER_CACERT;
 *   - pod template 'ansible-runner' (OpenShift, restricted-v2) and agents labelled 'ansible-builder' (Podman VM);
 *   - credentials 'spotter-api-token' and 'nexus-galaxy-hosted-token' (Secret text).
 * Optional stages (units, integration, Molecule) run only when the matching directory exists.
 */
def call() {
    pipeline {
        agent none
        options {
            buildDiscarder(logRotator(numToKeepStr: '20'))
            timeout(time: 90, unit: 'MINUTES')
            timestamps()
            ansiColor('xterm')
        }
        stages {
            stage('Static checks') {
                parallel {
                    stage('Lint') {
                        agent { kubernetes { inheritFrom 'ansible-runner'; defaultContainer 'runner' } }
                        steps { aci 'lint'; aci 'docs' }
                    }
                    stage('Certification') {
                        agent { kubernetes { inheritFrom 'ansible-runner'; defaultContainer 'runner' } }
                        steps { aci 'certification' }
                    }
                    stage('Build') {
                        agent { kubernetes { inheritFrom 'ansible-runner'; defaultContainer 'runner' } }
                        steps {
                            aci 'build'
                            archiveArtifacts artifacts: 'dist/*.tar.gz', fingerprint: true
                            aci 'importer'
                        }
                    }
                    stage('Security scan') {
                        agent { kubernetes { inheritFrom 'ansible-runner'; defaultContainer 'runner' } }
                        steps { aci 'security-scan', 'reports/security/*.xml' }
                    }
                    stage('Spotter') {
                        when { beforeAgent true; expression { env.SPOTTER_ENDPOINT } }
                        agent { kubernetes { inheritFrom 'ansible-runner'; defaultContainer 'runner' } }
                        steps {
                            // findings make the build UNSTABLE, not FAILED
                            catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                                withCredentials([string(credentialsId: 'spotter-api-token', variable: 'SPOTTER_TOKEN')]) {
                                    aci 'spotter', 'reports/spotter/*.xml'
                                }
                            }
                        }
                    }
                    stage('Changelog fragment') {
                        when { beforeAgent true; changeRequest() }
                        agent { kubernetes { inheritFrom 'ansible-runner'; defaultContainer 'runner' } }
                        steps { aci 'changelog-check' }
                    }
                }
            }
            stage('ansible-test') {
                matrix {
                    // AAP 2.6 ships ansible-core 2.16 and 2.18; 2.20 (AAP 2.7) is also required by the
                    // Red Hat certification sanity. All on Python 3.12, the Python of the AAP EEs.
                    axes { axis { name 'ACI_CORE'; values '2.16', '2.18', '2.20' } }
                    agent { kubernetes { inheritFrom 'ansible-runner'; defaultContainer 'runner' } }
                    stages {
                        stage('sanity') { steps { aci 'sanity', 'reports/sanity-*/junit/*.xml' } }
                        stage('units') {
                            when { expression { fileExists('tests/unit') } }
                            steps { aci 'units', 'reports/units-*/junit/*.xml' }
                        }
                    }
                }
            }
            // Integration and Molecule need Podman: they run on the ansible-builder VM. The `when` is
            // checked on the agent (after checkout), so the stage shows as skipped when the directory is absent.
            stage('Container tests') {
                parallel {
                    stage('Integration') {
                        agent { label 'ansible-builder' }
                        when { expression { fileExists('tests/integration/targets') } }
                        environment { ACI_TEST_MODE = 'docker' }
                        steps { aci 'integration', 'reports/integration-*/junit/*.xml' }
                    }
                    stage('Molecule') {
                        agent { label 'ansible-builder' }
                        when { expression { fileExists('extensions/molecule') } }
                        steps { aci 'molecule' }
                    }
                }
            }
            stage('Publish') {
                when { beforeAgent true; buildingTag() }
                agent { kubernetes { inheritFrom 'ansible-runner'; defaultContainer 'runner' } }
                steps {
                    aci 'build'
                    withCredentials([string(credentialsId: 'nexus-galaxy-hosted-token', variable: 'ACI_GALAXY_TOKEN')]) {
                        aci 'publish'
                    }
                }
            }
        }
    }
}

// Runs one `aci` subcommand, then archives reports/ and publishes the JUnit files matching `junitFiles`,
// even when the command fails. The exit code of `aci` alone decides the stage result.
void aci(String command, String junitFiles = '') {
    try {
        sh label: "aci ${command}", script: "/opt/ansible-ci/bin/aci ${command}"
    } finally {
        if (junitFiles) {
            junit allowEmptyResults: true, skipMarkingBuildUnstable: true, testResults: junitFiles
        }
        archiveArtifacts allowEmptyArchive: true, artifacts: 'reports/**', excludes: '**/.tmp/**'
    }
}
