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
  code) [ $# -eq 4 ] || { sed -n '2,7p' "$0"; exit 2; }; base=$2; commit=$3; text=$4 ;;
  ask) [ $# -eq 3 ] || { sed -n '2,7p' "$0"; exit 2; }; commit=$2; text=$3 ;;
  *) sed -n '2,7p' "$0"; exit 2 ;;
esac

git rev-parse --verify --quiet "$commit^{commit}" >/dev/null || { echo "codex_review: no commit $commit" >&2; exit 1; }
[ "$mode" = ask ] || git rev-parse --verify --quiet "$base^{commit}" >/dev/null || { echo "codex_review: no commit $base" >&2; exit 1; }

worktree=$(mktemp -d "${TMPDIR:-/tmp}/codex-review-XXXXXX")
rmdir "$worktree"
git worktree add --detach "$worktree" "$commit" >/dev/null

remove() {
  git worktree remove --force "$worktree" 2>/dev/null || echo "codex_review: could not remove the worktree $worktree" >&2
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
