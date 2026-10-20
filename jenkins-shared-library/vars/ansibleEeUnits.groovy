// POC (non teste sans registry.redhat.io) : ansible-test units DANS l'image d'une EE cible
// (podman, agent ansible-builder), avec le Python et les bibliotheques de l'EE.
// Aide : ansibleEeUnits.txt
def call(Map opts = [:]) {
    Map o = new LinkedHashMap(opts)
    String image = o.remove('image')
    if (!image) error('ansibleEeUnits : image requise')
    aciRun(step: 'ansibleEeUnits', command: 'ee-units', opts: o + [args: [image]],
           junit: "reports/ee-units-${image.tokenize('/').last().replace(':', '-')}/junit/*.xml")
}
