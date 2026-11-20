#!/usr/bin/env bash
# Merges pull request P only after CI passed on its branch combined with the current main.
#
#   dev/merge_when_green.sh P
#
# GitHub's merge queue is offered only to organization-owned repositories, so this script
# does its job one pull request at a time: run it for one pull request, and for the next
# when it ends. (Two runs at once stay correct, because each rechecks main after its CI,
# but each merge of one makes the other's CI stale and wastes a run.)
#
# It works in a temporary worktree of its own, made from origin/<the pull request's branch>
# and removed when the script ends, however it ends: the caller's checkout, its branch and
# its files are never touched, and a local copy of the branch is left behind the pushed
# one. Then, until it merges or stops:
#
#   1. origin/main is fetched. A branch that holds origin/main has had CI on exactly that
#      combination (CI tests the head merged with main), so nothing is merged in; otherwise
#      origin/main is merged into the worktree's copy of the branch, `./check fast` runs
#      there (the push hook requires it), and the merge is pushed to the branch.
#   2. dev/pr_wait.sh P waits for the head's checks.
#   3. origin/main is fetched again. If the branch holds it, `gh pr merge P --merge
#      --match-head-commit <head>` merges the pull request; if main moved while CI ran,
#      back to 1.
#
# It stops, with a line on stderr and exit 1, and leaves the branch as it was when:
#   - the merge of origin/main conflicts (the files are named; the merge is aborted);
#   - `./check fast` fails after the merge of main (nothing is pushed);
#   - a check fails (the failing jobs are named) or none appears;
#   - a GitHub or git call fails, the pull request is not open on main, origin/<branch>
#     is not the pull request's head, or the push is refused (the branch moved).
# A pull request merged by this script is read by the progress hook
# (dev/hooks/progress_lines.py) as the merge of P, so its CI and merge lines are posted.
#
# MERGE_WHEN_GREEN_POLL_SECONDS (default 5): the pause between asks while GitHub catches up
# with a push.
set -euo pipefail

die() {
  echo "merge_when_green: $*" >&2
  exit 1
}

[[ $# -eq 1 && $1 =~ ^[0-9]+$ ]] || { echo "usage: dev/merge_when_green.sh P" >&2; exit 2; }
number=$1
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repository=$(cd "$here/.." && pwd)
poll_seconds=${MERGE_WHEN_GREEN_POLL_SECONDS:-5}

view=$(gh pr view "$number" --json state,baseRefName,headRefName,headRefOid \
  --jq '[.state, .baseRefName, .headRefName, .headRefOid] | join(" ")') \
  || die "gh pr view $number failed"
read -r state base branch head <<<"$view"
[[ $state == OPEN && $base == main ]] \
  || die "pull request $number is $state on $base, not open on main"

work=$(mktemp -d "${TMPDIR:-/tmp}/merge-when-green.XXXXXX")
cleanup() {
  git -C "$repository" worktree remove --force "$work" >/dev/null 2>&1 || true
  rm -rf "$work" "$work.errors"
}
trap cleanup EXIT

fetch() {
  git -C "$repository" fetch -q origin main "$branch" || die "fetch of origin main and $branch failed"
}

# holds_main: succeeds when the worktree's HEAD holds origin/main.
holds_main() {
  local status=0
  git -C "$work" merge-base --is-ancestor origin/main HEAD || status=$?
  case $status in
    0) return 0 ;;
    1) return 1 ;;
    *) die "git merge-base failed (exit $status)" ;;
  esac
}

# merge_main_in: merges origin/main into the worktree's branch, checks it, pushes it, and
# waits until GitHub shows the pushed commit as the pull request's head.
merge_main_in() {
  local conflicted pushed seen=
  if ! git -C "$work" merge --no-edit -m "Merge remote-tracking branch 'origin/main' into $branch" \
    origin/main >/dev/null; then
    conflicted=$(git -C "$work" diff --name-only --diff-filter=U | tr '\n' ' ')
    git -C "$work" merge --abort || true
    die "origin/main conflicts with $branch in: ${conflicted:-(no file named)}; nothing was pushed"
  fi
  (cd "$work" && ./check fast) \
    || die "./check fast failed on $branch merged with origin/main; nothing was pushed"
  git -C "$work" push -q origin "HEAD:refs/heads/$branch" \
    || die "push of $branch was refused; it moved since this run started"
  pushed=$(git -C "$work" rev-parse HEAD)
  for _ in $(seq 20); do
    seen=$(gh pr view "$number" --json headRefOid --jq .headRefOid) || die "gh pr view $number failed"
    [[ $seen == "$pushed" ]] && return 0
    sleep "$poll_seconds"
  done
  die "GitHub still shows head ${seen:0:9} on pull request $number, not the pushed ${pushed:0:9}"
}

# wait_for_ci: waits for the head's checks; stops unless they all passed.
wait_for_ci() {
  local status=0 errors="$work.errors" failing
  "$here/pr_wait.sh" "$number" 2>"$errors" || status=$?
  cat "$errors" >&2
  failing=$(sed -n 's/^pr_wait: failing jobs: //p' "$errors")
  rm -f "$errors"
  case $status in
    0) ;;
    1) die "CI failed on pull request $number: ${failing:-no check passed}" ;;
    *) die "dev/pr_wait.sh could not tell the state of pull request $number (exit $status)" ;;
  esac
}

fetch
git -C "$repository" worktree add --detach "$work" "origin/$branch" \
  || die "no worktree of origin/$branch"
[[ $(git -C "$work" rev-parse HEAD) == "$head" ]] \
  || die "origin/$branch is not the head of pull request $number; fetch again and rerun"

if holds_main; then up_to_date=true; else up_to_date=false; fi
while true; do
  $up_to_date || merge_main_in
  wait_for_ci
  fetch
  holds_main && break
  up_to_date=false
done

head=$(git -C "$work" rev-parse HEAD)
gh pr merge "$number" --merge --match-head-commit "$head" || die "gh pr merge $number failed"
echo "merge_when_green: pull request $number merged at head ${head:0:9}"
