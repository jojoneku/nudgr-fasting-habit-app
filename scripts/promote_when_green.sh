#!/usr/bin/env bash
# Open (or find) a promotion PR and merge it once its required checks pass.
# Invoked by the `promote_to_main` and `promote_hotfix` jobs in
# .github/workflows/ci.yml.
#
# Usage: scripts/promote_when_green.sh --base <branch> --head <branch> \
#          --title <pr title> --body <pr body>
#
# One file rather than three inline copies: the loop below encodes several
# non-obvious GitHub behaviours (see the comments), and keeping three drifting
# copies of it is how the "merge already in progress" case got missed.
set -uo pipefail

base="" head="" title="" body=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="$2"; shift 2 ;;
    --head) head="$2"; shift 2 ;;
    --title) title="$2"; shift 2 ;;
    --body) body="$2"; shift 2 ;;
    *) echo "::error::promote_when_green.sh: unknown argument '$1'"; exit 2 ;;
  esac
done

: "${base:?--base is required}"
: "${head:?--head is required}"
: "${title:?--title is required}"
: "${body:?--body is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"

repo="$GITHUB_REPOSITORY"

find_pr() {
  gh pr list --base "$base" --head "$head" --repo "$repo" \
    --json number --jq '.[0].number' 2>/dev/null || true
}

pr=$(find_pr)
if [ -z "$pr" ]; then
  # `gh pr create` fails with "No commits between ..." when there is nothing
  # left to promote. That is the ordinary outcome when a concurrent promotion
  # run already merged this branch, so it must not fail the job.
  gh pr create --base "$base" --head "$head" \
    --title "$title" --body "$body" --repo "$repo" || true
  pr=$(find_pr)
fi

if [ -z "$pr" ]; then
  echo "Nothing to promote: no open $head → $base PR, and none could be created."
  exit 0
fi

echo "Waiting on PR #$pr ($head → $base)."

# Merge once the required checks pass, polling mergeStateStatus.
#
# Do NOT gate on "no checks with a null conclusion": right after the PR is
# opened its own pull_request-triggered checks haven't registered yet, so the
# rollup shows only the already-finished push checks. That reads as "all done"
# and fires an immediate merge while the required checks are still queued,
# which GitHub rejects ("Repository rule violations found / required status
# checks are queued") — and because the mutation fails, the PR is left open
# with no auto-merge armed to retry once the checks pass.
#
# mergeStateStatus is BLOCKED while required checks are pending and CLEAN once
# they pass. The initial sleep lets the PR's own checks register so the state
# isn't transiently CLEAN before they appear.
sleep 20
for _ in $(seq 1 90); do
  read -r state merge_state <<<"$(
    gh pr view "$pr" --repo "$repo" --json state,mergeStateStatus \
      --jq '"\(.state) \(.mergeStateStatus)"' 2>/dev/null || echo "UNKNOWN UNKNOWN"
  )"

  case "$state" in
    MERGED)
      echo "PR #$pr is merged."
      exit 0
      ;;
    CLOSED)
      echo "::error::PR #$pr was closed without merging."
      exit 1
      ;;
  esac

  case "$merge_state" in
    CLEAN|UNSTABLE|HAS_HOOKS)
      if out=$(gh pr merge "$pr" --merge --repo "$repo" 2>&1); then
        echo "$out"
        echo "Merged PR #$pr ($head → $base)."
        exit 0
      fi
      echo "$out"
      # Two promotion runs can overlap — GitHub's cancellation of a superseded
      # run is asynchronous, so the older run's merge call may still be in
      # flight. GitHub answers the second caller with "Merge already in
      # progress". That means the promotion IS happening; failing here is what
      # painted dev red while main got the code anyway. Fall through and let
      # the next poll observe state == MERGED.
      if grep -qiE 'merge already in progress|already merged' <<<"$out"; then
        echo "::notice::PR #$pr is already being merged by another run; waiting for it to land."
      else
        echo "::error::Failed to merge PR #$pr."
        exit 1
      fi
      ;;
    DIRTY)
      echo "::error::PR #$pr has merge conflicts; not merging."
      exit 1
      ;;
  esac

  sleep 10
done

echo "::error::Timed out waiting for PR #$pr ($head → $base) to become mergeable."
exit 1
