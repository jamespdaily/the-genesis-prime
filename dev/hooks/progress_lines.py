"""PostToolUse and PostToolUseFailure hook for the Bash tool: posts a step's progress lines.

For a branch `jimd/<n>-...` it posts, on issue n, one line for each of these, and moves the
card:

  event                                   line                                              card
  a push of the branch                    pushed <sha7> (<k> commits): `<head subject>`     In progress, when To do
  a pull request opened from it           pull request <P> opened on <sha7>
  its checks ended (dev/pr_wait.sh P)     CI passed on <sha7>, pull request <P>, attempt <a>
                                          (or "CI failed on ...")
  its merge (gh pr merge P)               merged: pull request <P> (<merge sha7>)           Done, when P closes n
                                          and, when P closes n, `dev/step_measure.py n` as a
                                          comment headed "Measure (draft for the closing summary)",
                                          then the coverage and ranking comment (merge_measures)
  (at the merge, the CI line of the merged head comes first, when the issue lacks it)
  after a merge, any merge: the branch's worktree and local branch are cleaned up
  (merge_cleanup), and each result is a line shown to Claude (`additionalContext`)

  Bash call ends
    -> events_of(hook json)           which of the four tools ran at a command's start, from the
                                      command and its output; anything else exits 0 at once,
                                      with no gh call
    -> the shell reads GitHub         issue n's comments, the branch head, the pull request, its
                                      checks and run attempt, the card's status
    -> lines_for(event, comments)     the lines not yet posted for that event
    -> the shell posts them           gh issue comment; dev/card.sh status; step_measure.py;
                                      merge_measures (two `gleam run` reads from the main
                                      checkout, 60 s each; skipped with a reason when it is not
                                      on the merged main yet)
    -> after a merge                  merge_cleanup.clean_up: remove a clean worktree, delete the
                                      branch; a dirty or locked worktree is left, and said so

Rules:
  - The hook's stdin JSON has tool_name, tool_input.command, cwd and tool_response (stdout,
    stderr, interrupted), and no exit status (code.claude.com/docs/en/hooks.md). So a push is
    read from git's ref lines, else from the command's refspec and the branch head on GitHub
    (`git push -q` prints no ref line); the result of a wait or a merge is asked of GitHub.
  - PostToolUse runs only after a tool call succeeds; a Bash command that exits non-zero (a
    `dev/pr_wait.sh` whose checks failed) runs PostToolUseFailure, whose input has `error`
    ("Exit code N" and the output) in place of tool_response. Both events run this hook.
  - Exit 2 shows stderr to Claude; exit 0 is silent. Every failure is one stderr line and exit 2.
    The call has already run, so the hook never blocks it. A hook input that is not a Bash call
    with a command string is no event.
  - A tool counts only at the start of a command (the first word, or after `&&`, `||`, `;`, `|`,
    `(`, a newline or a `VAR=x` prefix). Heredoc bodies are cut first, so text that mentions
    `git push` is not a push.
  - A `cd X` before a tool (the last one in the chain) sets the folder it runs in, and `-C X`
    sets it for one git call; `~` is expanded. A path that is a variable gives exit 2.
  - A push or a pull request command counts only for this repository: `-R` or a URL names it,
    or the folder's remote (`git remote get-url`) does.
  - A pull request number that is not a literal (`$P`, none, a URL, a branch) is read from
    `gh pr view` for the folder's branch, or the URL or branch given.
  - A line is posted once: a comment that already starts with the event's key stops it (a push:
    the same sha; a pull request: opened once). The card move and the measures at a merge are
    each keyed on their own state (the card not Done; no comment headed "### Measure (draft" or
    "### Coverage and unhandled ranking (draft"), so a retry finishes what a failure left. A
    "skipped" coverage comment does not stop a later try, but is not posted twice unchanged.
  - The clean-up and the coverage comment run only for a branch `jimd/<n>-...`: a merge whose
    branch has no issue number is not read at all.
  - A merged pull request closes the step only when it closes issue n; a fix branch's merge
    posts its CI and merge lines and nothing else.
  - Settings hooks fire for a subagent's tool calls too, so a builder's push is seen.

It posts as the jamespdaily login, as dev/card.sh does, unless GH_TOKEN is set. An event made
outside a Claude Code session is not seen. A wait started in the background posts nothing when
it ends; the merge posts the CI line instead.

  python3 -I dev/hooks/progress_lines.py            hook JSON on stdin, posts
  python3 -I dev/hooks/progress_lines.py --dry-run  prints "#n: line" instead of posting, and
                                                    runs no card move and no measure
"""

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, replace
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from shell_command import Simple, git_pushes, simple_commands  # noqa: E402
from step_issue import (  # noqa: E402
    PROJECT, REPOSITORY, Failure, GitHub, current_branch, issue_of, last_line,
    names_repository,
)
import merge_cleanup  # noqa: E402
import merge_measures  # noqa: E402

