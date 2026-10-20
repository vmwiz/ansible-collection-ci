# shellcheck shell=bash
# aide:   changelog-check fragment changelogs/fragments/ obligatoire sur une PR/MR (+ antsibull-changelog lint)
# Contexte detecte : Jenkins multibranche (CHANGE_ID, CHANGE_TARGET, CHANGE_TITLE) ou GitLab
# (CI_MERGE_REQUEST_IID, CI_MERGE_REQUEST_TARGET_BRANCH_NAME, CI_MERGE_REQUEST_LABELS, ..._TITLE).
# Hors PR/MR : rien. Exemption : etiquette ou titre contenant ACI_CHANGELOG_SKIP (defaut "skip-changelog").
# Fichiers qui n'exigent pas de fragment : ACI_CHANGELOG_EXEMPT (motifs egrep, defaut : docs, tests, CI).
main() {
  local target=${ACI_TARGET_BRANCH:-${CHANGE_TARGET:-${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-}}}
  if [ -z "${CHANGE_ID:-}${CI_MERGE_REQUEST_IID:-}${ACI_TARGET_BRANCH:-}" ] || [ -z "$target" ]; then
    log "pas une PR/MR : controle du fragment de changelog ignore"; return 0
  fi
  local skip=${ACI_CHANGELOG_SKIP:-skip-changelog}
  case ",${CI_MERGE_REQUEST_LABELS:-},${CHANGE_TITLE:-}${CI_MERGE_REQUEST_TITLE:-}" in
    *"$skip"*) warn "exemption '$skip' (etiquette ou titre) : pas de fragment exige"; return 0 ;;
  esac
  cd "$ACI_SRC" || die "ACI_SRC introuvable"
  git rev-parse --verify -q "origin/$target" >/dev/null ||
    run git fetch --no-tags -q origin "+refs/heads/$target:refs/remotes/origin/$target" ||
    die "branche cible origin/$target introuvable (clone superficiel ? autoriser le fetch de la branche cible)"
  local base; base=$(git merge-base "origin/$target" HEAD) || die "pas d'ancetre commun avec origin/$target (profondeur de clone ?)"
  local exempt=${ACI_CHANGELOG_EXEMPT:-'^(changelogs/|docs/|tests/|\.github/|\.gitlab-ci\.yml$|Jenkinsfile$|README\.md$|\.ansible-lint|\.yamllint|\.gitignore$)'}
  local changed fragments
  changed=$(git diff --name-only --diff-filter=ACMRD "$base" HEAD | grep -Ev -- "$exempt" || true)
  fragments=$(git diff --name-only --diff-filter=AM "$base" HEAD -- changelogs/fragments/ | grep -E '\.ya?ml$' || true)
  if [ -n "$changed" ] && [ -z "$fragments" ]; then
    printf '%s\n' "$changed" | sed 's/^/    /' >&2
    die "fichiers de la collection modifies sans fragment changelogs/fragments/*.yml (ou etiquette '$skip')"
  fi
  if [ -f changelogs/config.yaml ]; then aci_venv lint >/dev/null; run antsibull-changelog lint; fi
  log "changelog : ${fragments:-aucun fragment requis}"
}
