# shellcheck shell=bash
# aide:   prime-images    pre-tire depuis Nexus les images ansible-test d'ACI_CORE (alias : default utility ubuntu2404...)
main() {
  aci_venv core >/dev/null
  [ $# -gt 0 ] || set -- default utility
  aci_prime "$@"
}
