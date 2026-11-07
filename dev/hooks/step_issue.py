"""What the hooks in this folder share about a step's issue and this repository's GitHub.

A step's branch is `jimd/<n>-...` and its issue is n. A hook script puts this folder on
`sys.path` first, because `python3 -I` leaves the script's folder off it.

  issue_of(branch)                    the issue number of a step branch
  names_repository(folder, remote)    whether a git folder's remote is this repository
  current_branch(branch, folder)      a push's branch, "HEAD" read from the folder
  GitHub                              gh as the jamespdaily login, to this repository
"""

import json
import os
import re
import subprocess
from pathlib import Path

REPOSITORY = "jamespdaily/the-genesis-prime"
PROJECT = Path(__file__).resolve().parents[2]

_THIS_REMOTE = re.compile(r"github\.com[:/]" + re.escape(REPOSITORY) + r"(?:\.git)?/?$", re.I)
_STEP_BRANCH = re.compile(r"jimd/(\d+)-")
_RUN_ID = re.compile(r"/actions/runs/(\d+)")


class Failure(Exception):
    """A step the hook could not finish, as one line for the agent that ran the command."""


def last_line(text: str, fallback: str) -> str:
    """The last non-empty line of a program's stderr, else `fallback`."""
    lines = [line for line in text.strip().splitlines() if line.strip()]
    return lines[-1].strip() if lines else fallback


def issue_of(branch: str) -> int | None:
    """The issue number n of a branch `jimd/<n>-...`."""
    found = _STEP_BRANCH.match(branch)
    return int(found.group(1)) if found else None


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


def current_branch(branch: str, folder: str) -> str:
    """A pushed branch's name: "HEAD" is the current branch of the push's folder."""
    if branch != "HEAD":
        return branch
    done = subprocess.run(
        ["git", "-C", folder, "symbolic-ref", "--short", "HEAD"],
        capture_output=True, text=True, timeout=10,
    )
    return done.stdout.strip()


class GitHub:
    """The calls the hooks make, as the jamespdaily login, to this repository. A gh call that
    runs longer than `timeout` seconds is a Failure."""

    def __init__(self, timeout: int = 120) -> None:
        self._environment: dict | None = None
        self._timeout = timeout

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
                env=self.environment, timeout=self._timeout, cwd=cwd,
            )
        except (OSError, subprocess.TimeoutExpired) as problem:
            raise Failure(f"gh {args[0]}: {problem}") from problem

    def run(self, *args: str, input: str | None = None, cwd: str | None = None) -> str:
        """gh's stdout. A failure raises with gh's last stderr line."""
        done = self.execute(*args, input=input, cwd=cwd)
        if done.returncode != 0:
            raise Failure(f"gh {' '.join(args[:2])}: {last_line(done.stderr, f'exit {done.returncode}')}")
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
            raise Failure(f"gh api commits/{ref}: {last_line(done.stderr, f'exit {done.returncode}')}")
        sha, message = json.loads(done.stdout)
        return sha, (message.splitlines() or [""])[0]

    def texts(self, issue: int) -> list[str]:
        """An issue's body followed by its comments' bodies."""
        out = self.run(
            "issue", "view", str(issue), "-R", REPOSITORY, "--json", "body,comments",
            "--jq", "[.body] + [.comments[].body]",
        )
        return json.loads(out)

    def comments(self, issue: int) -> list[str]:
        """An issue's comments' bodies."""
        return self.texts(issue)[1:]

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
        raise Failure(f"gh pr checks {number}: {last_line(done.stderr, f'exit {done.returncode}')}")

    def run_attempt(self, links: list[str]) -> int:
        runs = {m.group(1) for link in links if (m := _RUN_ID.search(link))}
        return max((int(self.api(f"actions/runs/{r}", ".run_attempt")) for r in runs), default=1)

    def card_status(self, issue: int) -> str:
        """The card's board status, from dev/card.sh."""
        done = subprocess.run(
            [str(PROJECT / "dev" / "card.sh"), "get", str(issue)],
            capture_output=True, text=True, env=self.environment, timeout=self._timeout,
        )
        if done.returncode != 0:
            raise Failure(f"card #{issue}: {last_line(done.stderr, f'exit {done.returncode}')}")
        return done.stdout.strip()
