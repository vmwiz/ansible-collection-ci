# shellcheck shell=bash
# help:   info            shows the resolved configuration (series, Python, mode, Nexus...)
main() {
  local core; core=$(aci_core)
  echo "aci            $ACI_VERSION ($ACI_HOME)"
  echo "collection     $ACI_SRC"
  echo "ansible-core   $core ($(aci_core_spec "$core"))"
  echo "python         $(aci_python "$core")"
  echo "mode           $ACI_TEST_MODE"
  echo "galaxy         ${ACI_GALAXY_URL:-<ansible default>}"
  echo "image mirror   ${ACI_IMAGE_MIRROR:-<none>}"
  echo "cache          $ACI_CACHE"
}
