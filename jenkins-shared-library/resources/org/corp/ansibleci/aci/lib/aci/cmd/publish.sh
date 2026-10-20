# shellcheck shell=bash
# aide:   publish         ansible-galaxy collection publish vers ACI_GALAXY_PUBLISH_URL (jeton ACI_GALAXY_TOKEN)
main() {
  [ -n "${ACI_GALAXY_PUBLISH_URL:-}" ] || die "ACI_GALAXY_PUBLISH_URL non defini (ex. Nexus ansible-hosted)"
  [ -n "${ACI_GALAXY_TOKEN:-}" ] || die "ACI_GALAXY_TOKEN absent (credential CI)"
  aci_venv core >/dev/null
  local tarball; tarball=$(aci_tarball)
  [ -f "$tarball" ] || die "$tarball absent : lancer d'abord 'aci build'"
  # tag Git (Jenkins TAG_NAME, GitLab CI_COMMIT_TAG) = version de galaxy.yml, avec ou sans 'v'
  local tag=${ACI_RELEASE_TAG:-${TAG_NAME:-${CI_COMMIT_TAG:-}}} version
  read -r _ _ version < <(aci_meta)
  if [ -n "$tag" ] && [ "${tag#v}" != "$version" ]; then
    die "tag '$tag' different de la version galaxy.yml '$version' : publication refusee"
  fi
  ANSIBLE_GALAXY_SERVER_ACI_PUBLISH_TOKEN=$ACI_GALAXY_TOKEN aci_galaxy collection publish "$tarball" --server aci_publish "$@"
}