MEASURE_HEADING = "Measure (draft for the closing summary)"
MEASURE_PREFIX = "### Measure (draft"

# A git push ref line: ` * [new branch]  a -> b` or `   1a2b3c4..5d6e7f8  a -> b`.
_REF_LINE = re.compile(
    r"^\s*[ +*]\s+(?:\[new branch\]|(?P<old>[0-9a-f]{7,40})\.\.\.?(?P<new>[0-9a-f]{7,40}))"
    r"\s+\S+ -> (?P<branch>\S+)",
    re.MULTILINE,
)
_PULL_REQUEST_URL = re.compile(r"github\.com/([^/\s]+/[^/\s]+)/pull/(\d+)")
_PUSH_LINE = re.compile(r"^pushed ([0-9a-f]{7}) \(", re.MULTILINE)

_GH_OPTIONS_WITH_VALUE = {
    "-b", "--body", "-F", "--body-file", "-t", "--title", "-A", "--author-email",
    "--match-head-commit", "--subject", "-B", "--base", "-H", "--head", "-a", "--assignee",
    "-l", "--label", "-m", "--milestone", "-p", "--project", "-r", "--reviewer", "--template",
}


@dataclass(frozen=True)
class Push:
    """A push of a remote branch. `branch` is "HEAD" for the current branch of `folder`, which is
    None when the command's folder is a variable."""

    branch: str
    folder: str | None
    remote: str = "origin"
    old: str | None = None
    new: str | None = None
    count: int = 0
    subject: str = ""


@dataclass(frozen=True)
class Pull:
    """A pull request a command names: by `number`, by `selector` (a branch), or by neither (the
    folder's branch). `explicit` is whether `-R` or a URL named this repository."""

    number: int | None = None
    selector: str | None = None
    folder: str | None = None
    explicit: bool = False
    branch: str = ""
    head: str = ""


@dataclass(frozen=True)
class Opened(Pull):
    """A pull request created."""


@dataclass(frozen=True)
class Checked(Pull):
    """A `dev/pr_wait.sh` call, or a merged head's checks. `ended` is whether every check has
    ended."""

    ended: bool = False
    passed: bool = False
    attempt: int = 0


@dataclass(frozen=True)
class Merged(Pull):
    """A `gh pr merge` call. `commit` is the merge commit once the pull request is MERGED."""

    commit: str = ""


def pushed_shas(comments: list[str]) -> list[str]:
    """The sha7 of every push line among an issue's comments, oldest first."""
    return [m for body in comments for m in _PUSH_LINE.findall(body)]


def _pull_named(kind, repo: str | None, selector: str | None, folder: str | None):
    """A pull request event for the number, URL or branch a command gives, or None when `-R` or
    the URL names another repository. A selector that is not a literal is no selector."""
    if repo is not None and repo.lower() != REPOSITORY:
        return None
    explicit = repo is not None
    number, branch = None, None
    if selector:
        url = _PULL_REQUEST_URL.search(selector)
        if selector.isdigit():
            number = int(selector)
        elif url:
            if url[1].lower() != REPOSITORY:
                return None
            number, explicit = int(url[2]), True
        elif not re.search(r"[$`(]", selector):
            branch = selector
    return kind(number=number, selector=branch, folder=folder, explicit=explicit)


