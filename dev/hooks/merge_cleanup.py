"""After a merge: removes the merged branch's worktree when it is clean, and deletes the local branch.

Old worktrees holding branch names made new builders work under other names.
progress_lines calls `clean_up` once it has seen a pull request MERGED; each result is one
line for Claude (the hook's `additionalContext`), and a step that fails is a line, not a crash.

  worktrees(project)          `git worktree list --porcelain`: path, branch, locked, main
  clean_up(...)               the lines for one merged branch

Rules, in the order they are checked for each worktree on the merged branch:
  - the main checkout is never removed;
  - a locked worktree is never touched (no `--force` is ever passed);
  - a worktree that holds the folder the merging command ran in is left, so that command's
    shell keeps its folder;
  - a worktree whose `git status --porcelain` is not empty is left, and the line says how many
    paths changed;
  - a clean one is removed with `git worktree remove`.
The local branch is then deleted with `git branch -D` only when the pull request's head holds
every commit of it (its tip is the head or an ancestor of it), so no unpushed commit is lost;
a branch that is still checked out somewhere is left.
"""

import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Worktree:
    path: str
    branch: str | None
    locked: bool
    main: bool


def _git(folder: str | Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(folder), *args], capture_output=True, text=True, timeout=60,
    )


def worktrees(project: Path) -> list[Worktree]:
    """The worktrees of the repository `project` belongs to; the first is the main checkout."""
    done = _git(project, "worktree", "list", "--porcelain")
    if done.returncode != 0:
        return []
    found: list[Worktree] = []
    for block in done.stdout.strip().split("\n\n"):
        path, branch, locked = None, None, False
        for line in block.splitlines():
            if line.startswith("worktree "):
                path = line[len("worktree "):]
            elif line.startswith("branch refs/heads/"):
                branch = line[len("branch refs/heads/"):]
            elif line == "locked" or line.startswith("locked "):
                locked = True
        if path:
            found.append(Worktree(path, branch, locked, main=not found))
    return found


def _inside(folder: str | None, path: str) -> bool:
    if not folder:
        return False
    try:
        Path(folder).resolve().relative_to(Path(path).resolve())
    except ValueError:
        return False
    return True


def clean_up(
    project: Path, branch: str, head: str, command_folder: str | None, dry_run: bool,
) -> list[str]:
    """What happened to the merged `branch` (its pull request's head `head`): one line for each
    worktree or branch left alone, removed or deleted."""
    notes: list[str] = []
    gone: set[str] = set()
    for tree in worktrees(project):
        if tree.branch != branch:
            continue
        name = Path(tree.path).name
        if tree.main:
            notes.append(f"Merged branch {branch} is checked out in the main checkout: left alone.")
        elif tree.locked:
            notes.append(f"Worktree {name} of merged branch {branch} is locked: left alone.")
        elif _inside(command_folder, tree.path):
            notes.append(f"Worktree {name} of merged branch {branch} holds the command's folder: left in place.")
        else:
            status = _git(tree.path, "status", "--porcelain")
            changed = len(status.stdout.splitlines())
            if status.returncode != 0:
                notes.append(f"Worktree {name} of merged branch {branch}: git status failed, left in place.")
            elif changed:
                notes.append(
                    f"Worktree {name} of merged branch {branch} is dirty ({changed} changed paths): "
                    "left in place; remove it by hand when its changes are dealt with."
                )
            elif dry_run:
                gone.add(tree.path)
                notes.append(f"[dry-run] would remove worktree {name} of merged branch {branch}.")
            else:
                removed = _git(project, "worktree", "remove", tree.path)
                if removed.returncode == 0:
                    gone.add(tree.path)
                    notes.append(f"Removed the clean worktree {name} of merged branch {branch}.")
                else:
                    last = (removed.stderr.strip().splitlines() or ["failed"])[-1]
                    notes.append(f"Worktree {name} of merged branch {branch} not removed: {last}")
    notes += _delete_branch(project, branch, head, gone, dry_run)
    return notes


def _delete_branch(
    project: Path, branch: str, head: str, gone: set[str], dry_run: bool,
) -> list[str]:
    """The line for the local branch: deleted, or why not; none when there is no local branch."""
    tip = _git(project, "rev-parse", "--verify", "--quiet", f"refs/heads/{branch}")
    if tip.returncode != 0:
        return []
    if any(tree.branch == branch and tree.path not in gone for tree in worktrees(project)):
        return [f"Local branch {branch} is still checked out: not deleted."]
    contained = _git(project, "merge-base", "--is-ancestor", tip.stdout.strip(), head)
    if contained.returncode != 0:
        return [f"Local branch {branch} holds commits the pull request's head lacks: not deleted."]
    if dry_run:
        return [f"[dry-run] would delete local branch {branch}."]
    deleted = _git(project, "branch", "-D", branch)
    if deleted.returncode != 0:
        last = (deleted.stderr.strip().splitlines() or ["failed"])[-1]
        return [f"Local branch {branch} not deleted: {last}"]
    return [f"Deleted local branch {branch}."]
