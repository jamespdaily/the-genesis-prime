#!/usr/bin/env bash
# Waits for pull request N's checks to finish and exits with their status.
#
#   dev/pr_wait.sh N
#
# `gh pr checks N --watch` run right after `gh pr create` exits at once with "no checks
# reported", because CI has not registered its checks yet. So this polls every 15 s, up to
# 5 min, until the pull request has at least one check, then runs
# `gh pr checks N --watch --interval 30` and exits with its status. It exits 1 when no
# check appears within 5 min.
set -euo pipefail

[[ $# -eq 1 && $1 =~ ^[0-9]+$ ]] || { echo "usage: dev/pr_wait.sh N" >&2; exit 2; }
number=$1

for _ in $(seq 20); do
  checks=$(gh pr view "$number" --json statusCheckRollup --jq '.statusCheckRollup | length')
  [[ $checks -gt 0 ]] && exec gh pr checks "$number" --watch --interval 30
  sleep 15
done
echo "pr_wait: no check on pull request $number after 5 min" >&2
exit 1
