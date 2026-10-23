# shellcheck shell=bash
# help:   changelog-check changelogs/fragments/ fragment required on a PR/MR (+ antsibull-changelog lint)
# Detected context: Jenkins multibranch (CHANGE_ID, CHANGE_TARGET, CHANGE_TITLE) or GitLab
# (CI_MERGE_REQUEST_IID, CI_MERGE_REQUEST_TARGET_BRANCH_NAME, CI_MERGE_REQUEST_LABELS, ..._TITLE).
# Outside a PR/MR: nothing. Exemption: label or title containing ACI_CHANGELOG_SKIP (default "skip-changelog").
# Files that need no fragment: ACI_CHANGELOG_EXEMPT (egrep patterns, default: docs, tests, CI).
main() {
  local target=${ACI_TARGET_BRANCH:-${CHANGE_TARGET:-${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-}}}
  if [ -z "${CHANGE_ID:-}${CI_MERGE_REQUEST_IID:-}${ACI_TARGET_BRANCH:-}" ] || [ -z "$target" ]; then
    log "not a PR/MR: changelog fragment check skipped"; return 0
  fi
  local skip=${ACI_CHANGELOG_SKIP:-skip-changelog}
  case ",${CI_MERGE_REQUEST_LABELS:-},${CHANGE_TITLE:-}${CI_MERGE_REQUEST_TITLE:-}" in
    *"$skip"*) warn "exemption '$skip' (label or title): no fragment required"; return 0 ;;
  esac
  cd "$ACI_SRC" || die "ACI_SRC not found"
  # checkout done by another UID (GitLab pod, container): "dubious ownership" -> safe.directory given
  # as command-line configuration (protected scope, honoured by git), without touching ~/.gitconfig
  git() { command git -c safe.directory="$ACI_SRC" "$@"; }
  git rev-parse --verify -q "origin/$target" >/dev/null ||
    run git fetch --no-tags -q origin "+refs/heads/$target:refs/remotes/origin/$target" ||
    die "target branch origin/$target not found (shallow clone? allow fetching the target branch)"
  local base; base=$(git merge-base "origin/$target" HEAD) || die "no common ancestor with origin/$target (clone depth?)"
  local exempt=${ACI_CHANGELOG_EXEMPT:-'^(changelogs/|docs/|tests/|\.github/|\.gitlab-ci\.yml$|Jenkinsfile$|README\.md$|\.ansible-lint|\.yamllint|\.gitignore$)'}
  local changed fragments
  changed=$(git diff --name-only --diff-filter=ACMRD "$base" HEAD | grep -Ev -- "$exempt" || true)
  fragments=$(git diff --name-only --diff-filter=AM "$base" HEAD -- changelogs/fragments/ | grep -E '\.ya?ml$' || true)
  if [ -n "$changed" ] && [ -z "$fragments" ]; then
    printf '%s\n' "$changed" | sed 's/^/    /' >&2
    die "collection files changed without a changelogs/fragments/*.yml fragment (or label '$skip')"
  fi
  if [ -f changelogs/config.yaml ]; then aci_venv lint >/dev/null; run antsibull-changelog lint; fi
  log "changelog: ${fragments:-no fragment required}"
}
