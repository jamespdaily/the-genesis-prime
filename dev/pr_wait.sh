#!/usr/bin/env bash
# Waits for pull request N's checks to finish and exits with their outcome.
#
#   dev/pr_wait.sh N
#
# `gh pr checks N --watch` run right after `gh pr create` exits at once with "no checks
# reported", because CI has not registered its checks yet. So this polls every 15 s, up to
# 5 min, until the pull request has at least one check, then runs
# `gh pr checks N --watch --interval 30`.
#
# Exit status:
#   0  every check passed
#   1  a check failed (the line `pr_wait: failing jobs: A, B` on stderr names them), or no
#      check appeared within 5 min
#   2  usage
#   3  a GitHub call failed, or its answer was not the one asked for; nothing is known of the
#      checks. A failing `gh pr checks --watch` counts as a CI failure only when a second
#      question finds a check failed or cancelled; a status the answer does not explain is 3.
set -euo pipefail

[[ $# -eq 1 && $1 =~ ^[0-9]+$ ]] || { echo "usage: dev/pr_wait.sh N" >&2; exit 2; }
number=$1

call_failed() {
  echo "pr_wait: a GitHub call failed ($1) on pull request $number" >&2
  exit 3
}

checks=0
for _ in $(seq 20); do
  checks=$(gh pr view "$number" --json statusCheckRollup --jq '.statusCheckRollup | length') \
    || call_failed "gh pr view"
  [[ $checks =~ ^[0-9]+$ ]] || call_failed "gh pr view answered '$checks'"
  [[ $checks -gt 0 ]] && break
  sleep 15
done
if [[ $checks -eq 0 ]]; then
  echo "pr_wait: no check on pull request $number after 5 min" >&2
  exit 1
fi

status=0
gh pr checks "$number" --watch --interval 30 || status=$?
[[ $status -eq 0 ]] && exit 0

failing=$(gh pr checks "$number" --json name,bucket \
  --jq '[.[] | select(.bucket == "fail" or .bucket == "cancel") | .name] | join(", ")') \
  || call_failed "gh pr checks ended with status $status and the failing jobs could not be read"
if [[ -z $failing ]]; then
  echo "pr_wait: a GitHub call failed: gh pr checks ended with status $status but no check failed" >&2
  exit 3
fi
echo "pr_wait: failing jobs: $failing" >&2
exit 1
