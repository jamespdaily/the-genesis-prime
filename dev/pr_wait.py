"""Waits for pull request N's checks to finish and exits with their outcome.

    dev/pr_wait.sh N          (runs this file)

The checks are read every POLL_SECONDS with `gh pr checks N --json name,bucket` (never
`--watch`, whose own loop has no deadline). `decide` turns one reading into a verdict, `wait`
repeats it until the verdict ends the wait, and `ask_gh` is the only call to gh, cut at
CALL_SECONDS.

    ask_gh -> parse_rows -> decide -> wait (sleep, deadline) -> exit status

The checks have ended when every one passed and one is named `check`: CI's gate job, which
branch protection requires, is made about a second after the last part job ends.

A call that fails, is cut at its limit or answers something other than a JSON list of
checks is tried again after a poll; TRIES failed in a row end the wait with 3, so a passing
blip does not. A failed or cancelled check ends the wait at once, while others still pend.

Exit status:
  0  every check passed
  1  a check failed (the line `pr_wait: failing jobs: A, B` on stderr names them), or no
     check appeared within NO_CHECK_SECONDS
  2  usage
  3  a GitHub call failed on all its tries; nothing is known of the checks
  4  DEADLINE_SECONDS passed; the line on stderr names the checks still pending, or says no
     check named `check` appeared

The environment sets the limits for the tests: PR_WAIT_DEADLINE_SECONDS, PR_WAIT_POLL_SECONDS,
PR_WAIT_CALL_SECONDS and PR_WAIT_NO_CHECK_SECONDS (seconds, a decimal point allowed).
Run: python3.13 -I dev/pr_wait.py N
"""

import enum
import json
import os
import re
import subprocess
import sys
import time
from collections.abc import Callable
from dataclasses import dataclass

GATE_CHECK = "check"
# 25 min: 1.8 times 846 s, the longest of the 100 latest check.yml runs (measured 2026-11-26).
DEADLINE_SECONDS = 1500
# Half a minute: gh's own watch interval, which this replaces.
POLL_SECONDS = 30
# One minute: a gh call that answers takes seconds; a longer one is hung.
CALL_SECONDS = 60
# 5 min: the time the old wait gave a pull request to get its first check (20 polls of 15 s).
NO_CHECK_SECONDS = 300
TRIES = 3


class CallFailed(Exception):
    """A gh call that failed, was cut at its limit, or answered something else than asked."""


class Kind(enum.Enum):
    PASS = "pass"
    FAIL = "fail"
    WAIT = "wait"
    NONE = "none"


@dataclass(frozen=True)
class Verdict:
    """PASS: every check passed. FAIL: names are the failed or cancelled checks. WAIT: names are
    the pending checks (none when only the gate job is missing). NONE: no check yet."""

    kind: Kind
    names: tuple[str, ...] = ()


def decide(rows: list[tuple[str, str]]) -> Verdict:
    """The verdict on one reading of the checks, as (bucket, name) rows in gh's order."""
    if not rows:
        return Verdict(Kind.NONE)
    failed = tuple(name for bucket, name in rows if bucket in ("fail", "cancel"))
    if failed:
        return Verdict(Kind.FAIL, failed)
    pending = tuple(name for bucket, name in rows if bucket == "pending")
    if pending or not any(name == GATE_CHECK for _, name in rows):
        return Verdict(Kind.WAIT, pending)
    return Verdict(Kind.PASS)


def parse_rows(text: str) -> list[tuple[str, str]]:
    """The (bucket, name) rows of gh's JSON list of checks; anything else is a failed call."""
    try:
        listed = json.loads(text)
    except json.JSONDecodeError as error:
        raise CallFailed(f"gh answered '{text.strip()[:80]}', not JSON ({error.msg})") from error
    if not isinstance(listed, list):
        raise CallFailed("gh answered JSON that is not a list of checks")
    rows = []
    for item in listed:
        if not (isinstance(item, dict) and isinstance(item.get("bucket"), str) and isinstance(item.get("name"), str)):
            raise CallFailed("gh answered a check without a name and a bucket")
        rows.append((item["bucket"], item["name"]))
    return rows


