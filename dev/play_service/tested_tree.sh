#!/usr/bin/env bash
# tested_tree.sh REPOSITORY COMMIT JOB...: finds out whether COMMIT holds exactly the
# files of a tree that a passed run of every job tested, so the work is not done twice.
# A pull request's run tests its head merged with main as it was then, not the head
# alone, and a merge group's run tests the group's commit itself, so each job records the
# tree it checked out as a `tested tree TREE` notice (see .github/workflows/check.yml).
# A commit the merge queue made is the commit of the merge group's run, so it has the tree
# that run tested; a merge commit of a pull request that was current with main has the
# tree of its pull request's run. Used by the check workflow (the push to main skips its
# jobs) and by update.sh (the play server deploys the merge without waiting for its own
# run).
#
# Asks GitHub (gh, logged in or with GH_TOKEN) for the commit's tree and parents. A
# candidate qualifies when every job named has run on it, every run ended `success` and
# carries the notice with COMMIT's tree. The candidates, in order: COMMIT itself, by the
# runs of the merge_group event on it; then each parent, by its check runs. Prints the
# candidate that qualifies and exits 0; exits 1 when none does (a run from before the
# notice existed does not), 2 when GitHub could not be asked.
#
# Usage: tested_tree.sh owner/repo COMMIT check tools
set -euo pipefail

[ "$#" -ge 3 ] || { echo "usage: tested_tree.sh REPOSITORY COMMIT JOB..." >&2; exit 2; }
repository=$1
commit=$2
shift 2

# verdict RUNS: 0 when RUNS (one "ID STATUS:CONCLUSION" line per run) is not empty, every
# run ended success and every run's annotations hold the notice for $tree.
verdict() {
  local id conclusion notices
  [ -n "$1" ] || return 1
  while read -r id conclusion; do
    [ "$conclusion" = completed:success ] || return 1
    notices=$(gh api "repos/$repository/check-runs/$id/annotations?per_page=100" --jq '.[].message') || return 2
    grep -qx "tested tree $tree" <<<"$notices" || return 1
  done <<<"$1"
}

# passed COMMIT JOB: the verdict on the job's check runs on the commit (a re-run replaces
# the run it repeats: the API lists the latest of each by default).
passed() {
  local runs
  runs=$(gh api "repos/$repository/commits/$1/check-runs?per_page=100" \
    --jq ".check_runs[] | select(.name == \"$2\") | \"\\(.id) \\(.status):\\(.conclusion)\"") || return 2
  verdict "$runs"
}

# passed_in_merge_group COMMIT JOB: the verdict on the job in the merge_group runs of the
# commit (the jobs of a run are listed at their latest attempt; a job's id is its check
# run's id).
passed_in_merge_group() {
  local ids id jobs runs=
  ids=$(gh api "repos/$repository/actions/runs?head_sha=$1&event=merge_group&per_page=100" \
    --jq '.workflow_runs[].id') || return 2
  for id in $ids; do
    jobs=$(gh api "repos/$repository/actions/runs/$id/jobs?per_page=100" \
      --jq ".jobs[] | select(.name == \"$2\") | \"\\(.id) \\(.status):\\(.conclusion)\"") || return 2
    runs+=${jobs:+$jobs$'\n'}
  done
  verdict "${runs%$'\n'}"
}

# qualifies COMMIT KIND JOB...: 0 when every job passed on the commit, by its merge_group
# runs (KIND "group") or by its check runs (KIND "check-runs"); 1 when one did not, 2 when
# GitHub could not be asked.
qualifies() {
  local candidate=$1 kind=$2 job status
  shift 2
  for job in "$@"; do
    status=0
    if [ "$kind" = group ]; then
      passed_in_merge_group "$candidate" "$job" || status=$?
    else
      passed "$candidate" "$job" || status=$?
    fi
    [ "$status" = 0 ] || return "$status"
  done
}

tree=$(gh api "repos/$repository/commits/$commit" --jq '.commit.tree.sha') || exit 2
parents=$(gh api "repos/$repository/commits/$commit" --jq '.parents[].sha') || exit 2

# The candidates, each "SHA KIND".
candidates=("$commit group")
for parent in $parents; do
  candidates+=("$parent check-runs")
done
for candidate in "${candidates[@]}"; do
  status=0
  qualifies "${candidate% *}" "${candidate#* }" "$@" || status=$?
  case $status in
    0) echo "${candidate% *}"; exit 0 ;;
    1) ;;
    *) exit 2 ;;
  esac
done
exit 1
