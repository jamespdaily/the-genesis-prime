#!/usr/bin/env bash
# tested_tree.sh REPOSITORY COMMIT JOB...: finds out whether COMMIT holds exactly the
# files of a commit whose checks already passed, so the work is not done twice.
# A merge commit of a pull request that was current with main has the tree of the
# pull request's head, and the head's jobs ran on that tree. Used by the check
# workflow (the push to main skips its jobs) and by update.sh (the play server
# deploys the merge without waiting for its own run).
#
# Asks GitHub (gh, logged in or with GH_TOKEN) for the commit's tree and parents, and
# for each parent whose tree is the same, its check runs: every job named has run on
# it and ended `success`. Prints the parent that qualifies and exits 0; exits 1 when
# none does, 2 when GitHub could not be asked.
#
# Usage: tested_tree.sh owner/repo COMMIT check tools
set -euo pipefail

[ "$#" -ge 3 ] || { echo "usage: tested_tree.sh REPOSITORY COMMIT JOB..." >&2; exit 2; }
repository=$1
commit=$2
shift 2

# passed COMMIT JOB: 0 when the job has a run on the commit and every run ended success
# (a re-run replaces the run it repeats: the API lists the latest of each by default).
passed() {
  local runs
  runs=$(gh api "repos/$repository/commits/$1/check-runs?per_page=100" \
    --jq ".check_runs[] | select(.name == \"$2\") | \"\\(.status):\\(.conclusion)\"") || return 2
  [ -n "$runs" ] || return 1
  if printf '%s\n' "$runs" | grep -qv '^completed:success$'; then
    return 1
  fi
}

lines=$(gh api "repos/$repository/commits/$commit" --jq '.commit.tree.sha, .parents[].sha') || exit 2
tree=$(printf '%s\n' "$lines" | sed -n 1p)
parents=$(printf '%s\n' "$lines" | sed 1d)

for parent in $parents; do
  parent_tree=$(gh api "repos/$repository/commits/$parent" --jq '.commit.tree.sha') || exit 2
  [ "$parent_tree" = "$tree" ] || continue
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
