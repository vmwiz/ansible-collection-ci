import org.corp.ansibleci.Config

// Introspection des EE cibles (podman : agent ansible-builder) -> matrice [core, python, pin, image].
// Echoue immediatement si une EE est incompatible (requires_ansible, plage Python controleur, serie inconnue).
// Aide : ansibleEeIntrospect.txt
List call(Map opts = [:]) {
    Map o = new LinkedHashMap(opts)
    List images = o.remove('images') ?: (o.remove('targetEEs') ?: [])
    if (!images) error('ansibleEeIntrospect : images (ou targetEEs) requis, ex. images: [\'hub.corp.local/ee-minimal-rhel9:2.16\']')
    o.args = images
    aciRun(step: 'ansibleEeIntrospect', command: 'ee-introspect', opts: o)
    List rows = Config.parseEeMatrix(readFile('reports/ee/matrix.txt'))
    echo "Matrice derivee des EE : ${rows.collect { Config.label(it) }.join(' | ')}"
    return rows
}
