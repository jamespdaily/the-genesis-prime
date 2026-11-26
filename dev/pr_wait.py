"""Waits for pull request N's checks to finish and exits with their outcome (stub)."""

import enum
import sys
from dataclasses import dataclass

GATE_CHECK = "check"
DEADLINE_SECONDS = 1500
POLL_SECONDS = 30
CALL_SECONDS = 60
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
    kind: Kind
    names: tuple[str, ...] = ()


def decide(rows: list[tuple[str, str]]) -> Verdict:
    raise NotImplementedError("decide")


def parse_rows(text: str) -> list[tuple[str, str]]:
    raise NotImplementedError("parse_rows")


def wait(number, fetch, sleep, clock, *, deadline_seconds=DEADLINE_SECONDS, poll_seconds=POLL_SECONDS,
         no_check_seconds=NO_CHECK_SECONDS) -> tuple[int, str]:
    raise NotImplementedError("wait")


def main() -> int:
    raise NotImplementedError("main")


if __name__ == "__main__":
    sys.exit(main())
