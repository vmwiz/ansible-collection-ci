package org.corp.ansibleci

import com.cloudbees.groovy.cps.NonCPS

/**
 * Configuration de la bibliotheque ansible-ci : valeurs par defaut, validation, traduction en
 * variables d'environnement ACI_* lues par les scripts bash `aci` (resources/org/corp/ansibleci/aci).
 *
 * Classe sans aucune etape Jenkins : toutes les methodes sont @NonCPS (calcul pur, rapide, pas de
 * serialisation d'iterateurs) et testables hors Jenkins (test/unit). Syntaxe compatible Groovy 2.4.
 */
class Config implements Serializable {
    private static final long serialVersionUID = 1L

    /** Cles reconnues et valeurs par defaut (ordre = ordre de la documentation). */
    static final Map DEFAULTS = [
        // --- matrice ansible-core / Python
        // AAP 2.6 : ansible-core 2.16 et 2.18 (EE Python 3.12). 2.20 = AAP 2.7 -> ansibleCoreOptional
        ansibleCoreVersions    : ['2.16', '2.18'],
        ansibleCoreOptional    : [],
        ansibleCorePrerelease  : [],
        targetEEs              : [],
        ansibleCoreDefault     : null,
        pythonMap              : [:],
        prereleaseUnstable     : true,
        // --- etapes
        lint                   : true,
        docs                   : true,
        build                  : true,
        galaxyImporter         : true,
        securityScan           : true,
        spotter                : false,
        certification          : true,
        certificationSanity    : true,
        changelogCheck         : true,
        changelogSkipToken     : 'skip-changelog',
        eeTests                : false,
        sanity                 : true,
        units                  : true,
        integration            : false,
        molecule               : false,
        publish                : true,
        // --- mode ansible-test
        testMode               : 'auto',
        fullTestBranches       : ['main', 'master'],
        integrationCoreVersions: [],
        integrationImages      : ['default'],
        moleculeImages         : ['ubuntu2404', 'fedora40'],
        sanityArgs             : '',
        unitsArgs              : '',
        integrationArgs        : '',
        dockerNetwork          : '',
        coverage               : false,
        failFast               : false,
        // --- agents
        agentType              : 'kubernetes',
        podTemplateYaml        : null,
        podCloud               : null,
        runnerImage            : 'nexus.corp.local:8443/ci/ansible-collection-runner:2026.10',
        jnlpImage              : 'nexus.corp.local:8443/jenkins/inbound-agent:latest-jdk21',
        runnerLabel            : 'ansible-runner',
        builderLabel           : 'ansible-builder',
        containerEngine        : 'podman',
        scriptsFrom            : 'library',
        agentScriptsPath       : '/opt/ansible-ci/bin/aci',
        // --- Nexus / Galaxy
        pipIndexUrl            : null,   // null : /etc/pip.conf de l'image/VM (seul lu par ansible-test --venv)
        pypiEndpoint           : 'https://nexus.corp.local/repository/pypi-group/simple',   // conteneurs ansible-test (mode docker)
        imageMirror            : 'nexus.corp.local:8444',
        galaxyServerUrl        : 'https://nexus.corp.local/repository/ansible-group/',
        galaxyPublishUrl       : 'https://nexus.corp.local/repository/ansible-hosted/',
        galaxyCredentialsId    : 'nexus-galaxy-hosted-token',
        // --- scanners
        securityFailOn         : 'high',
        securityReportSeverity : null,
        spotterEndpoint        : null,
        spotterCredentialsId   : 'spotter-api-token',
        spotterCaCert          : '/etc/pki/tls/certs/ca-bundle.crt',
        spotterAnsibleVersion  : '2.20',
        spotterDisplayLevel    : 'error',
        spotterBlocking        : false,
        // --- divers
        timeoutMinutes         : 90,
        testTimeoutMinutes     : 45,
        buildsToKeep           : 20,
        color                  : true,
        extraEnv               : [:],
    ]

