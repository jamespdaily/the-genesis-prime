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
                                          comment headed "Measure (draft for the closing summary)"
  (at the merge, the CI line of the merged head comes first, when the issue lacks it)

  Bash call ends
    -> events_of(hook json)           which of the four tools ran at a command's start, from the
                                      command and its output; anything else exits 0 at once,
                                      with no gh call
    -> the shell reads GitHub         issue n's comments, the branch head, the pull request, its
                                      checks and run attempt, the card's status
    -> lines_for(event, comments)     the lines not yet posted for that event
    -> the shell posts them           gh issue comment; dev/card.sh status; step_measure.py

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
    the same sha; a pull request: opened once). The card move and the measure at a merge are
    each keyed on their own state (the card not Done; no comment headed "### Measure (draft"),
    so a retry finishes what a failure left.
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
import shlex
import subprocess
import sys
from dataclasses import dataclass, replace
from pathlib import Path

REPOSITORY = "jamespdaily/the-genesis-prime"
PROJECT = Path(__file__).resolve().parents[2]
MEASURE_HEADING = "Measure (draft for the closing summary)"
MEASURE_PREFIX = "### Measure (draft"

# A git push ref line: ` * [new branch]  a -> b` or `   1a2b3c4..5d6e7f8  a -> b`.
_REF_LINE = re.compile(
    r"^\s*[ +*]\s+(?:\[new branch\]|(?P<old>[0-9a-f]{7,40})\.\.\.?(?P<new>[0-9a-f]{7,40}))"
    r"\s+\S+ -> (?P<branch>\S+)",
    re.MULTILINE,
)
_PULL_REQUEST_URL = re.compile(r"github\.com/([^/\s]+/[^/\s]+)/pull/(\d+)")
_THIS_REMOTE = re.compile(r"github\.com[:/]" + re.escape(REPOSITORY) + r"(?:\.git)?/?$", re.I)
_STEP_BRANCH = re.compile(r"jimd/(\d+)-")
_PUSH_LINE = re.compile(r"^pushed ([0-9a-f]{7}) \(", re.MULTILINE)
_RUN_ID = re.compile(r"/actions/runs/(\d+)")
_HEREDOC = re.compile(r"(?<!<)<<(-?)\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")
_ASSIGNMENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=")
_KEYWORDS = {"then", "do", "else", "elif", "if", "while", "until", "{", "!", "time"}

_GIT_OPTIONS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
_PUSH_OPTIONS_WITH_VALUE = {"-o", "--push-option", "--repo", "--receive-pack", "--exec"}
_PUSH_SKIPPED = {"-d", "--delete", "-n", "--dry-run", "--all", "--mirror", "--tags"}
_GH_OPTIONS_WITH_VALUE = {
    "-b", "--body", "-F", "--body-file", "-t", "--title", "-A", "--author-email",
    "--match-head-commit", "--subject", "-B", "--base", "-H", "--head", "-a", "--assignee",
    "-l", "--label", "-m", "--milestone", "-p", "--project", "-r", "--reviewer", "--template",
}


class Failure(Exception):
    """A step the hook could not finish, as one line for the agent that ran the command."""


def _last_line(text: str, fallback: str) -> str:
    """The last non-empty line of a program's stderr, else `fallback`."""
    lines = [line for line in text.strip().splitlines() if line.strip()]
    return lines[-1].strip() if lines else fallback


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


def issue_of(branch: str) -> int | None:
    """The issue number n of a branch `jimd/<n>-...`."""
    found = _STEP_BRANCH.match(branch)
    return int(found.group(1)) if found else None


def pushed_shas(comments: list[str]) -> list[str]:
    """The sha7 of every push line among an issue's comments, oldest first."""
    return [m for body in comments for m in _PUSH_LINE.findall(body)]


def _without_heredocs(command: str) -> str:
    """The command with each heredoc's body cut, so its text is not read as commands."""
    kept: list[str] = []
    waiting: list[tuple[str, bool]] = []
    for line in command.split("\n"):
        if waiting:
            delimiter, dashed = waiting[0]
            if (line.strip() if dashed else line) == delimiter:
                waiting.pop(0)
            continue
        kept.append(line)
        waiting += [(m[3], bool(m[1])) for m in _HEREDOC.finditer(line)]
    return "\n".join(kept)


def _tokens(command: str) -> list[str]:
    """The words of a shell command, with `&&`, `||`, `;`, `|`, parentheses, redirections and
    newlines as words of their own."""
    lexer = shlex.shlex(command, posix=True, punctuation_chars="();<>|&\n")
    lexer.whitespace_split = True
    lexer.commenters = ""
    lexer.whitespace = " \t\r"
    try:
        words = list(lexer)
    except ValueError:
        words = command.replace("\n", " ; ").split()
    # `2>&1` comes out as "2", ">&", "1": the file descriptor is not an argument.
    return [
        w for i, w in enumerate(words)
        if not (w in {"0", "1", "2"} and i + 1 < len(words) and words[i + 1][:1] in "<>")
    ]


