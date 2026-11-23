#!/usr/bin/env bash
# Waits for pull request N's checks to finish and exits with their outcome.
#
#   dev/pr_wait.sh N
#
# `gh pr checks N --watch` run right after `gh pr create` exits at once with "no checks
# reported", because CI has not registered its checks yet. So this polls every
# ${PR_WAIT_POLL_SECONDS:-15} s, up to 20 polls (5 min, more when a poll's call is asked
# again), until the pull request has at least one check, then runs
# `gh pr checks N --watch --interval 30`.
#
# CI's gate job, named `check` (branch protection requires it), is created about a second
# after the last part job ends, so a watch can end with every check passed and none named
# `check`. The wait has ended only when a check named `check` is among the checks: the
# checks are read again every ${PR_WAIT_GATE_POLL_SECONDS:-5} s, up to 20 reads, until it
# appears; if it is then still pending the watch runs again.
#
# A GitHub call that fails is asked again, up to 3 tries in all, waiting
# ${PR_WAIT_RETRY_SECONDS:-15} s between tries, so a passing blip does not end the wait.
# `gh pr checks --watch` can also end while a check is still pending; then the checks'
# buckets decide: a failed or cancelled check ends the wait with 1, a pending one runs the
# watch again, up to 3 watches in all.
#
# Exit status:
#   0  every check passed
#   1  a check failed (the line `pr_wait: failing jobs: A, B` on stderr names them), or no
#      check appeared within the 20 polls
#   2  usage
#   3  a GitHub call failed on all 3 tries, or its answer was not the one asked for; nothing
#      is known of the checks. A failing `gh pr checks --watch` counts as a CI failure only
#      when a second question finds a check failed or cancelled; a check still pending after
#      the third watch, or a status the answer does not explain, is 3. So is a pull request
#      whose checks passed and none is named `check` within the 20 reads.
set -euo pipefail

[[ $# -eq 1 && $1 =~ ^[0-9]+$ ]] || { echo "usage: dev/pr_wait.sh N" >&2; exit 2; }
number=$1
gate_check=check

call_failed() {
  echo "pr_wait: a GitHub call failed ($1) on pull request $number" >&2
  exit 3
}

# Runs the command up to 3 times and prints the answer of the first try that succeeds.
ask() {
  local try answer
  for try in 1 2 3; do
    answer=$("$@") && { printf '%s\n' "$answer"; return 0; }
    [[ $try -lt 3 ]] && sleep "${PR_WAIT_RETRY_SECONDS:-15}"
  done
  return 1
}

checks=0
for _ in $(seq 20); do
  checks=$(ask gh pr view "$number" --json statusCheckRollup --jq '.statusCheckRollup | length') \
    || call_failed "gh pr view"
  [[ $checks =~ ^[0-9]+$ ]] || call_failed "gh pr view answered '$checks'"
  [[ $checks -gt 0 ]] && break
  sleep "${PR_WAIT_POLL_SECONDS:-15}"
done
if [[ $checks -eq 0 ]]; then
  echo "pr_wait: no check on pull request $number after 20 polls" >&2
  exit 1
fi

# read_buckets: sets buckets to one line `bucket name` per check; the call is asked again
# when it fails, and ends the wait as an error when it fails on every try.
read_buckets() {
  buckets=$(ask gh pr checks "$number" --json name,bucket --jq '.[] | "\(.bucket) \(.name)"') \
    || call_failed "gh pr checks ended with status $status and the checks could not be read"
}

# has_gate_check: succeeds when buckets holds the check named $gate_check.
has_gate_check() {
  grep -q " $gate_check$" <<< "$buckets"
}

for _ in 1 2 3; do
  status=0
  gh pr checks "$number" --watch --interval 30 || status=$?

  read_buckets
  if [[ $status -eq 0 ]]; then
    for _ in $(seq 19); do
      has_gate_check && break
      sleep "${PR_WAIT_GATE_POLL_SECONDS:-5}"
      read_buckets
    done
    if ! has_gate_check; then
      echo "pr_wait: every check passed, but no check named $gate_check appeared within 20 reads" >&2
      exit 3
    fi
  fi
  failing=""
  pending=""
  while read -r bucket name; do
    case $bucket in
      fail | cancel) failing+="${failing:+, }$name" ;;
      pending) pending+="${pending:+, }$name" ;;
    esac
  done <<< "$buckets"
  if [[ -n $failing ]]; then
    echo "pr_wait: failing jobs: $failing" >&2
    exit 1
  fi
  if [[ -z $pending ]]; then
    [[ $status -eq 0 ]] && exit 0
    echo "pr_wait: a GitHub call failed: gh pr checks ended with status $status but no check failed" >&2
    exit 3
  fi
done
echo "pr_wait: a GitHub call failed: gh pr checks ended with status $status while still pending: $pending" >&2
exit 3
