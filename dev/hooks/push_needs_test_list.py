"""PreToolUse hook (Bash): refuses a push of a step branch `jimd/<n>-...` before issue n has a test list.

Each `git push` of the command is read (shell_command.git_pushes). A branch of another name, a
push of another repository and a gh failure pass.
"""

import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from shell_command import git_pushes, simple_commands  # noqa: E402
from step_issue import GitHub, current_branch, issue_of, names_repository  # noqa: E402


def main() -> int:
    try:
        event, github = json.load(sys.stdin), GitHub(timeout=10)
        for simple in simple_commands(event["tool_input"]["command"], event["cwd"]):
            for push in git_pushes(simple) if os.path.basename(simple.words[0]) == "git" else []:
                branch = current_branch(push.branch, push.folder)
                issue = issue_of(branch)
                if issue and names_repository(push.folder, push.remote) and not any(
                    "test list" in text.lower() for text in github.texts(issue)
                ):
                    print(f"Issue {issue} has no posted test list (\"test list\" in its body or a comment), "
                          f"so {branch} is not pushed.", file=sys.stderr)
                    return 2
    except Exception:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
