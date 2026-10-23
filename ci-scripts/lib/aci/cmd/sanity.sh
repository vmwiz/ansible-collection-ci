# shellcheck shell=bash
# help:   sanity          ansible-test sanity (ACI_CORE, ACI_TEST_MODE=venv|docker, ACI_SANITY_ARGS)
main() {
  aci_venv core >/dev/null
  aci_test_home
  local -a target
  if [ "$ACI_TEST_MODE" = venv ]; then
    # shellcheck disable=SC2207
    target=($(aci_venv_python_args) --requirements)
    if [ "${ACI_VENV_URL_REQS:-skip}" != allow ]; then
      local t
      for t in $(python "$ACI_PY/url_requirements.py"); do
        warn "sanity test '$t' skipped in venv mode: direct-URL pip requirement (not served by Nexus PyPI)"
        target+=(--skip-test "$t")
      done
    fi
  else
    aci_prime default utility
    target=(--docker default)
  fi
  aci_prepare_tree sanity
  # shellcheck disable=SC2046,SC2086
  aci_ansible_test "sanity-$(aci_core)" sanity "${target[@]}" --junit $(aci_common_test_args) ${ACI_SANITY_ARGS:-} "$@"
}