def _is_operator(word: str) -> bool:
    """Whether a word ends a command's arguments: a separator, a newline or a redirection."""
    return bool(word) and (
        all(c in "();<>|&\n" for c in word) or re.match(r"\d*[<>]", word) is not None
    )


def _in_folder(path: str, folder: str | None) -> str | None:
    """The folder a `cd path` or `-C path` leads to from `folder`; None when the path is a
    variable, a substitution or `-`, or is relative to an unknown folder."""
    if re.search(r"[$`]", path) or path == "-":
        return None
    path = os.path.expanduser(path)
    if os.path.isabs(path):
        return os.path.normpath(path)
    return os.path.normpath(os.path.join(folder, path)) if folder else None


@dataclass(frozen=True)
class Simple:
    """One simple command: its words, from its command word on, and the folder it runs in."""

    words: list[str]
    folder: str | None


def _simple_commands(command: str, folder: str | None) -> list[Simple]:
    """The commands of a command line, each with the folder the line's `cd`s lead it to."""
    found: list[Simple] = []
    current: list[str] = []

    def finish() -> None:
        nonlocal folder, current
        words = current
        current = []
        while words and (_ASSIGNMENT.match(words[0]) or words[0] in _KEYWORDS):
            words = words[1:]
        if not words:
            return
        if words[0] == "cd":
            paths = [w for w in words[1:] if w not in {"-P", "-L", "-e", "-@"}]
            folder = _in_folder(paths[0] if paths else "~", folder)
        else:
            found.append(Simple(words, folder))

    for word in _tokens(_without_heredocs(command)):
        if _is_operator(word):
            finish()
        else:
            current.append(word)
    finish()
    return found


def _git_pushes(simple: Simple) -> list[Push]:
    """The pushes `git [options] push [options] remote refspec...` a simple command makes."""
    words, where = simple.words, simple.folder
    i = 1
    while i < len(words) and words[i].startswith("-"):
        if words[i] == "-C" and i + 1 < len(words):
            where = _in_folder(words[i + 1], where)
        i += 2 if words[i] in _GIT_OPTIONS_WITH_VALUE else 1
    if i >= len(words) or words[i] != "push":
        return []
    rest, skip = [], False
    for word in words[i + 1 :]:
        if skip:
            skip = False
        elif word in _PUSH_OPTIONS_WITH_VALUE:
            skip = True
        else:
            rest.append(word)
    if {w for w in rest if w.startswith("-")} & _PUSH_SKIPPED:
        return []
    positional = [w for w in rest if not w.startswith("-")]
    remote = positional[0] if positional else "origin"
    pushes = []
    for refspec in positional[1:] or ["HEAD"]:
        destination = refspec.lstrip("+").split(":")[-1].removeprefix("refs/heads/")
        if destination:
            pushes.append(Push(destination, where, remote))
    return pushes


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
    for simple in _simple_commands(command, folder):
        program = os.path.basename(simple.words[0])
        if program == "git":
            pushes += _git_pushes(simple)
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

    def execute(self, *args: str, input: str | None = None, cwd: str | None = None):
        """gh's finished process; a gh that cannot run or runs too long is a Failure."""
        try:
            return subprocess.run(
                ["gh", *args], capture_output=True, text=True, input=input,
                env=self.environment, timeout=120, cwd=cwd,
            )
        except (OSError, subprocess.TimeoutExpired) as problem:
            raise Failure(f"gh {args[0]}: {problem}") from problem

    def run(self, *args: str, input: str | None = None, cwd: str | None = None) -> str:
        """gh's stdout. A failure raises with gh's last stderr line."""
        done = self.execute(*args, input=input, cwd=cwd)
        if done.returncode != 0:
            raise Failure(f"gh {' '.join(args[:2])}: {_last_line(done.stderr, f'exit {done.returncode}')}")
        return done.stdout

    def api(self, path: str, jq: str) -> str:
        return self.run("api", f"repos/{REPOSITORY}/{path}", "--jq", jq).strip()

    def head(self, ref: str) -> tuple[str, str] | None:
        """The full sha and subject of a branch's head or of a commit; None when GitHub has no
        such branch or commit."""
        done = self.execute("api", f"repos/{REPOSITORY}/commits/{ref}", "--jq", "[.sha,.commit.message]")
        if done.returncode != 0:
            if "HTTP 404" in done.stderr or "No commit found" in done.stderr:
                return None
            raise Failure(f"gh api commits/{ref}: {_last_line(done.stderr, f'exit {done.returncode}')}")
        sha, message = json.loads(done.stdout)
        return sha, (message.splitlines() or [""])[0]

    def comments(self, issue: int) -> list[str]:
        out = self.run(
            "issue", "view", str(issue), "-R", REPOSITORY, "--json", "comments",
            "--jq", "[.comments[].body]",
        )
        return json.loads(out)

    def pull_request(self, target: list[str], folder: str | None) -> dict:
        """`gh pr view` of a number, URL or branch of this repository, or (no target) of the
        folder's branch."""
        fields = "number,state,headRefName,headRefOid,mergeCommit,closingIssuesReferences"
        if target:
            return json.loads(self.run("pr", "view", *target, "-R", REPOSITORY, "--json", fields))
        return json.loads(self.run("pr", "view", "--json", fields, cwd=folder))

    def checks(self, number: int) -> list[dict]:
        """A pull request's checks: gh exits 0 (all passed), 1 (one failed, or none reported) or
        8 (pending) with the JSON; anything else is a failure."""
        done = self.execute("pr", "checks", str(number), "-R", REPOSITORY, "--json", "bucket,link")
        if done.returncode in (0, 1, 8):
            try:
                checks = json.loads(done.stdout)
                if isinstance(checks, list):
                    return checks
            except json.JSONDecodeError:
                pass
            if done.returncode == 1 and "no checks reported" in done.stderr:
                return []
        raise Failure(f"gh pr checks {number}: {_last_line(done.stderr, f'exit {done.returncode}')}")

    def run_attempt(self, links: list[str]) -> int:
        runs = {m.group(1) for link in links if (m := _RUN_ID.search(link))}
        return max((int(self.api(f"actions/runs/{r}", ".run_attempt")) for r in runs), default=1)

    def card_status(self, issue: int) -> str:
        """The card's board status, from dev/card.sh."""
        done = subprocess.run(
            [str(PROJECT / "dev" / "card.sh"), "get", str(issue)],
            capture_output=True, text=True, env=self.environment, timeout=120,
        )
        if done.returncode != 0:
            raise Failure(f"card #{issue}: {_last_line(done.stderr, f'exit {done.returncode}')}")
        return done.stdout.strip()


