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
# It works in one merge worktree, $HOME/.genesis-prime/merge-worktree (or
# MERGE_WHEN_GREEN_WORKTREE): made on first use, reused by every later run, and reset to
# origin/<the pull request's branch> at the start of each run, so it never holds uncommitted
# work (untracked files are removed; ignored ones stay) and its build/ stays warm. A fresh
# worktree builds cold, and ./check fast (budget 29 s) is stopped as hung at 3 times that.
# One run at a time uses it: a second run stops at once, naming the first's pid. A run
# changes no branch, file or worktree of the caller's, except that the fetch updates
# origin/main and origin/<branch> in the caller's repository and the merge worktree is
# registered in its .git. Then, until it merges or stops:
#
#   1. origin/main is fetched. A branch that holds origin/main has had CI on exactly that
#      combination (CI tests the head merged with main), so nothing is merged in; otherwise
#      origin/main is merged into the worktree's copy of the branch, `./check fast` runs
#      there (so the merge commit builds before it is pushed), and the merge is pushed to the branch.
#   2. dev/pr_wait.sh P waits for the head's checks.
#   3. origin/main is fetched again. If the branch holds it, `gh pr merge P --merge
#      --match-head-commit <head>` merges the pull request; if main moved while CI ran,
#      back to 1, at most 3 merges of main in one run.
#
# It stops, with a line on stderr and exit 1, in one of two states.
#
# Nothing of this run is pushed (the branch is as it was) when:
#   - the pull request is not open on main, or origin/<branch> is not its head;
#   - the merge of origin/main conflicts (the files are named; the merge is aborted);
#   - `./check fast` fails after the merge of main;
#   - the push is refused (the branch moved);
#   - another run holds the merge worktree, the worktree path holds another repository's
#     worktree, or a git call fails before the push.
#
# The merge of origin/main is already pushed, and stays on the branch, when, after a push:
#   - a check fails (the failing jobs are named) or none appears, so a failure of CI on the
#     merge leaves the pull request's branch ahead of the caller's local copy;
#   - a GitHub call fails, `gh pr merge` is refused, or main moved 3 times in a row.
# After such a stop the caller pulls the branch before working on it. A stop at the first
# wait, with nothing merged in, has pushed nothing.
#
# The merge itself is pinned to the head that CI passed on; main is not pinned, so a push to
# main between the last fetch and `gh pr merge` can still land first.
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
work=${MERGE_WHEN_GREEN_WORKTREE:-$HOME/.genesis-prime/merge-worktree}
lock="$work.lock"
max_merges=3
errors=

view=$(gh pr view "$number" --json state,baseRefName,headRefName,headRefOid \
  --jq '[.state, .baseRefName, .headRefName, .headRefOid] | join(" ")') \
  || die "gh pr view $number failed"
read -r state base branch head <<<"$view"
[[ $state == OPEN && $base == main ]] \
  || die "pull request $number is $state on $base, not open on main"

# take_lock: makes the lock (a symlink to this run's pid, so its content appears with it); a
# lock whose run is gone is taken over.
take_lock() {
  local holder
  mkdir -p "$(dirname "$work")"
  until ln -s "$$" "$lock" 2>/dev/null; do
    holder=$(readlink "$lock" || true)
    if [[ -n $holder ]] && kill -0 "$holder" 2>/dev/null; then
      die "another run (pid $holder) is using $work; run one at a time"
    fi
    rm -f "$lock"
  done
}

cleanup() {
  pkill -P $$ 2>/dev/null || true
  rm -f "$lock" ${errors:+"$errors"}
}

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
  local status=0 failing
  errors=$(mktemp "${TMPDIR:-/tmp}/merge-when-green.XXXXXX")
  "$here/pr_wait.sh" "$number" 2>"$errors" || status=$?
  cat "$errors" >&2
  failing=$(sed -n 's/^pr_wait: failing jobs: //p' "$errors")
  rm -f "$errors"
  errors=
  case $status in
    0) ;;
    1) die "CI failed on pull request $number: ${failing:-no check passed}" ;;
    *) die "dev/pr_wait.sh could not tell the state of pull request $number (exit $status)" ;;
  esac
}

# prepare_worktree: makes the merge worktree when it is absent, then resets it to
# origin/<branch>. An existing folder must be a worktree of this repository.
prepare_worktree() {
  local mine theirs=
  if [[ -e $work/.git ]]; then
    mine=$(git -C "$repository" rev-parse --path-format=absolute --git-common-dir) \
      || die "git rev-parse failed in $repository"
    theirs=$(git -C "$work" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || theirs=
    [[ $mine == "$theirs" ]] \
      || die "$work is not a worktree of $repository; remove it and rerun"
  else
    git -C "$repository" worktree prune
    git -C "$repository" worktree add --detach "$work" "origin/$branch" \
      || die "no worktree of origin/$branch at $work"
  fi
  git -C "$work" reset -q --hard "origin/$branch" || die "reset of $work to origin/$branch failed"
  git -C "$work" clean -fdq || die "clean of $work failed"
}

take_lock
trap cleanup EXIT
fetch
prepare_worktree
[[ $(git -C "$work" rev-parse HEAD) == "$head" ]] \
  || die "origin/$branch is not the head of pull request $number; fetch again and rerun"

if holds_main; then up_to_date=true; else up_to_date=false; fi
merges=0
while true; do
  if ! $up_to_date; then
    ((merges < max_merges)) \
      || die "origin/main moved again after $max_merges rounds of merge and CI; the merge of main is pushed to $branch, so pull it; rerun to go on"
    merges=$((merges + 1))
    merge_main_in
  fi
  wait_for_ci
  fetch
  holds_main && break
  up_to_date=false
done

head=$(git -C "$work" rev-parse HEAD)
gh pr merge "$number" --merge --match-head-commit "$head" || die "gh pr merge $number failed"
echo "merge_when_green: pull request $number merged at head ${head:0:9}"
