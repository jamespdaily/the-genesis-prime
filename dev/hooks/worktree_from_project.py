"""PreToolUse hook for the Agent tool: refuses a worktree agent started from another repository.

A worktree agent gets the repository of the shell's folder, not of the session's project.
Claude Code passes the hook's JSON on stdin (`cwd`, `tool_input`). When `tool_input.isolation`
is `worktree` and the git toplevel of `cwd` is not `$CLAUDE_PROJECT_DIR`, it prints a line to
stderr and exits 2, which blocks the call and shows Claude that line. Every other case, a
failed git call included, exits 0.
"""
import json
import os
import subprocess
import sys


def toplevel(folder):
    done = subprocess.run(
        ["git", "-C", folder, "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, timeout=10, check=True,
    )
    return os.path.realpath(done.stdout.strip())


def main():
    try:
        event = json.load(sys.stdin)
        project = os.environ["CLAUDE_PROJECT_DIR"]
        if event["tool_input"].get("isolation") != "worktree":
            return 0
        if toplevel(event["cwd"]) == os.path.realpath(project):
            return 0
    except Exception:
        return 0
    print(
        f"A worktree agent gets the repository of the shell's folder: cd {project} first "
        "(twice an agent landed in the-eldan-experiment, 2026-11-05)",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
