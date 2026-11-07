#!/usr/bin/env bash
# tested_tree.sh REPOSITORY COMMIT JOB...: finds out whether COMMIT holds exactly the
# files of a tree that a passed run of every job tested, so the work is not done twice.
# A pull request's run tests its head merged with main as it was then, not the head
# alone, so each job records the tree it checked out as a `tested tree TREE` notice
# (see .github/workflows/check.yml), and a merge commit of a pull request that was
# current with main has that tree. Used by the check workflow (the push to main skips
# its jobs) and by update.sh (the play server deploys the merge without waiting for
# its own run).
#
# Asks GitHub (gh, logged in or with GH_TOKEN) for the commit's tree and parents, and
# for each parent its check runs: every job named has run on it, every run ended
# `success` and carries the notice with COMMIT's tree. Prints the parent that
# qualifies and exits 0; exits 1 when none does (a run from before the notice existed
# does not), 2 when GitHub could not be asked.
#
# Usage: tested_tree.sh owner/repo COMMIT check tools
set -euo pipefail

[ "$#" -ge 3 ] || { echo "usage: tested_tree.sh REPOSITORY COMMIT JOB..." >&2; exit 2; }
repository=$1
commit=$2
shift 2

# passed COMMIT JOB: 0 when the job has a run on the commit, every run ended success
# and every run's annotations hold the notice for $tree (a re-run replaces the run it
# repeats: the API lists the latest of each by default).
passed() {
  local runs id conclusion notices
  runs=$(gh api "repos/$repository/commits/$1/check-runs?per_page=100" \
    --jq ".check_runs[] | select(.name == \"$2\") | \"\\(.id) \\(.status):\\(.conclusion)\"") || return 2
  [ -n "$runs" ] || return 1
  while read -r id conclusion; do
    [ "$conclusion" = completed:success ] || return 1
    notices=$(gh api "repos/$repository/check-runs/$id/annotations?per_page=100" --jq '.[].message') || return 2
    grep -qx "tested tree $tree" <<<"$notices" || return 1
  done <<<"$runs"
}

tree=$(gh api "repos/$repository/commits/$commit" --jq '.commit.tree.sha') || exit 2
parents=$(gh api "repos/$repository/commits/$commit" --jq '.parents[].sha') || exit 2

for parent in $parents; do
  ok=1
  for job in "$@"; do
    status=0
    passed "$parent" "$job" || status=$?
    case $status in
      0) ;;
      1) ok=0 ;;
      *) exit 2 ;;
    esac
  done
  if [ "$ok" = 1 ]; then
    echo "$parent"
    exit 0
  fi
done
exit 1
