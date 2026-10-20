import org.corp.ansibleci.Config

// INTERNE. Construit les branches `parallel` de la matrice ansible-core.
// Pourquoi pas la directive declarative `matrix` ? Ses `values` doivent etre des litteraux connus a la
// compilation du Jenkinsfile : une liste venant d'un parametre (cfg.ansibleCoreVersions) y est refusee.
// Une Map de closures passee a `parallel` dans un bloc script produit le meme affichage (une branche par
// serie) et accepte n'importe quelle liste.

/** venv | docker. 'auto' : docker sur fullTestBranches, les tags et les builds planifies, sinon venv. */
String testMode(Map cfg) {
    if (cfg.testMode != 'auto') return cfg.testMode
    boolean timer = !currentBuild.getBuildCauses('hudson.triggers.TimerTrigger$TimerTriggerCause').isEmpty()
    boolean full = env.TAG_NAME || timer || (env.BRANCH_NAME && cfg.fullTestBranches.contains(env.BRANCH_NAME))
    return full ? 'docker' : 'venv'
}

/** Erreur d'une serie en pre-version -> UNSTABLE au lieu de FAILURE (si prereleaseUnstable). */
def guard(boolean tolerant, String what, Closure body) {
    if (tolerant) {
        catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE', message: "${what} : echec non bloquant (pre-version)") { body() }
    } else {
        body()
    }
}

Map tests(Map cfg) {
    String mode = testMode(cfg)
    Map branches = [:]
    List rows = Config.matrix(cfg)
    for (int i = 0; i < rows.size(); i++) {
        Map row = rows[i]
        String name = Config.label(row)
        boolean tolerant = row.optional || (cfg.prereleaseUnstable && cfg.ansibleCorePrerelease.contains(row.core))
        branches[name] = {
            aciNode(cfg, mode == 'docker' ? 'builder' : 'runner') {
                withAnsibleCore(row.core) {
                    timeout(time: cfg.testTimeoutMinutes, unit: 'MINUTES') {
                        guard(tolerant, name) {
                            Map o = [testMode: mode]
                            if (row.python) { o.python = row.python }
                            if (row.pin) { o.corePin = row.pin }
                            if (cfg.sanity) { stage("sanity ${row.pin ?: row.core} (${mode})") { ansibleTestSanity(o) } }
                            if (cfg.units) { stage("units ${row.pin ?: row.core} (${mode})") { ansibleTestUnits(o) } }
                        }
                    }
                }
            }
        }
    }
    if (cfg.certification && cfg.certificationSanity) {
        // sanity de certification (stable-2.16/2.18/2.20 filtrees par requires_ansible, Python 3.12) ;
        // une serie deja testee a l'identique (meme serie, sans version figee, Python 3.12 ou libre) n'est pas rejouee
        List certCores = cfg.certificationCores ?: []
        for (int i = 0; i < certCores.size(); i++) {
            String core = certCores[i]
            boolean covered = rows.any { it.core == core && !it.pin && (it.python == null || it.python == '3.12') && !it.optional }
            if (covered) continue
            branches["certification sanity ${core} py3.12"] = {
                aciNode(cfg, mode == 'docker' ? 'builder' : 'runner') {
                    withAnsibleCore(core) {
                        timeout(time: cfg.testTimeoutMinutes, unit: 'MINUTES') {
                            stage("certification sanity ${core} (${mode})") { ansibleTestSanity(testMode: mode, python: '3.12') }
                        }
                    }
                }
            }
        }
    }
    branches.failFast = cfg.failFast
    return branches
}

Map integration(Map cfg) {
    Map branches = [:]
    List cores = cfg.integrationCoreVersions
    List images = cfg.integrationImages
    for (int i = 0; i < cores.size(); i++) {
        for (int j = 0; j < images.size(); j++) {
            String core = cores[i]
            String image = images[j]
            boolean tolerant = cfg.prereleaseUnstable && cfg.ansibleCorePrerelease.contains(core)
            branches["integration ${core} ${image}"] = {
                aciNode(cfg, 'builder') {
                    withAnsibleCore(core) {
                        timeout(time: cfg.testTimeoutMinutes, unit: 'MINUTES') {
                            guard(tolerant, "integration ${core} ${image}") { ansibleTestIntegration(image: image) }
                        }
                    }
                }
            }
        }
    }
    branches.failFast = cfg.failFast
    return branches
}

