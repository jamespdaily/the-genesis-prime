#!/usr/bin/env bash
# Waits for pull request N's checks to finish: see dev/pr_wait.py.
#
#   dev/pr_wait.sh N
exec python3.13 -I "$(dirname "${BASH_SOURCE[0]}")/pr_wait.py" "$@"
