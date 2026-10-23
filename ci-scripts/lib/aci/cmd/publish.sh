# shellcheck shell=bash
# help:   publish         ansible-galaxy collection publish to ACI_GALAXY_PUBLISH_URL (token ACI_GALAXY_TOKEN)
main() {
  [ -n "${ACI_GALAXY_PUBLISH_URL:-}" ] || die "ACI_GALAXY_PUBLISH_URL not set (e.g. Nexus ansible-hosted)"
  [ -n "${ACI_GALAXY_TOKEN:-}" ] || die "ACI_GALAXY_TOKEN missing (CI credential)"
  aci_venv core >/dev/null
  local tarball; tarball=$(aci_tarball)
  [ -f "$tarball" ] || die "$tarball missing: run 'aci build' first"
  # Git tag (Jenkins TAG_NAME, GitLab CI_COMMIT_TAG) = galaxy.yml version, with or without 'v'
  local tag=${ACI_RELEASE_TAG:-${TAG_NAME:-${CI_COMMIT_TAG:-}}} version
  read -r _ _ version < <(aci_meta)
  if [ -n "$tag" ] && [ "${tag#v}" != "$version" ]; then
    die "tag '$tag' differs from galaxy.yml version '$version': publication refused"
  fi
  ANSIBLE_GALAXY_SERVER_ACI_PUBLISH_TOKEN=$ACI_GALAXY_TOKEN aci_galaxy collection publish "$tarball" --server aci_publish "$@"
}
