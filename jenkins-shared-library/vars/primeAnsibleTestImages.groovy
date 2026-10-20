// Pre-tire depuis le miroir Nexus (imageMirror) les images ansible-test de la serie courante et les
// re-tague sous quay.io/... (ansible-test ne tire pas une image deja presente).
// Aide : primeAnsibleTestImages.txt
def call(Map opts = [:]) {
    Map o = new LinkedHashMap(opts)
    List images = o.remove('images') ?: ['default', 'utility']
    o.args = images
    aciRun(step: 'primeAnsibleTestImages', command: 'prime-images', opts: o)
}