    static final Map CHOICES = [
        testMode           : ['venv', 'docker', 'auto'],
        agentType          : ['kubernetes', 'label'],
        scriptsFrom        : ['library', 'agent'],
        securityFailOn     : ['high', 'critical', 'none'],
        securityReportSeverity: ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'],
        spotterDisplayLevel: ['hint', 'warning', 'error'],
        containerEngine    : ['podman', 'docker'],
    ]

    static final List URL_KEYS = ['pipIndexUrl', 'pypiEndpoint', 'galaxyServerUrl', 'galaxyPublishUrl', 'spotterEndpoint']
    static final List SPECIAL_CORES = ['devel', 'milestone']

    /** Lit python-map.txt : "2.20  3.12 3.13 3.14" -> ['2.20': ['3.12','3.13','3.14']] (ordre conserve). */
    @NonCPS
    static Map parsePythonMap(String text) {
        Map map = [:]
        text.readLines().each { String line ->
            String l = line.trim()
            if (l && !l.startsWith('#')) {
                List parts = l.split(/\s+/) as List
                map[parts[0]] = parts.drop(1)
            }
        }
        return map
    }

    /**
     * Fusionne la configuration utilisateur avec les defauts et la valide.
     * @param partial true pour les etapes granulaires : seules les cles fournies sont retournees.
     * @param extraKeys cles supplementaires admises (options propres a une etape).
     * @return [cfg: Map, errors: List<String>]
     */
    @NonCPS
    static Map resolve(Map user, String pythonMapText, boolean partial = false, List extraKeys = []) {
        List errors = []
        Map given = user ?: [:]
        Map cfg = partial ? [:] : new LinkedHashMap(DEFAULTS)
        Map known = parsePythonMap(pythonMapText)

        given.each { k, v ->
            String key = k.toString()
            if (extraKeys.contains(key)) { cfg[key] = v; return }
            if (!DEFAULTS.containsKey(key)) {
                String hint = closest(key, (DEFAULTS.keySet() as List) + extraKeys)
                errors << "parametre inconnu '${key}'" + (hint ? " (vouliez-vous dire '${hint}' ?)" : '')
                return
            }
            Object err = typeError(key, v)
            if (err) { errors << err.toString() } else { cfg[key] = normalize(key, v) }
        }

        // tables Python : celle de la bibliotheque + surcharges pythonMap
        Map pyMap = new LinkedHashMap(known)
        (cfg.pythonMap ?: [:]).each { c, pys ->
            if (!(pys instanceof List) || pys.isEmpty()) { errors << "pythonMap['${c}'] doit etre une liste non vide, ex. ['3.12', '3.11']" }
            else { pyMap[c.toString()] = pys.collect { it.toString() } }
        }
        cfg.supportedCores = pyMap.keySet() as List

        CHOICES.each { key, allowed ->
            if (cfg[key] != null && !allowed.contains(cfg[key])) {
                errors << "${key} = '${cfg[key]}' : valeurs possibles ${allowed.join(' | ')}"
            }
        }
        URL_KEYS.each { key ->
            if (cfg[key] && !(cfg[key] ==~ /https?:\/\/\S+/)) { errors << "${key} = '${cfg[key]}' : URL http(s) attendue" }
        }

        List cores = cfg.ansibleCoreVersions
        if (cores != null) {
            if (cores.isEmpty() && !partial) errors << 'ansibleCoreVersions est vide'
            cores.findAll { !pyMap.containsKey(it) }.each {
                errors << "ansible-core '${it}' inconnu : series prises en charge ${pyMap.keySet().join(', ')} (ou pythonMap: ['${it}': ['3.x']])"
            }
            if (cores.unique(false).size() != cores.size()) errors << "ansibleCoreVersions contient des doublons : ${cores}"
        }
        if (cfg.ansibleCoreOptional != null) {
            cfg.ansibleCoreOptional.findAll { !pyMap.containsKey(it) }.each { errors << "ansibleCoreOptional : serie '${it}' inconnue" }
            if (cores != null) cfg.ansibleCoreOptional.findAll { cores.contains(it) }.each { errors << "ansibleCoreOptional : '${it}' figure deja dans ansibleCoreVersions" }
        }
        if (cfg.targetEEs) {
            if (given.containsKey('ansibleCoreVersions')) {
                errors << 'targetEEs et ansibleCoreVersions sont exclusifs : avec targetEEs, la matrice est derivee des EE (introspection)'
            }
            cfg.targetEEs.findAll { !(it ==~ /[^\s]+/) }.each { errors << "targetEEs : reference d'image invalide '${it}'" }
        }
        if (cfg.ansibleCorePrerelease != null) {
            cfg.ansibleCorePrerelease.findAll { !pyMap.containsKey(it) }.each { errors << "ansibleCorePrerelease : serie '${it}' inconnue" }
        }
        if (cfg.ansibleCoreDefault && cores != null && !cores.contains(cfg.ansibleCoreDefault)) {
            errors << "ansibleCoreDefault '${cfg.ansibleCoreDefault}' absent d'ansibleCoreVersions ${cores}"
        }
        if (!partial) {
            cfg.defaultCore = cfg.ansibleCoreDefault ?: defaultCore(cores, cfg.ansibleCorePrerelease)
            if (!cfg.defaultCore) errors << 'impossible de choisir la serie par defaut : definir ansibleCoreDefault'
            if (cfg.integrationCoreVersions.isEmpty()) {
                cfg.integrationCoreVersions = cfg.defaultCore ? [cfg.defaultCore] : []
                cfg.integrationCoreDefaulted = true
            }
            cfg.integrationCoreVersions.findAll { !cores.contains(it) }.each {
                errors << "integrationCoreVersions : '${it}' absent d'ansibleCoreVersions ${cores}"
            }
            if (cfg.spotter && !cfg.spotterEndpoint) errors << "spotter: true exige spotterEndpoint (instance Spotter privee, ex. 'https://spotter.corp.local/api') : sans lui la CLI vise le SaaS"
            if (cfg.galaxyImporter && !cfg.build) errors << 'galaxyImporter: true exige build: true'
            if (cfg.eeTests && !cfg.targetEEs) errors << 'eeTests: true exige targetEEs'
            if (cfg.publish && !cfg.build) errors << 'publish: true exige build: true'
            if (cfg.publish && !cfg.galaxyPublishUrl) errors << 'publish: true exige galaxyPublishUrl'
            if (cfg.agentType == 'kubernetes' && !cfg.podTemplateYaml && !cfg.runnerImage) errors << 'agentType kubernetes : runnerImage ou podTemplateYaml requis'
            ['timeoutMinutes', 'testTimeoutMinutes', 'buildsToKeep'].each { if (cfg[it] <= 0) errors << "${it} doit etre > 0" }
            if (cfg.integrationImages.isEmpty() && cfg.integration) errors << 'integration: true exige au moins une image dans integrationImages'
        }
        (cfg.extraEnv ?: [:]).each { k, v ->
            if (!(k.toString() ==~ /[A-Za-z_][A-Za-z0-9_]*/)) errors << "extraEnv : nom de variable invalide '${k}'"
        }
        cfg.pythonMapResolved = pyMap
        return [cfg: cfg, errors: errors]
    }

