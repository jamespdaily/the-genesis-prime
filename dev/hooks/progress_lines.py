"""PostToolUse and PostToolUseFailure hook for the Bash tool: posts a step's progress lines.

For a branch `jimd/<n>-...` it posts, on issue n, one line for each of these, and moves the
card:

  event                                   line                                              card
  a push of the branch                    pushed <sha7> (<k> commits): <head subject>       In progress, when To do
  a pull request opened from it           pull request <P> opened on <sha7>
  its checks ended (dev/pr_wait.sh P)     CI passed on <sha7>, pull request <P>, attempt <a>
                                          (or "CI failed on ...")
  its merge (gh pr merge P)               merged: pull request <P> (<merge sha7>)           Done
                                          and `dev/step_measure.py n` as a second comment
                                          headed "Measure (draft for the closing summary)"

  Bash call ends
    -> events_of(hook json)           which of the four tools ran, from the command and its output;
                                      anything else exits 0 at once, with no gh call
    -> the shell reads GitHub         issue n's comments, the branch head, the pull request, its
                                      checks and run attempt
    -> lines_for(event, comments)     the lines not yet posted for that event
    -> the shell posts them           gh issue comment; dev/card.sh status; step_measure.py

Rules, each from the docs at code.claude.com/docs/en/hooks.md:
  - The hook's stdin JSON has tool_name, tool_input.command, cwd and tool_response (stdout,
    stderr, interrupted), and no exit status. So a push is read from git's ref lines, else from
    the command's refspec and the branch head on GitHub (`git push -q` prints no ref line), and
    the result of a wait or a merge is asked of GitHub, never guessed from the output.
  - PostToolUse runs only after a tool call succeeds; a Bash command that exits non-zero (a
    `dev/pr_wait.sh` whose checks failed) runs PostToolUseFailure, whose input has `error`
    ("Exit code N" and the output) in place of tool_response. Both events run this hook.
  - Exit 2 shows stderr to Claude; exit 0 is silent. Every failure is one stderr line and exit 2.
    The call has already run, so the hook never blocks it.
  - A line is posted once: a comment that already starts with the event's line key (the same
    sha for a push) stops it.
  - Settings hooks fire for a subagent's tool calls too, so a builder's push is seen.

It posts as the jamespdaily login, as dev/card.sh does, unless GH_TOKEN is set. An event made
outside a Claude Code session is not seen. A wait started in the background posts nothing,
because its checks are still running when the call returns.

  python3 -I dev/hooks/progress_lines.py            hook JSON on stdin, posts
  python3 -I dev/hooks/progress_lines.py --dry-run  prints "#n: line" instead of posting, and
                                                    runs no card move and no measure
"""

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
from dataclasses import dataclass, replace
from pathlib import Path

REPOSITORY = "jamespdaily/the-genesis-prime"
PROJECT = Path(__file__).resolve().parents[2]
MEASURE_HEADING = "Measure (draft for the closing summary)"
RESULT_WORDS = re.compile(r"\berror:|\bfatal:|\[rejected\]|\[remote rejected\]")

# A git push ref line: ` * [new branch]  a -> b` or `   1a2b3c4..5d6e7f8  a -> b`.
_REF_LINE = re.compile(
    r"^\s*[ +*]\s+(?:\[new branch\]|(?P<old>[0-9a-f]{7,40})\.\.\.?(?P<new>[0-9a-f]{7,40}))"
    r"\s+\S+ -> (?P<branch>\S+)",
    re.MULTILINE,
)
_PULL_REQUEST_URL = re.compile(r"github\.com/[^/\s]+/[^/\s]+/pull/(\d+)")
_STEP_BRANCH = re.compile(r"jimd/(\d+)-")
_PUSH_LINE = re.compile(r"^pushed ([0-9a-f]{7}) \(", re.MULTILINE)
_RUN_ID = re.compile(r"/actions/runs/(\d+)")


class Failure(Exception):
    """A step the hook could not finish, as one line for the agent that ran the command."""


@dataclass(frozen=True)
class Push:
    """A push of a remote branch. `branch` is "HEAD" for the current branch of `folder`."""

    branch: str
    folder: str
    old: str | None = None
    new: str | None = None
    count: int = 0
    subject: str = ""


@dataclass(frozen=True)
class Opened:
    """A pull request created."""

    number: int
    branch: str = ""
    head: str = ""


@dataclass(frozen=True)
class Checked:
    """A `dev/pr_wait.sh` call on a pull request. `ended` is whether every check has ended."""

    number: int
    branch: str = ""
    head: str = ""
    ended: bool = False
    passed: bool = False
    attempt: int = 0


