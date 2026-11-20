#!/usr/bin/env bash
# Waits for pull request N's checks to finish and exits with their status; a pull request
# that is in the merge queue (or has auto-merge set) when its checks pass is followed on,
# until it is merged.
#
#   dev/pr_wait.sh N
#
# `gh pr checks N --watch` run right after `gh pr create` exits at once with "no checks
# reported", because CI has not registered its checks yet. So this polls every 15 s, up to
# 5 min, until the pull request has at least one check, then runs
# `gh pr checks N --watch --interval 30`. It exits 1 when no check appears within 5 min,
# and with the checks' status when they do not all pass.
#
# After passing checks it asks GitHub once whether the pull request is queued (the merge
# queue holds it, or `gh pr merge --auto` set auto-merge). If not, it exits 0 there. If so,
# it asks every PR_WAIT_QUEUE_POLL_SECONDS (default 30), up to PR_WAIT_QUEUE_POLLS times
# (default 240, two hours at the default), until the pull request is MERGED (exit 0) or has
# left the queue without merging (CLOSED, or OPEN and no longer queued: exit 1). The queue
# runs the checks again on the merge group the pull request is in, so the pull request's own
# checks passing is not yet its merge.
set -euo pipefail

[[ $# -eq 1 && $1 =~ ^[0-9]+$ ]] || { echo "usage: dev/pr_wait.sh N" >&2; exit 2; }
number=$1
poll_seconds=${PR_WAIT_QUEUE_POLL_SECONDS:-30}
polls=${PR_WAIT_QUEUE_POLLS:-240}

# state_of: "STATE QUEUED AUTO", e.g. "OPEN true false".
state_of() {
  gh api graphql -F owner='{owner}' -F name='{repo}' -F number="$number" \
    -f query='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){state isInMergeQueue autoMergeRequest{enabledAt}}}}' \
    --jq '.data.repository.pullRequest | "\(.state) \(.isInMergeQueue) \(.autoMergeRequest != null)"'
}

checks=0
for _ in $(seq 20); do
  checks=$(gh pr view "$number" --json statusCheckRollup --jq '.statusCheckRollup | length')
  [[ $checks -gt 0 ]] && break
  sleep 15
done
if [[ $checks -eq 0 ]]; then
  echo "pr_wait: no check on pull request $number after 5 min" >&2
  exit 1
fi

status=0
gh pr checks "$number" --watch --interval 30 || status=$?
[[ $status -eq 0 ]] || exit "$status"

read -r state queued auto <<<"$(state_of)"
if [[ $state == MERGED ]]; then
  echo "pr_wait: pull request $number merged"
  exit 0
fi
[[ $state == OPEN && ( $queued == true || $auto == true ) ]] || exit 0

for _ in $(seq "$polls"); do
  sleep "$poll_seconds"
  read -r state queued auto <<<"$(state_of)"
  case $state in
    MERGED)
      echo "pr_wait: pull request $number merged by the queue"
      exit 0 ;;
    CLOSED)
      echo "pr_wait: pull request $number was closed without merging" >&2
      exit 1 ;;
  esac
  if [[ $queued != true && $auto != true ]]; then
    echo "pr_wait: pull request $number left the merge queue without merging" >&2
    exit 1
  fi
done
echo "pr_wait: pull request $number still queued after $polls polls" >&2
exit 1