def _gh_pull_events(simple: Simple, output: str) -> list:
    """The events of `gh pr create` and `gh pr merge`."""
    words = simple.words
    if len(words) < 3 or words[1] != "pr":
        return []
    verb, repo, positional, i = words[2], None, [], 3
    while i < len(words):
        word = words[i]
        if word in {"-R", "--repo"} and i + 1 < len(words):
            repo, i = words[i + 1], i + 2
        elif word.startswith("--repo="):
            repo, i = word[7:], i + 1
        elif word in _GH_OPTIONS_WITH_VALUE and i + 1 < len(words):
            i += 2
        else:
            if not word.startswith("-"):
                positional.append(word)
            i += 1
    if verb == "create":
        urls = [u for u in _PULL_REQUEST_URL.findall(output) if u[0].lower() == REPOSITORY]
        return [Opened(number=int(urls[-1][1]), explicit=True)] if urls else []
    if verb == "merge":
        event = _pull_named(Merged, repo, positional[0] if positional else None, simple.folder)
        return [event] if event else []
    return []


def events_of(hook) -> list:
    """What a Bash call did that the hook reports: pushes, a pull request created, a wait on a
    pull request's checks, a merge. Only the command and its output are read (a call that
    exited non-zero reaches the hook as PostToolUseFailure, whose `error` holds the output);
    GitHub fills in the rest. Anything that is not a Bash call with a command gives an empty
    list."""
    if not isinstance(hook, dict) or hook.get("tool_name") != "Bash":
        return []
    tool_input, response = hook.get("tool_input"), hook.get("tool_response")
    command = tool_input.get("command") if isinstance(tool_input, dict) else None
    if not isinstance(command, str):
        return []
    parts = [response.get(k) for k in ("stdout", "stderr")] if isinstance(response, dict) else []
    output = "\n".join(p for p in parts + [hook.get("error")] if isinstance(p, str))
    folder = hook.get("cwd") if isinstance(hook.get("cwd"), str) else "."

    others: list = []
    pushes: list[Push] = []
    for simple in simple_commands(command, folder):
        program = os.path.basename(simple.words[0])
        if program == "git":
            pushes += [Push(t.branch, t.folder, t.remote) for t in git_pushes(simple)]
        elif program == "gh":
            others += _gh_pull_events(simple, output)
        elif program == "pr_wait.sh":
            event = _pull_named(Checked, None, simple.words[1] if len(simple.words) > 1 else None,
                                simple.folder)
            others += [event] if event else []
    refs = list(_REF_LINE.finditer(output))
    if pushes and refs:
        pushes = [Push(m["branch"], pushes[0].folder, pushes[0].remote, m["old"], m["new"])
                  for m in refs]
    return pushes + others


def _count(n: int, word: str) -> str:
    return f"{n} {word}{'' if n == 1 else 's'}"


def lines_for(event, comments: list[str]) -> list[str]:
    """The lines to post for a resolved event: none when a comment already starts with the
    event's key (a push: the same sha; a pull request: opened once), or when the event did not
    happen (checks still running, no merge). A subject goes in backticks, so an `@name` in it
    notifies no one."""
    match event:
        case Push(new=new, count=count, subject=subject) if new:
            key = f"pushed {new[:7]} ("
            line = f"{key}{_count(count, 'commit')}): `{subject.replace('`', chr(39))}`"
        case Opened(number=number, head=head) if head:
            key = f"pull request {number} opened on "
            line = f"{key}{head[:7]}"
        case Checked(number=number, head=head, ended=True, passed=passed, attempt=attempt):
            outcome = "passed" if passed else "failed"
            key = line = f"CI {outcome} on {head[:7]}, pull request {number}, attempt {attempt}"
        case Merged(number=number, commit=commit) if commit:
            key = f"merged: pull request {number} ("
            line = f"{key}{commit[:7]})"
        case _:
            return []
    posted = any(body.strip().startswith(key) for body in comments)
    return [] if posted else [line]


def ahead_of(github: GitHub, event: Push, comments: list[str], full: str) -> int:
    """The commits this push sent: those past the ref line's old sha; else past the newest
    pushed sha on the issue that the new head holds (a step's other branches have pushes on the
    same issue); else past the default branch."""
    if event.old:
        bases = [event.old]
    else:
        bases = list(reversed(pushed_shas(comments))) + ["main"]
    for base in bases:
        try:
            ahead, behind = github.api(
                f"compare/{base}...{full}", r'"\(.ahead_by) \(.behind_by)"'
            ).split()
        except Failure:
            continue
        if base in (event.old, "main") or behind == "0":
            return int(ahead)
    raise Failure(f"no commit count for {full[:7]}")


