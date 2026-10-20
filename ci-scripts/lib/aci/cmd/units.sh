# shellcheck shell=bash
# aide:   units           ansible-test units --requirements (ACI_CORE, ACI_TEST_MODE, ACI_UNITS_ARGS)
main() {
  if [ ! -d "$ACI_SRC/tests/unit" ]; then log "pas de tests/unit : rien a faire"; return 0; fi
  aci_venv core >/dev/null
  aci_test_home
  local -a target
  if [ "$ACI_TEST_MODE" = venv ]; then
    # shellcheck disable=SC2207
    target=($(aci_venv_python_args))
  else
    aci_prime default utility
    target=(--docker default)
  fi
  aci_prepare_tree units
  # shellcheck disable=SC2046,SC2086
  aci_ansible_test "units-$(aci_core)" units "${target[@]}" --requirements $(aci_common_test_args) ${ACI_UNITS_ARGS:-} "$@"
}
