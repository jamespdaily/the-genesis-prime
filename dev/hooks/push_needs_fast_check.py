"""PreToolUse hook (Bash): refuses a push of a step branch `jimd/<n>-...` whose HEAD is not the commit
`./check fast` or the full check last passed on.

./check writes that commit to `check-passed-commit` in the worktree's own git directory after a
passing run on a clean tree (see ./check). Each `git push` of the command is read
(shell_command.git_pushes). A branch of another name, a push of another repository and any error in
this hook pass.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from shell_command import git_pushes, simple_commands  # noqa: E402
from step_issue import current_branch, issue_of, names_repository  # noqa: E402


def git_output(folder: str, *arguments: str) -> str:
    """What `git -C folder ...` prints; an empty string when git fails."""
    done = subprocess.run(["git", "-C", folder, *arguments], capture_output=True, text=True, timeout=10)
    return done.stdout.strip() if done.returncode == 0 else ""


def passed_commit(folder: str) -> str:
    """The commit the folder's worktree last passed the check on; empty when none is recorded."""
    git_directory = git_output(folder, "rev-parse", "--absolute-git-dir")
    record = Path(git_directory) / "check-passed-commit"
    return record.read_text().strip() if git_directory and record.exists() else ""


def main() -> int:
    try:
        event = json.load(sys.stdin)
        for simple in simple_commands(event["tool_input"]["command"], event["cwd"]):
            for push in git_pushes(simple) if os.path.basename(simple.words[0]) == "git" else []:
                branch = current_branch(push.branch, push.folder)
                if issue_of(branch) and names_repository(push.folder, push.remote):
                    head = git_output(push.folder, "rev-parse", "HEAD")
                    if head and head != passed_commit(push.folder):
                        print(f"HEAD {head[:9]} of {branch} is not a commit ./check fast passed on, so it is not "
                              f"pushed: run ./check fast (on a clean tree, with everything committed), then push.",
                              file=sys.stderr)
                        return 2
    except Exception:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