@dataclass(frozen=True)
class Merged:
    """A `gh pr merge` call on a pull request. `commit` is empty unless it is MERGED."""

    number: int
    branch: str = ""
    commit: str = ""


def issue_of(branch: str) -> int | None:
    """The issue number n of a branch `jimd/<n>-...`."""
    found = _STEP_BRANCH.match(branch)
    return int(found.group(1)) if found else None


def pushed_shas(comments: list[str]) -> list[str]:
    """The sha7 of every push line among an issue's comments, oldest first."""
    return [m for body in comments for m in _PUSH_LINE.findall(body)]


def _tokens(command: str) -> list[str]:
    """The words of a shell command, with `&&`, `||`, `;` and `|` as words of their own."""
    lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    lexer.commenters = ""
    try:
        words = list(lexer)
    except ValueError:
        words = command.split()
    # `2>&1` comes out as "2", ">&", "1": the file descriptor is not an argument.
    return [
        w for i, w in enumerate(words)
        if not (w in {"0", "1", "2"} and i + 1 < len(words) and words[i + 1][:1] in "<>")
    ]


def _is_operator(word: str) -> bool:
    """Whether a word ends a command's arguments: a separator or a redirection."""
    return all(c in "();<>|&" for c in word) or re.match(r"\d*[<>]", word) is not None


_GIT_OPTIONS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
_PUSH_OPTIONS_WITH_VALUE = {"-o", "--push-option", "--repo", "--receive-pack", "--exec"}


def _git_pushes(words: list[str], folder: str) -> list[Push]:
    """The pushes `git [options] push [options] remote refspec...` in a command's words."""
    pushes = []
    for start, word in enumerate(words):
        if word != "git":
            continue
        i, where = start + 1, folder
        while i < len(words) and words[i].startswith("-"):
            if words[i] == "-C" and i + 1 < len(words):
                where = os.path.join(where, words[i + 1])
            i += 2 if words[i] in _GIT_OPTIONS_WITH_VALUE else 1
        if i >= len(words) or words[i] != "push":
            continue
        rest = []
        i += 1
        skip = False
        for word in words[i:]:
            if _is_operator(word):
                break
            if skip:
                skip = False
            elif word in _PUSH_OPTIONS_WITH_VALUE:
                skip = True
            else:
                rest.append(word)
        options = {w for w in rest if w.startswith("-")}
        if options & {"-d", "--delete", "-n", "--dry-run", "--all", "--mirror", "--tags"}:
            continue
        positional = [w for w in rest if not w.startswith("-")]
        refspecs = positional[1:] or ["HEAD"]
        for refspec in refspecs:
            destination = refspec.lstrip("+").split(":")[-1]
            if not destination:
                continue
            destination = destination.removeprefix("refs/heads/")
            pushes.append(Push(destination, where))
    return pushes


def events_of(hook: dict) -> list:
    """What a Bash call did that the hook reports: pushes, a pull request created, a wait on a
    pull request's checks, a merge. Only the command and its output are read (a call that
    exited non-zero reaches the hook as PostToolUseFailure, whose `error` holds the output);
    GitHub fills in the rest. Any other call gives an empty list."""
    if hook.get("tool_name") != "Bash":
        return []
    command = (hook.get("tool_input") or {}).get("command") or ""
    response = hook.get("tool_response") or {}
    output = "\n".join(
        str(response.get(key) or "") for key in ("stdout", "stderr")
    ) + "\n" + str(hook.get("error") or "")
    folder = hook.get("cwd") or "."
    words = _tokens(command)
    events: list = []

    if "push" in words:
        refs = list(_REF_LINE.finditer(output))
        if refs:
            events += [Push(m["branch"], folder, m["old"], m["new"]) for m in refs]
        elif "Everything up-to-date" not in output and not RESULT_WORDS.search(output):
            events += _git_pushes(words, folder)

    if "gh" in words:
        for i, word in enumerate(words[:-2]):
            if word == "gh" and words[i + 1] == "pr":
                verb = words[i + 2]
                rest = []
                for w in words[i + 3 :]:
                    if _is_operator(w):
                        break
                    rest.append(w)
                if verb == "create":
                    events += [Opened(int(n)) for n in _PULL_REQUEST_URL.findall(output)[-1:]]
                if verb == "merge":
                    numbers = [w for w in rest if w.isdigit()]
                    events += [Merged(int(n)) for n in numbers[:1]]

    for i, word in enumerate(words[:-1]):
        if os.path.basename(word) == "pr_wait.sh" and words[i + 1].isdigit():
            events.append(Checked(int(words[i + 1])))
    return events