def pull_of(github: GitHub, event: Pull) -> dict | None:
    """What GitHub says of the pull request an event names, or None when the event does not
    name this repository."""
    named = event.number is not None or event.selector
    if not (named and event.explicit) and not names_repository(event.folder, "origin"):
        return None
    target = []
    if event.number is not None:
        target = [str(event.number)]
    elif event.selector:
        target = [event.selector]
    return github.pull_request(target, event.folder)


def checked_of(github: GitHub, pull: dict) -> Checked:
    """A pull request's checks now: whether every check has ended and how, and the run attempt."""
    checks = github.checks(pull["number"])
    buckets = {c["bucket"] for c in checks}
    ended = bool(checks) and "pending" not in buckets
    return Checked(
        number=pull["number"], branch=pull["headRefName"], head=pull["headRefOid"], ended=ended,
        passed=ended and not buckets & {"fail", "cancel"},
        attempt=github.run_attempt([c.get("link", "") for c in checks]) if ended else 0,
    )


def post(github: GitHub, issue: int, body: str, dry_run: bool) -> None:
    if dry_run:
        print(f"#{issue}: {body}")
        return
    github.run("issue", "comment", str(issue), "-R", REPOSITORY, "--body-file", "-", input=body)


def move_card(github: GitHub, issue: int, status: str, when: str | None, dry_run: bool) -> None:
    """Moves the card to `status` when it is at `when` (any status but `status` when None)."""
    current = github.card_status(issue)
    if current == status or (when is not None and current != when):
        return
    if dry_run:
        print(f"#{issue}: [dry-run] card {current or 'none'} -> {status}")
        return
    done = subprocess.run(
        [str(PROJECT / "dev" / "card.sh"), "status", str(issue), status],
        capture_output=True, text=True, env=github.environment, timeout=120,
    )
    if done.returncode != 0:
        raise Failure(f"card #{issue} to {status}: {last_line(done.stderr, f'exit {done.returncode}')}")


def post_measure(github: GitHub, issue: int, comments: list[str], dry_run: bool) -> None:
    """Posts `dev/step_measure.py n` as a comment, unless the issue has one."""
    if any(body.strip().startswith(MEASURE_PREFIX) for body in comments):
        return
    if dry_run:
        print(f"#{issue}: [dry-run] would post the measure (python3 -I dev/step_measure.py {issue})")
        return
    done = subprocess.run(
        [sys.executable, "-I", str(PROJECT / "dev" / "step_measure.py"), str(issue)],
        capture_output=True, text=True, cwd=PROJECT, timeout=300,
    )
    if done.returncode != 0 or not done.stdout.strip():
        raise Failure(f"measure of #{issue}: {last_line(done.stderr, f'exit {done.returncode}')}")
    post(github, issue, f"### {MEASURE_HEADING}\n\n{done.stdout.strip()}", dry_run)


def report_push(event: Push, github: GitHub, dry_run: bool) -> None:
    """A push: its line, then the card to In progress when it is To do. A branch GitHub lacks
    (a push that failed) posts nothing."""
    if not names_repository(event.folder, event.remote):
        return
    branch = current_branch(event.branch, event.folder)
    issue = issue_of(branch)
    if issue is None:
        return
    comments = github.comments(issue)
    head = github.head(event.new or branch)
    if head is None:
        return
    full, subject = head
    event = replace(event, new=full, subject=subject, count=ahead_of(github, event, comments, full))
    for line in lines_for(event, comments):
        post(github, issue, line, dry_run)
    move_card(github, issue, "In progress", "To do", dry_run)


def post_merge_measures(
    github: GitHub, issue: int, commit: str, comments: list[str], dry_run: bool,
) -> None:
    """Posts the coverage counts and the unhandled ranking's top as one comment, run from the
    main checkout once it holds the merge commit (merge_measures). A comment that already has
    the measures stops it; a skipped one is not posted twice with the same reason."""
    if any(body.strip().startswith(merge_measures.PREFIX) for body in comments):
        return
    main, reason = merge_measures.main_checkout_on(PROJECT, commit)
    body = merge_measures.comment(main, commit, reason)
    if body.startswith(merge_measures.SKIPPED_PREFIX) and any(c.strip() == body for c in comments):
        return
    post(github, issue, body, dry_run)


