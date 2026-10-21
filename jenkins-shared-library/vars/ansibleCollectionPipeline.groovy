import org.corp.ansibleci.Config

/*
 * Pipeline declaratif complet de test/validation d'une collection Ansible (airgap, Nexus).
 *
 *   @Library('ansible-ci@v1') _
 *   ansibleCollectionPipeline(ansibleCoreOptional: ['2.20'], integration: true, spotter: true,
 *                             spotterEndpoint: 'https://spotter.corp.local/api')
 *
 * Reference des parametres : ansibleCollectionPipeline.txt / GUIDE-UTILISATEUR.md.
 * La configuration est validee AVANT le pipeline : une cle inconnue ou une valeur invalide arrete le
 * build avec la liste de toutes les erreurs.
 */
def call(Map config = [:]) {
    Map res = Config.resolve(config, libraryResource('org/corp/ansibleci/aci/share/aci/python-map.txt'))
    if (res.errors) {
        error(Config.errorMessage('ansibleCollectionPipeline', res.errors))
    }
    Map cfg = res.cfg
    // les directives declaratives (options) n'acceptent que des variables, pas d'appels de methode
    String keep = "${cfg.buildsToKeep}"
    int globalTimeout = cfg.timeoutMinutes

    pipeline {
        agent none
        options {
            buildDiscarder(logRotator(numToKeepStr: keep))
            timeout(time: globalTimeout, unit: 'MINUTES')
            timestamps()
            skipDefaultCheckout()
        }
        stages {
            stage('Configuration') {
                steps {
                    echo "ansible-ci ${libraryResource('org/corp/ansibleci/aci/VERSION').trim()} | " +
                         (cfg.targetEEs ? "EE cibles ${cfg.targetEEs.join(' ')} (matrice derivee) | " : '') +
                         "ansible-core ${cfg.ansibleCoreVersions.join(' ')}" +
                         (cfg.ansibleCoreOptional ? " + non bloquant ${cfg.ansibleCoreOptional.join(' ')} " : ' ') +
                         "(defaut ${cfg.defaultCore}, pre-versions ${cfg.ansibleCorePrerelease.join(' ') ?: 'aucune'}) | " +
                         "mode ${aciBranches.testMode(cfg)} | agents ${cfg.agentType == 'label' ? cfg.runnerLabel : 'pod ' + cfg.runnerImage} / ${cfg.builderLabel}"
                }
            }
            stage('EE cibles (introspection)') {
                when { expression { !cfg.targetEEs.isEmpty() } }
                steps {
                    script {
                        aciNode(cfg, 'builder') {
                            Config.applyEeMatrix(cfg, ansibleEeIntrospect(images: cfg.targetEEs))
                        }
                    }
                }
            }
            stage('Controles statiques') {
                parallel {
                    stage('Changelog (PR)') {
                        when { expression { cfg.changelogCheck && env.CHANGE_ID != null } }
                        steps { script { aciNode(cfg, 'runner') { ansibleChangelogCheck(skipToken: cfg.changelogSkipToken) } } }
                    }
                    stage('Certification Red Hat') {
                        when { expression { cfg.certification } }
                        steps {
                            script {
                                aciNode(cfg, 'runner') {
                                    cfg.certificationCores = ansibleCertification(sanityCores: true)
                                    ansibleCertification()
                                }
                            }
                        }
                    }
                    stage('Lint') {
                        when { expression { cfg.lint } }
                        steps { script { aciNode(cfg, 'runner') { ansibleLint() } } }
                    }
                    stage('Docs') {
                        when { expression { cfg.docs } }
                        steps { script { aciNode(cfg, 'runner') { ansibleCollectionDocs() } } }
                    }
                    stage('Build + galaxy-importer') {
                        when { expression { cfg.build } }
                        steps {
                            script {
                                aciNode(cfg, 'runner') {
                                    ansibleCollectionBuild()
                                    archiveArtifacts artifacts: 'dist/*.tar.gz', fingerprint: true
                                    stash name: 'aci-dist', includes: 'dist/*.tar.gz'
                                    if (cfg.galaxyImporter) { galaxyImporter() }
                                }
                            }
                        }
                    }
                    stage('Securite') {
                        when { expression { cfg.securityScan } }
                        steps { script { aciNode(cfg, 'runner') { ansibleSecurityScan() } } }
                    }
                    stage('Spotter') {
                        when { expression { cfg.spotter } }
                        steps {
                            script {
                                aciNode(cfg, 'runner') {
                                    if (cfg.spotterBlocking) {
                                        spotterScan()
                                    } else {
                                        catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE', message: 'Spotter : non bloquant (spotterBlocking: false)') { spotterScan() }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            stage('ansible-test sanity / units') {
                when { expression { cfg.sanity || cfg.units } }
                steps { script { parallel aciBranches.tests(cfg) } }
            }
            stage('EE : units dans les EE (POC)') {
                when { expression { cfg.eeTests } }
                steps {
                    script {
                        Map b = [:]
                        List images = cfg.targetEEs
                        for (int i = 0; i < images.size(); i++) {
                            String image = images[i]
                            b["units dans ${image.tokenize('/').last()}"] = { aciNode(cfg, 'builder') { ansibleEeUnits(image: image) } }
                        }
                        parallel b
                    }
                }
            }
            stage('Integration') {
                when { expression { cfg.integration } }
                steps { script { parallel aciBranches.integration(cfg) } }
            }
            stage('Molecule') {
                when { expression { cfg.molecule } }
                steps {
                    script {
                        aciNode(cfg, 'builder') {
                            timeout(time: cfg.testTimeoutMinutes, unit: 'MINUTES') { moleculeTest() }
                        }
                    }
                }
            }
            stage('Publication') {
                when {
                    allOf {
                        expression { cfg.publish }
                        buildingTag()
                    }
                }
                steps {
                    script {
                        aciNode(cfg, 'runner') {
                            unstash 'aci-dist'
                            ansibleCollectionPublish()
                        }
                    }
                }
            }
        }
    }
}