def _count(n: int, word: str) -> str:
    return f"{n} {word}{'' if n == 1 else 's'}"


def lines_for(event, comments: list[str]) -> list[str]:
    """The lines to post for a resolved event: none when a comment already starts with the
    event's key (a push: the same sha), or when the event did not happen (checks still
    running, no merge)."""
    match event:
        case Push(new=new, count=count, subject=subject) if new:
            key = f"pushed {new[:7]} ("
            line = f"pushed {new[:7]} ({_count(count, 'commit')}): {subject}"
        case Opened(number=number, head=head) if head:
            key = line = f"pull request {number} opened on {head[:7]}"
        case Checked(number=number, head=head, ended=True, passed=passed, attempt=attempt):
            outcome = "passed" if passed else "failed"
            key = line = f"CI {outcome} on {head[:7]}, pull request {number}, attempt {attempt}"
        case Merged(number=number, commit=commit) if commit:
            key = f"merged: pull request {number} ("
            line = f"merged: pull request {number} ({commit[:7]})"
        case _:
            return []
    posted = any(body.strip().startswith(key) for body in comments)
    return [] if posted else [line]


class GitHub:
    """The calls the hook makes, as the jamespdaily login, to this repository."""

    def __init__(self) -> None:
        self._environment: dict | None = None

    @property
    def environment(self) -> dict:
        """The process's environment with GH_TOKEN, read from gh's jamespdaily login on first use."""
        if self._environment is None:
            environment = dict(os.environ)
            if not environment.get("GH_TOKEN"):
                done = subprocess.run(
                    ["gh", "auth", "token", "--user", "jamespdaily"],
                    capture_output=True, text=True, timeout=30,
                )
                if done.returncode != 0 or not done.stdout.strip():
                    raise Failure("no jamespdaily login in gh")
                environment["GH_TOKEN"] = done.stdout.strip()
            self._environment = environment
        return self._environment

    def run(self, *args: str, input: str | None = None, tolerate: bool = False) -> str:
        """gh's stdout. A failure raises with gh's last stderr line, unless `tolerate`."""
        try:
            done = subprocess.run(
                ["gh", *args], capture_output=True, text=True, input=input,
                env=self.environment, timeout=120,
            )
        except (OSError, subprocess.TimeoutExpired) as problem:
            raise Failure(f"gh {args[0]}: {problem}") from problem
        if done.returncode != 0 and not tolerate:
            last = (done.stderr.strip().splitlines() or [f"exit {done.returncode}"])[-1]
            raise Failure(f"gh {' '.join(args[:2])}: {last}")
        return done.stdout

    def api(self, path: str, jq: str) -> str:
        return self.run("api", f"repos/{REPOSITORY}/{path}", "--jq", jq).strip()

    def comments(self, issue: int) -> list[str]:
        out = self.run(
            "issue", "view", str(issue), "-R", REPOSITORY, "--json", "comments",
            "--jq", "[.comments[].body]",
        )
        return json.loads(out)

    def pull_request(self, number: int) -> dict:
        out = self.run(
            "pr", "view", str(number), "-R", REPOSITORY, "--json",
            "state,headRefName,headRefOid,mergeCommit",
        )
        return json.loads(out)

    def checks(self, number: int) -> list[dict]:
        out = self.run(
            "pr", "checks", str(number), "-R", REPOSITORY, "--json", "bucket,link", tolerate=True
        )
        try:
            return json.loads(out)
        except json.JSONDecodeError:
            return []

    def run_attempt(self, links: list[str]) -> int:
        runs = {m.group(1) for link in links if (m := _RUN_ID.search(link))}
        return max((int(self.api(f"actions/runs/{r}", ".run_attempt")) for r in runs), default=1)

    def card_status(self, issue: int) -> str:
        query = (
            f'query{{repository(owner:"jamespdaily",name:"the-genesis-prime"){{issue(number:{issue})'
            "{projectItems(first:10){nodes{project{number} fieldValueByName(name:\"Status\")"
            "{... on ProjectV2ItemFieldSingleSelectValue{name}}}}}}}"
        )
        return self.run(
            "api", "graphql", "-f", f"query={query}", "--jq",
            '[.data.repository.issue.projectItems.nodes[] | select(.project.number == 2)'
            " | .fieldValueByName.name][0] // empty",
        ).strip()