def report_pull(event: Pull, github: GitHub, dry_run: bool, notes: list[str]) -> None:
    """A pull request opened, its checks waited on, or its merge. `notes` collects what Claude
    is told besides the posted lines (the cleanup after a merge)."""
    pull = pull_of(github, event)
    if pull is None:
        return
    issue = issue_of(pull["headRefName"])
    if issue is None:
        return
    if isinstance(event, Opened):
        event = replace(event, number=pull["number"], head=pull["headRefOid"])
        for line in lines_for(event, github.comments(issue)):
            post(github, issue, line, dry_run)
    elif isinstance(event, Checked):
        checked = checked_of(github, pull)
        if lines_for(checked, []):
            for line in lines_for(checked, github.comments(issue)):
                post(github, issue, line, dry_run)
    else:
        report_merge(github, pull, issue, dry_run, event.folder, notes)


def report_merge(
    github: GitHub, pull: dict, issue: int, dry_run: bool, folder: str | None, notes: list[str],
) -> None:
    """A merged pull request: the clean-up of its branch's worktree (on any merge, and first, so
    the slow parts below cannot cost it), the CI line of its head, the merge line, and, when it
    closes the issue, the card to Done, the measure and the coverage and ranking comment. Each
    part is attempted whatever the others do, and the failures are raised together."""
    if pull["state"] != "MERGED":
        return
    number = pull["number"]
    commit = (pull.get("mergeCommit") or {}).get("oid")
    if not commit:
        raise Failure(f"pull request {number} is MERGED and GitHub gives no merge commit")
    comments = github.comments(issue)
    closes = issue in [c["number"] for c in pull.get("closingIssuesReferences") or []]
    problems: list[str] = []

    def attempt(step) -> None:
        try:
            step()
        except Failure as problem:
            problems.append(str(problem))

    def lines() -> None:
        checked = checked_of(github, pull)
        merged = Merged(number=number, commit=commit)
        for event in (checked, merged):
            for line in lines_for(event, comments):
                post(github, issue, line, dry_run)

    # The clean-up comes first: the measures below may run long, and the hook's own timeout
    # ends the process.
    try:
        notes += merge_cleanup.clean_up(
            PROJECT, pull["headRefName"], pull["headRefOid"], folder, dry_run,
        )
    except (OSError, subprocess.SubprocessError) as problem:
        problems.append(f"clean-up of {pull['headRefName']}: {type(problem).__name__}: {problem}")
    attempt(lines)
    if closes:
        attempt(lambda: move_card(github, issue, "Done", None, dry_run))
        attempt(lambda: post_measure(github, issue, comments, dry_run))
        attempt(lambda: post_merge_measures(github, issue, commit, comments, dry_run))
    if problems:
        raise Failure("; ".join(problems))


def report(event, github: GitHub, dry_run: bool, notes: list[str]) -> None:
    """Posts what one event owes."""
    if isinstance(event, Push):
        report_push(event, github, dry_run)
    else:
        report_pull(event, github, dry_run, notes)


def main(argv: list[str] | None = None, stdin=None) -> int:
    parser = argparse.ArgumentParser(description="Posts a step's progress lines.")
    parser.add_argument("--dry-run", action="store_true")
    options = parser.parse_args(argv)
    try:
        hook = json.load(stdin or sys.stdin)
    except json.JSONDecodeError as problem:
        print(f"progress_lines: the hook's input is not JSON: {problem}", file=sys.stderr)
        return 2
    events = events_of(hook)
    if not events:
        return 0
    problems = []
    notes: list[str] = []
    github = GitHub()
    for event in events:
        try:
            report(event, github, options.dry_run, notes)
        except Failure as problem:
            problems.append(str(problem))
        except (KeyError, ValueError, OSError, subprocess.SubprocessError) as problem:
            problems.append(f"{type(problem).__name__}: {problem}")
    if problems:
        print("progress_lines: " + "; ".join(problems + notes).replace("\n", " "), file=sys.stderr)
        return 2
    if notes and options.dry_run:
        print("\n".join(notes))
    elif notes:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": hook.get("hook_event_name") or "PostToolUse",
            "additionalContext": " ".join(notes),
        }}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
