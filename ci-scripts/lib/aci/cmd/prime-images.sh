# shellcheck shell=bash
# help:   prime-images    pre-pulls the ansible-test images of ACI_CORE from Nexus (aliases: default utility ubuntu2404...)
main() {
  aci_venv core >/dev/null
  [ $# -gt 0 ] || set -- default utility
  aci_prime "$@"
}