    /** Derniere serie de la liste qui n'est pas une pre-version ni devel/milestone. */
    @NonCPS
    static String defaultCore(List cores, List prerelease) {
        List stable = (cores ?: []).findAll { !(prerelease ?: []).contains(it) && !SPECIAL_CORES.contains(it) }
        return stable ? stable.last() : (cores ? cores.last() : null)
    }

    /** Variables ACI_* pour withEnv (seules les cles presentes dans cfg sont traduites). */
    @NonCPS
    static List toEnv(Map cfg) {
        List e = []
        def put = { String name, Object value -> if (value != null) e << "${name}=${value}".toString() }
        def joined = { Object v -> v == null ? null : (v instanceof List ? v.join(' ') : v.toString()) }
        if (cfg.containsKey('ansibleCoreVersions')) put('ACI_CORE_VERSIONS', joined(cfg.ansibleCoreVersions + (cfg.ansibleCoreOptional ?: [])))
        if (cfg.containsKey('ansibleCorePrerelease')) put('ACI_PRERELEASE', joined(cfg.ansibleCorePrerelease))
        if (cfg.containsKey('defaultCore')) put('ACI_CORE_DEFAULT', cfg.defaultCore)
        if (cfg.containsKey('ansibleCoreDefault') && cfg.ansibleCoreDefault) put('ACI_CORE_DEFAULT', cfg.ansibleCoreDefault)
        put('ACI_PIP_INDEX_URL', cfg.pipIndexUrl)
        put('ACI_PYPI_ENDPOINT', cfg.pypiEndpoint)
        put('ACI_IMAGE_MIRROR', cfg.imageMirror)
        put('ACI_GALAXY_URL', cfg.galaxyServerUrl)
        put('ACI_GALAXY_PUBLISH_URL', cfg.galaxyPublishUrl)
        put('ACI_CONTAINER_ENGINE', cfg.containerEngine)
        put('ACI_SECURITY_FAIL_ON', cfg.securityFailOn)
        put('ACI_SECURITY_SEVERITY', cfg.securityReportSeverity)
        put('SPOTTER_ENDPOINT', cfg.spotterEndpoint)
        put('SPOTTER_CACERT', cfg.spotterCaCert)
        put('ACI_SPOTTER_ANSIBLE_VERSION', cfg.spotterAnsibleVersion)
        put('ACI_SPOTTER_DISPLAY_LEVEL', cfg.spotterDisplayLevel)
        put('ACI_SANITY_ARGS', cfg.sanityArgs ?: null)
        put('ACI_UNITS_ARGS', cfg.unitsArgs ?: null)
        put('ACI_INTEGRATION_ARGS', cfg.integrationArgs ?: null)
        put('ACI_DOCKER_NETWORK', cfg.dockerNetwork ?: null)
        put('ACI_MOLECULE_IMAGES', joined(cfg.moleculeImages))
        if (cfg.containsKey('coverage')) put('ACI_COVERAGE', cfg.coverage.toString())
        if (cfg.containsKey('color')) put('ACI_COLOR', cfg.color.toString())
        put('ACI_SCRIPTS_FROM', cfg.scriptsFrom)
        put('ACI_AGENT_SCRIPTS', cfg.agentScriptsPath)
        put('ACI_SPOTTER_CREDENTIALS_ID', cfg.spotterCredentialsId)
        put('ACI_GALAXY_CREDENTIALS_ID', cfg.galaxyCredentialsId)
        (cfg.extraEnv ?: [:]).each { k, v -> put(k.toString(), v) }
        return e
    }

