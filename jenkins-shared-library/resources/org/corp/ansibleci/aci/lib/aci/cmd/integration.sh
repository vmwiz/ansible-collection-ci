# shellcheck shell=bash
# aide:   integration     ansible-test integration --docker <ACI_INTEGRATION_IMAGE> (agent avec podman/docker)
main() {
  if [ ! -d "$ACI_SRC/tests/integration/targets" ]; then log "pas de tests/integration/targets : rien a faire"; return 0; fi
  [ "$ACI_TEST_MODE" = docker ] || die "integration exige ACI_TEST_MODE=docker et un agent avec moteur de conteneurs (VM ansible-builder)"
  local image=${ACI_INTEGRATION_IMAGE:-default}
  aci_venv core >/dev/null
  aci_test_home
  aci_prime "$image" utility
  aci_prepare_tree integration
  local -a extra=()
  [ -n "${ACI_DOCKER_NETWORK:-}" ] && extra=(--docker-network "$ACI_DOCKER_NETWORK")
  # shellcheck disable=SC2046,SC2086
  aci_ansible_test "integration-$(aci_core)-$image" integration --docker "$image" --retry-on-error --continue-on-error \
      "${extra[@]}" $(aci_common_test_args) ${ACI_INTEGRATION_ARGS:-} "$@"
}