def current_branch(push: Push) -> str:
    """The pushed branch's name: "HEAD" is the current branch of the push's folder."""
    if push.branch != "HEAD":
        return push.branch
    done = subprocess.run(
        ["git", "-C", push.folder, "symbolic-ref", "--short", "HEAD"],
        capture_output=True, text=True, timeout=10,
    )
    return done.stdout.strip()


def resolve_push(push: Push, github: GitHub, comments: list[str]) -> Push:
    """A push with its head sha, the commits it sent and the head's subject. A ref line gives
    the head's short sha; a quiet push prints none, so the branch's head on GitHub is read."""
    head = push.new or github.api(f"git/ref/heads/{push.branch}", ".object.sha")
    full = github.api(f"commits/{head}", ".sha")
    subject = github.api(f"commits/{full}", ".commit.message").splitlines()[0]
    return replace(push, new=full, subject=subject, count=ahead_of(github, push, comments, full))


def resolve_pull(event, github: GitHub):
    """A pull request event with its branch and what GitHub says of the pull request now: its
    head, whether every check has ended and how, the run attempt, the merge commit."""
    pull = github.pull_request(event.number)
    event = replace(event, branch=pull["headRefName"])
    if isinstance(event, Opened):
        return replace(event, head=pull["headRefOid"])
    if isinstance(event, Merged):
        merge = pull.get("mergeCommit") or {}
        return replace(event, commit=merge.get("oid", "") if pull["state"] == "MERGED" else "")
    checks = github.checks(event.number)
    buckets = {c["bucket"] for c in checks}
    ended = bool(checks) and "pending" not in buckets
    return replace(
        event,
        head=pull["headRefOid"],
        ended=ended,
        passed=ended and not buckets & {"fail", "cancel"},
        attempt=github.run_attempt([c.get("link", "") for c in checks]) if ended else 0,
    )


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


def post(github: GitHub, issue: int, body: str, dry_run: bool) -> None:
    if dry_run:
        print(f"#{issue}: {body}")
        return
    github.run("issue", "comment", str(issue), "-R", REPOSITORY, "--body-file", "-", input=body)


def move_card(github: GitHub, issue: int, status: str, when: str | None, dry_run: bool) -> None:
    """Moves the card to `status` when it is at `when` (any status when None)."""
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
        raise Failure(f"card #{issue} to {status}: {done.stderr.strip() or done.returncode}")


def post_measure(github: GitHub, issue: int, dry_run: bool) -> None:
    if dry_run:
        print(f"#{issue}: [dry-run] would post the measure (python3 -I dev/step_measure.py {issue})")
        return
    done = subprocess.run(
        [sys.executable, "-I", str(PROJECT / "dev" / "step_measure.py"), str(issue)],
        capture_output=True, text=True, cwd=PROJECT, timeout=300,
    )
    if done.returncode != 0 or not done.stdout.strip():
        last = (done.stderr.strip().splitlines() or [f"exit {done.returncode}"])[-1]
        raise Failure(f"measure of #{issue}: {last}")
    post(github, issue, f"### {MEASURE_HEADING}\n\n{done.stdout.strip()}", dry_run)


def report(event, github: GitHub, dry_run: bool) -> None:
    """Posts what one event owes: its line, then its card move, then (a merge) the measure.
    The measure is last, so its failure leaves the merge line and the card done."""
    if isinstance(event, Push):
        event = replace(event, branch=current_branch(event))
        issue = issue_of(event.branch)
        if issue is None:
            return
        comments = github.comments(issue)
        event = resolve_push(event, github, comments)
    else:
        event = resolve_pull(event, github)
        issue = issue_of(event.branch)
        if issue is None or not lines_for(event, []):
            return
        comments = github.comments(issue)
    lines = lines_for(event, comments)
    for line in lines:
        post(github, issue, line, dry_run)
    if lines and isinstance(event, Push):
        move_card(github, issue, "In progress", "To do", dry_run)
    if lines and isinstance(event, Merged):
        move_card(github, issue, "Done", None, dry_run)
        post_measure(github, issue, dry_run)


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
    github = GitHub()
    for event in events:
        try:
            report(event, github, options.dry_run)
        except Failure as problem:
            problems.append(str(problem))
        except (KeyError, ValueError, OSError, subprocess.SubprocessError) as problem:
            problems.append(f"{type(problem).__name__}: {problem}")
    if problems:
        print("progress_lines: " + "; ".join(problems).replace("\n", " "), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
