#!/usr/bin/env bash
# Runs Codex read-only on a clean, detached worktree of a commit, and always removes it.
#
#   dev/codex_review.sh code BASE HEAD "instructions"   review the changes in BASE..HEAD
#   dev/codex_review.sh ask COMMIT "question"           a design question
#
# CODEX_REVIEW_SECONDS limits the run (default 900).
set -euo pipefail

mode=${1:-}
case "$mode" in
  code) [ $# -eq 4 ] || { sed -n '2,7p' "$0"; exit 2; }; base_name=$2; commit_name=$3; text=$4 ;;
  ask) [ $# -eq 3 ] || { sed -n '2,7p' "$0"; exit 2; }; commit_name=$2; text=$3 ;;
  *) sed -n '2,7p' "$0"; exit 2 ;;
esac

# Names like HEAD~1 mean another commit inside the worktree, so both are fixed as hashes first.
commit=$(git rev-parse --verify --quiet "$commit_name^{commit}") || { echo "codex_review: no commit $commit_name" >&2; exit 1; }
[ "$mode" = ask ] || base=$(git rev-parse --verify --quiet "$base_name^{commit}") || { echo "codex_review: no commit $base_name" >&2; exit 1; }

worktree=$(mktemp -d "${TMPDIR:-/tmp}/codex-review-XXXXXX")
rmdir "$worktree"
git worktree add --detach "$worktree" "$commit" >/dev/null

remove() {
  git worktree remove --force "$worktree" 2>/dev/null || { echo "codex_review: could not remove the worktree $worktree" >&2; exit 1; }
}
trap remove EXIT
trap 'exit 130' INT TERM

cd "$worktree"
seconds=${CODEX_REVIEW_SECONDS:-900}
case "$mode" in
  code)
    timeout --kill-after=10 "$seconds" codex review -c sandbox_mode='"read-only"' \
      "$text Review the changes in $base..$commit. Follow this repository's CLAUDE.md."
    ;;
  ask)
    timeout --kill-after=10 "$seconds" codex exec -s read-only "$text Follow this repository's CLAUDE.md."
    ;;
esac
