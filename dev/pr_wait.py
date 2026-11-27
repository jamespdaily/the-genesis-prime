"""Waits for pull request N's checks to finish and exits with their outcome.

    dev/pr_wait.sh N          (runs this file)

The checks are read every POLL_SECONDS with `gh pr checks N --json name,bucket` (never
`--watch`, whose own loop has no deadline). While no check has appeared, the pull request's
`mergeable` is read too, with `gh pr view N --json mergeable`: GitHub runs no check on a
CONFLICTING pull request, so waiting for one is pointless. `decide` turns one reading (the
rows and the mergeable value) into a verdict, `wait` repeats it until the verdict ends the
wait, and `ask_gh` is the only call to gh, cut at CALL_SECONDS.

    ask_gh -> parse_rows (+ parse_mergeable when no row) -> decide -> wait (sleep, deadline)
        -> exit status

The checks have ended when every one passed and one is named `check`: CI's gate job, which
branch protection requires, is made about a second after the last part job ends.

A mergeable value of UNKNOWN or MERGEABLE changes nothing: the wait goes on as for no check.
A call that fails, is cut at its limit or answers something other than a JSON list of
checks is tried again after a poll; TRIES failed in a row end the wait with 3, so a passing
blip does not. A failed or cancelled check ends the wait at once, while others still pend.

Exit status:
  0  every check passed
  1  a check failed (the line `pr_wait: failing jobs: A, B` on stderr names them), or no
     check appeared within NO_CHECK_SECONDS, or no check has appeared and the pull request is
     CONFLICTING (the line says it conflicts with its base and GitHub runs no check on it)
  2  usage
  3  a GitHub call failed on all its tries, or this script failed (its traceback is on
     stderr); nothing is known of the checks
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
import traceback
from collections.abc import Callable
from dataclasses import dataclass

GATE_CHECK = "check"
# 25 min: 1.8 times 846 s, the longest of the 100 latest check.yml runs (measured 2026-11-26).
DEADLINE_SECONDS = 1500
# Half a minute: the interval the old script gave gh's --watch (gh's own default is 10 s).
POLL_SECONDS = 30
# One minute: a gh call that answers takes seconds; a longer one is hung.
CALL_SECONDS = 60
# 5 min: the time the old wait gave a pull request to get its first check (20 polls of 15 s).
NO_CHECK_SECONDS = 300
TRIES = 3
CONFLICTING = "CONFLICTING"
UNKNOWN = "UNKNOWN"


class CallFailed(Exception):
    """A gh call that failed, was cut at its limit, or answered something else than asked."""


class Kind(enum.Enum):
    PASS = "pass"
    FAIL = "fail"
    WAIT = "wait"
    NONE = "none"
    CONFLICT = "conflict"


@dataclass(frozen=True)
class Verdict:
    """PASS: every check passed. FAIL: names are the failed or cancelled checks. WAIT: names are
    the pending checks (none when only the gate job is missing). NONE: no check yet. CONFLICT: no
    check yet and the pull request conflicts with its base."""

    kind: Kind
    names: tuple[str, ...] = ()


def decide(rows: list[tuple[str, str]], mergeable: str) -> Verdict:
    """The verdict on one reading: the checks as (bucket, name) rows in gh's order, and the
    pull request's `mergeable` (read only while there is no row; otherwise it is ignored)."""
    if not rows:
        return Verdict(Kind.CONFLICT if mergeable == CONFLICTING else Kind.NONE)
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


def parse_mergeable(text: str) -> str:
    """The `mergeable` value of gh's JSON for the pull request; anything else is a failed call."""
    try:
        read = json.loads(text)
    except json.JSONDecodeError as error:
        raise CallFailed(f"gh answered '{text.strip()[:80]}', not JSON ({error.msg})") from error
    if not (isinstance(read, dict) and isinstance(read.get("mergeable"), str)):
        raise CallFailed("gh answered JSON without a mergeable value")
    return read["mergeable"]


def wait(
    number: int,
    fetch: Callable[[], str],
    sleep: Callable[[float], None],
    clock: Callable[[], float],
    fetch_mergeable: Callable[[], str],
    *,
    deadline_seconds: float = DEADLINE_SECONDS,
    poll_seconds: float = POLL_SECONDS,
    no_check_seconds: float = NO_CHECK_SECONDS,
) -> tuple[int, str]:
    """Polls until a verdict ends the wait; returns the exit status and the line for stderr
    (empty on a pass). `fetch` and `fetch_mergeable` return gh's answer or raise CallFailed;
    the second is called only while no check has appeared."""
    start = clock()
    failed_in_a_row = 0
    seen_a_check = False
    last = None
    while True:
        try:
            rows = parse_rows(fetch())
            mergeable = parse_mergeable(fetch_mergeable()) if not rows and not seen_a_check else UNKNOWN
            last = decide(rows, mergeable)
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
            if last.kind is Kind.CONFLICT:
                return 1, f"pr_wait: pull request {number} conflicts with its base and GitHub runs no check on it"
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
    if verdict.kind is Kind.NONE:
        return "no check is listed"
    return f"no check named {GATE_CHECK} appeared"


def ask_gh(number: int, call_seconds: float, field: str) -> str:
    """gh's JSON of pull request `number`: its checks (`field` "checks"; a pull request with no
    check yet is an empty list) or its mergeable value (`field` "mergeable"). A call that
    fails or is cut at its limit raises CallFailed."""
    if field == "checks":
        command = ["gh", "pr", "checks", str(number), "--json", "name,bucket"]
    else:
        command = ["gh", "pr", "view", str(number), "--json", "mergeable"]
    try:
        done = subprocess.run(
            command,
            capture_output=True, text=True, timeout=call_seconds, check=False,
        )
    except subprocess.TimeoutExpired as error:
        raise CallFailed(f"gh pr {command[2]} did not answer within {call_seconds:g} s") from error
    except OSError as error:
        raise CallFailed(f"gh could not run: {error}") from error
    if done.returncode != 0:
        # gh 2.105.0's text when the pull request has no check yet ("no checks reported on the '%s' branch").
        if field == "checks" and "no checks reported" in done.stderr:
            return "[]"
        raise CallFailed(f"gh pr {command[2]} ended with status {done.returncode}: {done.stderr.strip()[:80]}")
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
        lambda: ask_gh(number, call_seconds, "checks"),
        time.sleep,
        time.monotonic,
        lambda: ask_gh(number, call_seconds, "mergeable"),
        deadline_seconds=seconds_from("PR_WAIT_DEADLINE_SECONDS", DEADLINE_SECONDS),
        poll_seconds=seconds_from("PR_WAIT_POLL_SECONDS", POLL_SECONDS),
        no_check_seconds=seconds_from("PR_WAIT_NO_CHECK_SECONDS", NO_CHECK_SECONDS),
    )
    if message:
        print(message, file=sys.stderr)
    return status


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:  # a crash is not a check's failure: 1 would tell the merge script CI failed
        traceback.print_exc()
        sys.exit(3)
