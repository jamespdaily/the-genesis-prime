#!/usr/bin/env bash
# Prints the session's state block: git, pull requests, the play server, the watchers and the
# newest "Where it stands" comment of the milestone parents (details in session_state.py).
# The SessionStart hook in .claude/settings.json runs it. It always exits 0.
python3 -I "$(dirname "$0")/session_state.py" || echo "session state: unreachable"
exit 0
