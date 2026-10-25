"""The setup check: names every part this machine is missing, with its fix.

It runs before anything else, and the full check runs it first. It checks
every part, prints each missing one with what was found and how to fix it,
then exits non-zero. It installs nothing.

Settings come from the environment; on a development machine
$GENESIS_HOME/env.sh (default ~/.genesis-prime/env.sh) sets them, and the
full check reads it. GENESIS_NO_CLIENT=1 marks a machine without the client,
such as CI: the client, the client query process and the patched OTP are not
checked there.

Usage: ./setup-check
"""

import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Mapping

REPOSITORY = Path(__file__).resolve().parent.parent


@dataclass(frozen=True)
class Missing:
    part: str  # what is missing, as the reader knows it: "Postgres 18", "Gleam 1.19.2"
    found: str  # what is there instead, or "nothing"
    fix: str  # what to do, as a command or a setting where one exists


@dataclass(frozen=True)
class Machine:
    """What a check may look at, so a test can plant a machine missing a part."""

    env: Mapping[str, str]
    repository: Path
    run: Callable[[list[str]], tuple[int, str]]  # a command -> (exit code, stdout and stderr)


def tool_versions(machine: Machine) -> dict[str, str]:
    """The pinned versions in .tool-versions: tool -> version."""
    raise NotImplementedError


def check_gleam(machine: Machine) -> list[Missing]:
    raise NotImplementedError


def check_erlang(machine: Machine) -> list[Missing]:
    """OTP as pinned, and on a machine with the client the patched build the
    full check runs on (GENESIS_OTP_DIR, with its patch marker)."""
    raise NotImplementedError


def check_rebar(machine: Machine) -> list[Missing]:
    raise NotImplementedError


def check_manifest(machine: Machine) -> list[Missing]:
    raise NotImplementedError


def check_postgres(machine: Machine) -> list[Missing]:
    """Reachable at PGHOST, PGPORT and PGUSER; major version 18; its clock
    within 1 second of this machine's."""
    raise NotImplementedError


def check_client(machine: Machine) -> list[Missing]:
    """WildStar64.exe with the pinned SHA-256, and every Patch/*.index on the
    target build."""
    raise NotImplementedError


def check_query_process(machine: Machine) -> list[Missing]:
    """The client query process's pinned parts (ghidra_env.check_parts) and
    its environment, with a project path Ghidra accepts."""
    raise NotImplementedError


def check_all(machine: Machine) -> list[Missing]:
    """Every part's check, in order, skipping the client's parts where
    GENESIS_NO_CLIENT=1."""
    raise NotImplementedError


def main() -> int:
    raise NotImplementedError


if __name__ == "__main__":
    sys.exit(main())