def names_repository(folder: str | None, remote: str) -> bool:
    """Whether `remote` of the git folder is this repository. A folder that is a variable
    (cd or -C) is a Failure; a folder that is not a git folder is not this repository."""
    if folder is None:
        raise Failure("the command's folder (cd or -C) is a variable: cannot tell its repository")
    url = remote
    if "/" not in remote and ":" not in remote:
        try:
            done = subprocess.run(
                ["git", "-C", folder, "remote", "get-url", remote],
                capture_output=True, text=True, timeout=10,
            )
        except (OSError, subprocess.TimeoutExpired):
            return False
        if done.returncode != 0:
            return False
        url = done.stdout
    return _THIS_REMOTE.search(url.strip()) is not None


def current_branch(push: Push) -> str:
    """The pushed branch's name: "HEAD" is the current branch of the push's folder."""
    if push.branch != "HEAD":
        return push.branch
    done = subprocess.run(
        ["git", "-C", push.folder, "symbolic-ref", "--short", "HEAD"],
        capture_output=True, text=True, timeout=10,
    )
    return done.stdout.strip()


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
        raise Failure(f"card #{issue} to {status}: {_last_line(done.stderr, f'exit {done.returncode}')}")


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
        raise Failure(f"measure of #{issue}: {_last_line(done.stderr, f'exit {done.returncode}')}")
    post(github, issue, f"### {MEASURE_HEADING}\n\n{done.stdout.strip()}", dry_run)


def report_push(event: Push, github: GitHub, dry_run: bool) -> None:
    """A push: its line, then the card to In progress when it is To do. A branch GitHub lacks
    (a push that failed) posts nothing."""
    if not names_repository(event.folder, event.remote):
        return
    branch = current_branch(event)
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


def report_pull(event: Pull, github: GitHub, dry_run: bool) -> None:
    """A pull request opened, its checks waited on, or its merge."""
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
        report_merge(github, pull, issue, dry_run)


def report_merge(github: GitHub, pull: dict, issue: int, dry_run: bool) -> None:
    """A merged pull request: the CI line of its head, the merge line, and, when it closes the
    issue, the card to Done and the measure. Each part is attempted whatever the others do, and
    the failures are raised together."""
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

    attempt(lines)
    if closes:
        attempt(lambda: move_card(github, issue, "Done", None, dry_run))
        attempt(lambda: post_measure(github, issue, comments, dry_run))
    if problems:
        raise Failure("; ".join(problems))


def report(event, github: GitHub, dry_run: bool) -> None:
    """Posts what one event owes."""
    if isinstance(event, Push):
        report_push(event, github, dry_run)
    else:
        report_pull(event, github, dry_run)


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
