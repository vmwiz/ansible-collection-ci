# shellcheck shell=bash
# aide:   info            affiche la configuration resolue (serie, Python, mode, Nexus...)
main() {
  local core; core=$(aci_core)
  echo "aci            $ACI_VERSION ($ACI_HOME)"
  echo "collection     $ACI_SRC"
  echo "ansible-core   $core ($(aci_core_spec "$core"))"
  echo "python         $(aci_python "$core")"
  echo "mode           $ACI_TEST_MODE"
  echo "galaxy         ${ACI_GALAXY_URL:-<defaut ansible>}"
  echo "miroir images  ${ACI_IMAGE_MIRROR:-<aucun>}"
  echo "cache          $ACI_CACHE"
}
