"""At a step's merge: the coverage measure's counts and the top of the unhandled-message ranking.

progress_lines posts, beside the merge line and the step measure, one comment so the
coordinator writes only notes:

  ### Coverage and unhandled ranking (draft for the closing summary)

  the coverage measure's summary table and each engine's counts line, then the five messages
  the recorded sittings send most that no rule handles

  merged main's commit
    -> main_checkout_on(commit)     the main checkout must be on branch main and hold the commit
    -> `gleam run -m genesis_prime/coverage`                                  (stdout)
    -> `gleam run -m genesis_prime/unhandled_ranking -- <each sitting folder>` (stdout)
    -> comment(...)                 the lines kept, or a one-line reason for each part skipped

Both are reads, run from the main checkout, each stopped after 60 s. A part that fails, takes
over 60 s or cannot start is skipped with a one-line reason in the comment, and the other part
is still posted. When the main checkout is not yet on the merged main, both are skipped with
that reason. A comment whose heading says "skipped" does not stop a later try.
"""

import re
import subprocess
from pathlib import Path

from merge_cleanup import worktrees

HEADING = "Coverage and unhandled ranking (draft for the closing summary)"
PREFIX = "### Coverage and unhandled ranking (draft"
SKIPPED_PREFIX = "### Coverage and unhandled ranking (skipped"
SECONDS = 60
TOP = 5
SITTINGS = Path.home() / ".genesis-prime" / "sittings"

_COUNTS_LINE = re.compile(r"^\d+ rows over \d+ types")


def main_checkout_on(project: Path, commit: str) -> tuple[Path | None, str | None]:
    """The main checkout and None when it is on branch main and holds `commit`; else None and
    the reason."""
    trees = worktrees(project)
    if not trees:
        return None, "no main checkout found"
    main = Path(trees[0].path)
    branch = subprocess.run(
        ["git", "-C", str(main), "symbolic-ref", "--short", "HEAD"],
        capture_output=True, text=True, timeout=10,
    ).stdout.strip()
    if branch != "main":
        return None, f"the main checkout is on {branch or 'no branch'}, not main"
    held = subprocess.run(
        ["git", "-C", str(main), "merge-base", "--is-ancestor", commit, "HEAD"],
        capture_output=True, text=True, timeout=10,
    )
    if held.returncode != 0:
        return None, f"the main checkout does not hold the merge commit {commit[:7]} yet"
    return main, None


def _stdout(main: Path, *arguments: str) -> tuple[str | None, str | None]:
    """A `gleam run` read from the main checkout: its stdout, or None and a one-line reason."""
    try:
        done = subprocess.run(
            ["gleam", "run", *arguments], cwd=main, capture_output=True, text=True, timeout=SECONDS,
        )
    except subprocess.TimeoutExpired:
        return None, f"took over {SECONDS} s"
    except OSError as problem:
        return None, f"could not start: {problem}"
    if done.returncode != 0:
        lines = [line for line in done.stderr.strip().splitlines() if line.strip()]
        shown = next((line for line in lines if "error" in line.lower()), lines[-1] if lines else "no output")
        return None, f"failed with exit {done.returncode}: {shown.strip()}"
    return done.stdout, None


def coverage_summary(output: str) -> str:
    """The summary table at the head of the coverage measure's output, and each engine's counts
    line (`N rows over M types; ...`)."""
    table: list[str] = []
    for line in output.splitlines():
        if line.startswith("|"):
            table.append(line)
        elif table:
            break
    counts = [line for line in output.splitlines() if _COUNTS_LINE.match(line)]
    return "\n".join(table + [""] * bool(counts) + counts)


def ranking_top(output: str, count: int = TOP) -> str:
    """The first `count` lines of the ranking (most sent first), as a code block."""
    lines = [line.rstrip() for line in output.splitlines() if line.strip()]
    return "```\n" + "\n".join(lines[:count]) + "\n```"


def _coverage_section(main: Path) -> tuple[str | None, str]:
    """The coverage part's text, or None and why it is skipped."""
    output, why = _stdout(main, "-m", "genesis_prime/coverage")
    if output is None:
        return None, why or ""
    summary = coverage_summary(output)
    if not summary:
        return None, "no summary in its output"
    return "Coverage measure (`gleam run -m genesis_prime/coverage`):\n\n" + summary, ""


def _ranking_section(main: Path) -> tuple[str | None, str]:
    """The ranking part's text, or None and why it is skipped."""
    sittings = sorted(str(p) for p in SITTINGS.glob("*") if p.is_dir())
    if not sittings:
        return None, f"no sitting folders in {SITTINGS}"
    output, why = _stdout(main, "-m", "genesis_prime/unhandled_ranking", "--", *sittings)
    if output is None:
        return None, why or ""
    if not output.strip():
        return None, "no messages in its output"
    return (
        f"Top {TOP} unhandled messages of the {len(sittings)} recorded sittings, most sent first "
        "(count, opcode, system, name):\n\n" + ranking_top(output),
        "",
    )


def comment(main: Path | None, commit: str, reason: str | None) -> str:
    """The comment's text. `main` is None, with `reason`, when the main checkout cannot run the
    reads. A part that is skipped says why in the text; when both are, the heading says skipped."""
    if main is None:
        return f"### {SKIPPED_PREFIX[4:]}: {reason})"
    shown, skipped = [], []
    for name, section in (("Coverage measure", _coverage_section), ("Unhandled ranking", _ranking_section)):
        text, why = section(main)
        if text is None:
            skipped.append(f"{name} skipped: {why}.")
        else:
            shown.append(text)
    heading = HEADING if shown else f"{SKIPPED_PREFIX[4:]}: both parts)"
    return f"### {heading}\n\nAt main {commit[:7]}.\n\n" + "\n\n".join(shown + skipped)
