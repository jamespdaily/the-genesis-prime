"""PreToolUse hook for the Bash tool: refuses a push of a step branch before its test list is posted.

Branches were pushed before their step's test list stood on the issue, and a branch with no
issue number cannot be attributed by dev/step_measure.py. Claude Code passes the
hook's JSON on stdin (`tool_name`, `tool_input.command`, `cwd`). For each `git push` of this
repository in the command (shell_command.git_pushes; `HEAD` is read from the folder's branch):

  jimd/<n>-... , issue n's body and comments hold "test list" (any case)   allowed
  jimd/<n>-... , they do not                                               refused: stderr line, exit 2
  any other branch name                                                    allowed, with a warning
  main, or a name that is a local tag and no local branch                  allowed, with no warning
  gh failed or ran over 10 s                                               allowed, with a warning

The warning goes to Claude as JSON `hookSpecificOutput.additionalContext` on stdout with exit 0.
A push that deletes (`-d`), is a dry run, or names no branch (`--all`, `--mirror`, `--tags`) is
not read; neither is a push of another repository, or from a folder that is a variable.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from shell_command import git_pushes, simple_commands  # noqa: E402
from step_issue import Failure, GitHub, current_branch, issue_of, names_repository  # noqa: E402

GH_SECONDS = 10
UNNUMBERED = {"main"}


def is_tag(name: str, folder: str) -> bool:
    """Whether `name` is a local tag of the git folder and not a local branch."""
    def exists(ref: str) -> bool:
        return subprocess.run(
            ["git", "-C", folder, "show-ref", "--verify", "--quiet", ref], capture_output=True, timeout=10,
        ).returncode == 0
    return exists(f"refs/tags/{name}") and not exists(f"refs/heads/{name}")


def check(command: str, folder: str | None, github: GitHub) -> tuple[list[str], list[str]]:
    """The refusals and the warnings for the pushes of a command."""
    refusals: list[str] = []
    warnings: list[str] = []
    seen: set[str] = set()
    for simple in simple_commands(command, folder):
        if os.path.basename(simple.words[0]) != "git":
            continue
        for push in git_pushes(simple):
            try:
                if not names_repository(push.folder, push.remote):
                    continue
                branch = current_branch(push.branch, push.folder)
                tag = bool(branch) and is_tag(branch, push.folder)
            except (Failure, OSError, subprocess.SubprocessError):
                continue
            if not branch or branch in seen or branch in UNNUMBERED or tag:
                continue
            seen.add(branch)
            issue = issue_of(branch)
            if issue is None:
                warnings.append(
                    f"Branch {branch} has no issue number (jimd/<issue>-<topic>), so "
                    "dev/step_measure.py cannot attribute its work to a step."
                )
                continue
            try:
                texts = github.texts(issue)
            except Failure as problem:
                warnings.append(
                    f"Could not check that issue {issue} holds a test list before pushing {branch}: {problem}"
                )
                continue
            if not any("test list" in text.lower() for text in texts):
                refusals.append(
                    f"Issue {issue} has no posted test list yet (its body or a comment must hold "
                    f"\"test list\"), so {branch} is not pushed: post the list on the issue first."
                )
    return refusals, warnings


def main() -> int:
    try:
        event = json.load(sys.stdin)
        if event.get("tool_name") != "Bash":
            return 0
        folder = event.get("cwd") if isinstance(event.get("cwd"), str) else None
        refusals, warnings = check(event["tool_input"]["command"], folder, GitHub(timeout=GH_SECONDS))
    except Exception:
        return 0
    if refusals:
        print(" ".join(refusals), file=sys.stderr)
        return 2
    if warnings:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "additionalContext": " ".join(warnings),
        }}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
