// molecule test (scenarios extensions/molecule, ansible-native) : agent avec podman (VM ansible-builder).
// Aide : moleculeTest.txt
def call(Map opts = [:]) {
    Map o = new LinkedHashMap(opts)
    List images = o.remove('images')
    if (images != null) o.moleculeImages = images
    aciRun(step: 'moleculeTest', command: 'molecule', opts: o)
}
