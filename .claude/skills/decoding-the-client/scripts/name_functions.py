"""Saves every name in the fact file into the Ghidra project.

Read-only by default: reports, for each record with a name, whether its
function exists and what it is called now. With GHIDRA_WRITE=1 it creates a
missing function, renames each one and saves the project. Run with the pinned
Python and the environment ghidra_env reads, while no query process holds the
project open.

Usage: python3 -I name_functions.py
"""

import os
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_facts  # noqa: E402


@dataclass(frozen=True)
class Outcome:
    address: str
    name: str
    found: str | None  # the name the project held, or None when there was no function
    failed: str | None  # why it could not be named, or None


def name_pairs(records: dict[str, check_facts.Record]) -> list[tuple[int, str]]:
    """(address, name) for every record keyed by an address that has a name, sorted."""
    raise NotImplementedError


def apply_names(program, pairs: list[tuple[int, str]], write: bool) -> list[Outcome]:
    """Names each function in an open program; with write, inside one transaction."""
    raise NotImplementedError


def main() -> int:
    raise NotImplementedError


if __name__ == "__main__":
    sys.exit(main())