    /**
     * Matrice des tests : une entree par (serie, Python, version exacte) a tester.
     * Sans targetEEs : ansibleCoreVersions (bloquantes) + ansibleCoreOptional (non bloquantes).
     * Avec targetEEs : les lignes "serie python version image" de `aci ee-introspect` (eeMatrix).
     */
    @NonCPS
    static List matrix(Map cfg) {
        List rows = []
        if (cfg.eeMatrix) {
            cfg.eeMatrix.each { Map e -> rows << [core: e.core, python: e.python, pin: e.pin, image: e.image, optional: false] }
            return rows.unique { [it.core, it.python, it.pin] }
        }
        (cfg.ansibleCoreVersions ?: []).each { rows << [core: it, python: null, pin: null, image: null, optional: false] }
        (cfg.ansibleCoreOptional ?: []).each { rows << [core: it, python: null, pin: null, image: null, optional: true] }
        return rows
    }

    /** Applique la matrice issue de l'introspection des EE (series, serie par defaut, integration). */
    @NonCPS
    static void applyEeMatrix(Map cfg, List rows) {
        cfg.eeMatrix = rows
        cfg.ansibleCoreVersions = rows.collect { it.core }.unique()
        cfg.defaultCore = cfg.ansibleCoreDefault && cfg.ansibleCoreVersions.contains(cfg.ansibleCoreDefault) ?
            cfg.ansibleCoreDefault : defaultCore(cfg.ansibleCoreVersions, cfg.ansibleCorePrerelease)
        if (cfg.integrationCoreDefaulted) cfg.integrationCoreVersions = [cfg.defaultCore]
    }

