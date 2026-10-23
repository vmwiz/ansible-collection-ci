# shellcheck shell=bash
# help:   integration     ansible-test integration --docker <ACI_INTEGRATION_IMAGE> (agent with podman/docker)
main() {
  if [ ! -d "$ACI_SRC/tests/integration/targets" ]; then log "no tests/integration/targets: nothing to do"; return 0; fi
  [ "$ACI_TEST_MODE" = docker ] || die "integration needs ACI_TEST_MODE=docker and an agent with a container engine (ansible-builder VM)"
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
