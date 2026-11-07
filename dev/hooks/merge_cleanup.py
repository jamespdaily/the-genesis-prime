"""After a merge: removes the merged branch's worktree and deletes the local branch.

Git decides: `git worktree remove` without --force refuses a dirty, locked or main worktree, and
the branch goes only when the pull request's head holds its tip. Each result is a note.
"""

import subprocess
from pathlib import Path


def clean_up(project: Path, branch: str, head: str) -> list[str]:
    """The notes for removing the worktree of `branch` and deleting it, merged as `head`."""
    def git(*args: str) -> subprocess.CompletedProcess:
        return subprocess.run(["git", "-C", str(project), *args], capture_output=True, text=True, timeout=60)

    def note(done: subprocess.CompletedProcess, what: str) -> str:
        return f"Removed {what}." if done.returncode == 0 else f"Kept {what}: {done.stderr.strip()}"

    notes = []
    for block in git("worktree", "list", "--porcelain").stdout.split("\n\n"):
        lines = block.splitlines()
        if f"branch refs/heads/{branch}" in lines:
            notes.append(note(git("worktree", "remove", lines[0].removeprefix("worktree ")), f"worktree {lines[0][9:]}"))
    tip = git("rev-parse", "--verify", "--quiet", f"refs/heads/{branch}").stdout.strip()
    if tip and git("merge-base", "--is-ancestor", tip, head).returncode == 0:
        notes.append(note(git("branch", "-D", branch), f"local branch {branch}"))
    return notes