    /** Lit reports/ee/matrix.txt ("2.16 3.12 2.16.19 hub/ee-minimal-rhel9:2.16"). */
    @NonCPS
    static List parseEeMatrix(String text) {
        List rows = []
        text.readLines().each { String l ->
            List p = l.trim().split(/\s+/) as List
            if (p.size() >= 4) rows << [core: p[0], python: p[1], pin: p[2], image: p[3]]
        }
        return rows
    }

    /** Libelle d'une entree de matrice pour les branches parallel. */
    @NonCPS
    static String label(Map e) {
        String s = "ansible-core ${e.pin ?: e.core}" + (e.python ? " py${e.python}" : '')
        if (e.image) s += " (${e.image.tokenize('/').last()})"
        if (e.optional) s += ' [non bloquant]'
        return s
    }

    /** Table Python au format python-map.txt (passee a aci via ACI_PYTHON_MAP si surchargee). */
    @NonCPS
    static String renderPythonMap(Map pyMap) {
        return pyMap.collect { c, pys -> "${c} ${pys.join(' ')}" }.join('\n') + '\n'
    }

    /** Message d'erreur multi-ligne lisible. */
    @NonCPS
    static String errorMessage(String step, List errors) {
        return "${step} : configuration invalide\n" + errors.collect { "  - ${it}" }.join('\n') +
            "\n  (reference des parametres : `help` de l'etape, ou GUIDE-UTILISATEUR.md)"
    }

    // ---------------------------------------------------------------------------------------------
    @NonCPS
    private static Object typeError(String key, Object v) {
        Object d = DEFAULTS[key]
        if (v == null) return null
        if (key == 'ansibleCoreDefault' || key == 'podTemplateYaml' || key == 'podCloud' || key == 'pypiEndpoint' ||
            key == 'spotterEndpoint' || key == 'securityReportSeverity') {
            return (v instanceof CharSequence) ? null : "${key} : chaine attendue, recu ${v.getClass().simpleName}"
        }
        if (d instanceof Boolean && !(v instanceof Boolean)) return "${key} : booleen attendu (true/false), recu '${v}'"
        if (d instanceof Integer && !(v instanceof Number)) return "${key} : nombre attendu, recu '${v}'"
        if (d instanceof List) {
            if (!(v instanceof List)) return "${key} : liste attendue, ex. ${key}: ['${v}']"
            if (v.any { !(it instanceof CharSequence) }) return "${key} : liste de chaines attendue (attention : 2.20 sans guillemets est un nombre), ex. ['2.20']"
        }
        if (d instanceof Map && !(v instanceof Map)) return "${key} : map attendue, ex. ${key}: [CLE: 'valeur']"
        if (d instanceof CharSequence && !(v instanceof CharSequence)) return "${key} : chaine attendue, recu '${v}'"
        return null
    }

    @NonCPS
    private static Object normalize(String key, Object v) {
        if (key == 'securityReportSeverity') return v.toString().toUpperCase()
        if (v instanceof CharSequence) return v.toString()
        if (v instanceof List) return v.collect { it.toString() }
        if (v instanceof Number && DEFAULTS[key] instanceof Integer) return v.intValue()
        return v
    }

    @NonCPS
    private static String closest(String key, List candidates) {
        String best = null
        int bestD = 4
        candidates.each { String c ->
            int d = distance(key.toLowerCase(), c.toLowerCase())
            if (d < bestD) { bestD = d; best = c }
        }
        return best
    }

    @NonCPS
    private static int distance(String a, String b) {
        int[] prev = new int[b.length() + 1]
        for (int j = 0; j <= b.length(); j++) prev[j] = j
        for (int i = 1; i <= a.length(); i++) {
            int[] cur = new int[b.length() + 1]
            cur[0] = i
            for (int j = 1; j <= b.length(); j++) {
                int cost = a.charAt(i - 1) == b.charAt(j - 1) ? 0 : 1
                cur[j] = Math.min(Math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost)
            }
            prev = cur
        }
        return prev[b.length()]
    }
}