def wait(
    number: int,
    fetch: Callable[[], str],
    sleep: Callable[[float], None],
    clock: Callable[[], float],
    *,
    deadline_seconds: float = DEADLINE_SECONDS,
    poll_seconds: float = POLL_SECONDS,
    no_check_seconds: float = NO_CHECK_SECONDS,
) -> tuple[int, str]:
    """Polls until a verdict ends the wait; returns the exit status and the line for stderr
    (empty on a pass). `fetch` returns gh's answer or raises CallFailed."""
    start = clock()
    failed_in_a_row = 0
    seen_a_check = False
    last = None
    while True:
        try:
            last = decide(parse_rows(fetch()))
            failed_in_a_row = 0
        except CallFailed as error:
            failed_in_a_row += 1
            if failed_in_a_row >= TRIES:
                return 3, f"pr_wait: a GitHub call failed ({error}) on pull request {number}"
        else:
            if last.kind is Kind.PASS:
                return 0, ""
            if last.kind is Kind.FAIL:
                return 1, f"pr_wait: failing jobs: {', '.join(last.names)}"
            if last.kind is Kind.NONE and not seen_a_check and clock() - start >= no_check_seconds:
                return 1, f"pr_wait: no check on pull request {number} after {no_check_seconds:g} s"
            seen_a_check = seen_a_check or last.kind is not Kind.NONE
        if clock() - start >= deadline_seconds:
            return 4, f"pr_wait: deadline of {deadline_seconds:g} s passed on pull request {number}; {unfinished(last)}"
        sleep(poll_seconds)


def unfinished(verdict: Verdict | None) -> str:
    """What the deadline message says is missing."""
    if verdict is not None and verdict.names:
        return f"still pending: {', '.join(verdict.names)}"
    if verdict is None:
        return "no answer from GitHub"
    return f"no check named {GATE_CHECK} appeared"


def ask_gh(number: int, call_seconds: float) -> str:
    """gh's JSON of the checks of pull request `number`; a call that fails or is cut at its
    limit raises CallFailed. A pull request with no check yet is an empty list."""
    try:
        done = subprocess.run(
            ["gh", "pr", "checks", str(number), "--json", "name,bucket"],
            capture_output=True, text=True, timeout=call_seconds, check=False,
        )
    except subprocess.TimeoutExpired as error:
        raise CallFailed(f"gh pr checks did not answer within {call_seconds:g} s") from error
    except OSError as error:
        raise CallFailed(f"gh could not run: {error}") from error
    if done.returncode != 0:
        if "no checks reported" in done.stderr:
            return "[]"
        raise CallFailed(f"gh pr checks ended with status {done.returncode}: {done.stderr.strip()[:80]}")
    return done.stdout


def seconds_from(name: str, default: float) -> float:
    return float(os.environ.get(name, default))


def main() -> int:
    if len(sys.argv) != 2 or not re.fullmatch(r"[0-9]+", sys.argv[1]):
        print("usage: dev/pr_wait.sh N", file=sys.stderr)
        return 2
    number = int(sys.argv[1])
    call_seconds = seconds_from("PR_WAIT_CALL_SECONDS", CALL_SECONDS)
    status, message = wait(
        number,
        lambda: ask_gh(number, call_seconds),
        time.sleep,
        time.monotonic,
        deadline_seconds=seconds_from("PR_WAIT_DEADLINE_SECONDS", DEADLINE_SECONDS),
        poll_seconds=seconds_from("PR_WAIT_POLL_SECONDS", POLL_SECONDS),
        no_check_seconds=seconds_from("PR_WAIT_NO_CHECK_SECONDS", NO_CHECK_SECONDS),
    )
    if message:
        print(message, file=sys.stderr)
    return status


if __name__ == "__main__":
    sys.exit(main())
