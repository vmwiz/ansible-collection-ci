/*
 * ansible-ci: the one CI pipeline for Ansible collections (airgapped, Nexus, AAP 2.6).
 * Stages, matrix and behaviour are fixed: every collection runs exactly the same pipeline.
 * Only site settings can be overridden (see DEFAULTS below). A collection Jenkinsfile is:
 *
 *   @Library('ansible-ci@v2') _
 *   ansibleCollectionPipeline()                                    // or, e.g.:
 *   ansibleCollectionPipeline(spotterEndpoint: 'https://spotter.corp.local/api', spotterCredentialsId: 'my-team-spotter')
 *
 * All the work is done by the `aci` CLI baked into the ci-tools-image and the ansible-builder VM
 * (/opt/ansible-ci/bin/aci). The OpenShift pod comes from resources/ansible-ci/pod.yaml.
 * Optional stages (units, integration, Molecule) run only when the matching directory exists.
 */
import groovy.transform.Field

// Site defaults: the ONLY configurable values. Any key passed to ansibleCollectionPipeline() must be one of these.
@Field final Map DEFAULTS = [
    galaxyUrl           : 'https://nexus.corp.local/repository/ansible-group/',      // Galaxy group: collection dependencies
    galaxyPublishUrl    : 'https://nexus.corp.local/repository/ansible-hosted/',     // Galaxy hosted: publication on tags
    pypiEndpoint        : 'https://nexus.corp.local/repository/pypi-group/simple',   // PyPI inside ansible-test containers
    imageMirror         : 'nexus.corp.local:8444',                                   // Docker proxy of quay.io
    spotterEndpoint     : '',                                                        // private Spotter API; empty = Spotter skipped
    spotterCacert       : '/etc/pki/tls/certs/ca-bundle.crt',                        // CA bundle for the Spotter API
    ciToolsImage        : 'nexus.corp.local:8443/corp/ci-tools-image:2026.10',       // image of the 'runner' container (= aci version)
    builderLabel        : 'ansible-builder',                                         // Jenkins label of the Podman VMs
    spotterCredentialsId: 'spotter-api-token',                                       // Jenkins credential ID (Secret text)
    galaxyCredentialsId : 'nexus-galaxy-hosted-token',                               // Jenkins credential ID (Secret text)
]

def call(Map config = [:]) {
    def unknown = config.keySet() - DEFAULTS.keySet()
    if (unknown) {
        error "ansibleCollectionPipeline: unknown parameter(s) ${unknown}. Allowed: ${DEFAULTS.keySet().join(', ')}"
    }
    Map cfg = DEFAULTS + config
    // Computed once: declarative evaluates `agent` per stage.
    String podYaml = libraryResource('ansible-ci/pod.yaml').replace('@@CI_TOOLS_IMAGE@@', cfg.ciToolsImage as String)

    pipeline {
        agent none
        options {
            buildDiscarder(logRotator(numToKeepStr: '20'))
            timeout(time: 90, unit: 'MINUTES')
            timestamps()
            ansiColor('xterm')
        }
        environment {   // names read by aci
            ACI_GALAXY_URL         = "${cfg.galaxyUrl}"
            ACI_GALAXY_PUBLISH_URL = "${cfg.galaxyPublishUrl}"
            ACI_PYPI_ENDPOINT      = "${cfg.pypiEndpoint}"
            ACI_IMAGE_MIRROR       = "${cfg.imageMirror}"
            SPOTTER_ENDPOINT       = "${cfg.spotterEndpoint}"
            SPOTTER_CACERT         = "${cfg.spotterCacert}"
        }
        stages {
            stage('Static checks') {
                parallel {
                    stage('Lint') {
                        agent { kubernetes { yaml podYaml; defaultContainer 'runner' } }
                        steps { aci 'lint'; aci 'docs' }
                    }
                    stage('Certification') {
                        agent { kubernetes { yaml podYaml; defaultContainer 'runner' } }
                        steps { aci 'certification' }
                    }
                    stage('Build') {
                        agent { kubernetes { yaml podYaml; defaultContainer 'runner' } }
                        steps {
                            aci 'build'
                            archiveArtifacts artifacts: 'dist/*.tar.gz', fingerprint: true
                            aci 'importer'
                        }
                    }
                    stage('Security scan') {
                        agent { kubernetes { yaml podYaml; defaultContainer 'runner' } }
                        steps { aci 'security-scan', 'reports/security/*.xml' }
                    }
                    stage('Spotter') {
                        when { beforeAgent true; expression { cfg.spotterEndpoint } }
                        agent { kubernetes { yaml podYaml; defaultContainer 'runner' } }
                        steps {
                            // findings make the build UNSTABLE, not FAILED
                            catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                                withCredentials([string(credentialsId: cfg.spotterCredentialsId, variable: 'SPOTTER_TOKEN')]) {
                                    aci 'spotter', 'reports/spotter/*.xml'
                                }
                            }
                        }
                    }
                    stage('Changelog fragment') {
                        when { beforeAgent true; changeRequest() }
                        agent { kubernetes { yaml podYaml; defaultContainer 'runner' } }
                        steps { aci 'changelog-check' }
                    }
                }
            }
            stage('ansible-test') {
                matrix {
                    // AAP 2.6 ships ansible-core 2.16 and 2.18; 2.20 (AAP 2.7) is also required by the
                    // Red Hat certification sanity. All on Python 3.12, the Python of the AAP EEs.
                    axes { axis { name 'ACI_CORE'; values '2.16', '2.18', '2.20' } }
                    agent { kubernetes { yaml podYaml; defaultContainer 'runner' } }
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
                        agent { label "${cfg.builderLabel}" }
                        when { expression { fileExists('tests/integration/targets') } }
                        environment { ACI_TEST_MODE = 'docker' }
                        steps { aci 'integration', 'reports/integration-*/junit/*.xml' }
                    }
                    stage('Molecule') {
                        agent { label "${cfg.builderLabel}" }
                        when { expression { fileExists('extensions/molecule') } }
                        steps { aci 'molecule' }
                    }
                }
            }
            stage('Publish') {
                when { beforeAgent true; buildingTag() }
                agent { kubernetes { yaml podYaml; defaultContainer 'runner' } }
                steps {
                    aci 'build'
                    withCredentials([string(credentialsId: cfg.galaxyCredentialsId, variable: 'ACI_GALAXY_TOKEN')]) {
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
