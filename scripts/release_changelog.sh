#!/usr/bin/env bash
# Generate release notes from Conventional Commits since the last release tag,
# update CHANGELOG.md in place, and write RELEASE_NOTES.md for the GitHub
# release + update manifest. Invoked by the `release` job in .github/workflows/ci.yml.
#
# Usage: scripts/release_changelog.sh <new_version> <released_at_iso8601>
set -euo pipefail

NEW_VERSION="${1:?usage: release_changelog.sh <new_version> <released_at>}"
RELEASED_AT="${2:?usage: release_changelog.sh <new_version> <released_at>}"
DATE_ONLY="${RELEASED_AT%%T*}"
REPO_URL="https://github.com/jojoneku/nudgr-fasting-habit-app"
CHANGELOG="CHANGELOG.md"
NOTES_OUT="RELEASE_NOTES.md"

# Previous release tag (vX.Y.Z). The new tag doesn't exist yet at this point.
prev_tag="$(git tag -l 'v*' --sort=-v:refname | head -n1 || true)"
range="HEAD"
[ -n "$prev_tag" ] && range="${prev_tag}..HEAD"

feats=(); fixes=(); perfs=(); breaks=()
# `|| [ -n "$s" ]` processes the final line, which `git log --pretty=format`
# emits without a trailing newline (otherwise the oldest commit is dropped).
while IFS= read -r s || [ -n "$s" ]; do
  [ -z "$s" ] && continue
  case "$s" in
    "chore(release): bump version"*) continue ;;  # skip our own bump commits
  esac
  # Breaking changes (`type!:` / `type(scope)!:`) are listed only here, not
  # also under their type section.
  if printf '%s' "$s" | grep -qE '^[a-z]+(\([^)]+\))?!:'; then
    breaks+=("$(printf '%s' "$s" | sed -E 's/^[a-z]+(\([^)]+\))?!:[[:space:]]*//')")
    continue
  fi
  case "$s" in
    feat*) feats+=("$(printf '%s' "$s" | sed -E 's/^feat(\([^)]+\))?:[[:space:]]*//')") ;;
    fix*)  fixes+=("$(printf '%s' "$s" | sed -E 's/^fix(\([^)]+\))?:[[:space:]]*//')") ;;
    perf*) perfs+=("$(printf '%s' "$s" | sed -E 's/^perf(\([^)]+\))?:[[:space:]]*//')") ;;
  esac
done < <(git log "$range" --no-merges --pretty=format:'%s')

notes=""
add_section() {
  local title="$1"; local -n arr="$2"
  [ "${#arr[@]}" -eq 0 ] && return 0
  notes+="### ${title}"$'\n'
  local item
  for item in "${arr[@]}"; do notes+="- ${item}"$'\n'; done
  notes+=$'\n'
}
add_section "⚠ Breaking Changes" breaks
add_section "Added" feats
add_section "Fixed" fixes
add_section "Performance" perfs
[ -z "$notes" ] && notes="- Maintenance and internal improvements."$'\n\n'

printf '%s' "$notes" > "$NOTES_OUT"

# Rewrite CHANGELOG.md: reset [Unreleased] and insert the new version section
# above the previous entries. Commits are the source of truth, so the old
# [Unreleased] body is replaced (it regenerates from those same commits here).
awk -v ver="$NEW_VERSION" -v date="$DATE_ONLY" -v nf="$NOTES_OUT" '
  BEGIN { while ((getline l < nf) > 0) generated = generated l "\n" }
  /^## \[Unreleased\]/ {
    print "## [Unreleased]"; print "";
    print "## [" ver "] - " date; print "";
    printf "%s", generated;
    skip = 1; next
  }
  skip && (/^## \[/ || /^\[/) { skip = 0 }   # next version section or link refs
  skip { next }
  { print }
' "$CHANGELOG" > "${CHANGELOG}.tmp"
mv "${CHANGELOG}.tmp" "$CHANGELOG"

# Refresh link references.
sed -i -E "s#^\[Unreleased\]:.*#[Unreleased]: ${REPO_URL}/compare/v${NEW_VERSION}...HEAD#" "$CHANGELOG"
grep -qE "^\[${NEW_VERSION}\]:" "$CHANGELOG" || \
  printf '[%s]: %s/releases/tag/v%s\n' "$NEW_VERSION" "$REPO_URL" "$NEW_VERSION" >> "$CHANGELOG"

echo "Generated notes for v${NEW_VERSION}:"
echo "----"
cat "$NOTES_OUT"
