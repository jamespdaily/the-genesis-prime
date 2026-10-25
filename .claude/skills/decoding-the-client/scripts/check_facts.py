"""The fact file's checker: every record well formed, every cited client address recorded.

A record is one TOML table in references/client-facts.toml, keyed by a client
address (lower-case, 0x-prefixed), an opcode, a table column, an enum or a Lua
function. Its fields:

  statement  what the client does, in the game's or the message's terms
  proof      how it was read: the instructions, the table rows, the test that checks it
  grade      "sure", "fairly sure" or "guess"
  gap        what is not yet read, and what would settle it; for "fairly sure" and "guess" only
  name       the function's name, when the key is a function's entry

An address a test plants on purpose is assigned to a name starting with
PLANTED_, as seed.PLANTED_UNMAPPED is, and is not a fact.

Usage: python3 -I check_facts.py  (exits non-zero and prints each problem)
"""

import sys
from dataclasses import dataclass
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
FACT_FILE = SCRIPTS.parent / "references" / "client-facts.toml"
REPOSITORY = SCRIPTS.parents[3]
GRADES = ("sure", "fairly sure", "guess")


@dataclass(frozen=True)
class Record:
    key: str
    statement: str
    proof: str
    grade: str
    gap: str | None
    name: str | None


@dataclass(frozen=True)
class Problem:
    where: str  # a record's key, or a file and line that cites an address
    what: str


def load(path: Path) -> dict[str, Record]:
    """Reads the fact file; a duplicate key or a malformed table raises ValueError naming it."""
    raise NotImplementedError


def record_problems(records: dict[str, Record], function_entries: set[str]) -> list[Problem]:
    """Each record's fields, grade, gap, name and wording, against the rules above.
    function_entries holds the keys known to be a function's entry."""
    raise NotImplementedError


def cited_addresses(repository: Path) -> dict[str, list[str]]:
    """Every 0x14xxxxxxx address in the repository's tracked files, outside the
    fact file and lines that assign a PLANTED_ name: address -> ["file:line", ...]."""
    raise NotImplementedError


def coverage_problems(records: dict[str, Record], cited: dict[str, list[str]]) -> list[Problem]:
    """One problem per cited address that no record holds as its key or in its statement or proof."""
    raise NotImplementedError


def main(argv: list[str]) -> int:
    """Checks the fact file against the repository. The name rule needs the
    client at $WILDSTAR_CLIENT_EXE to know the function entries; without it,
    main says the rule was not checked."""
    raise NotImplementedError


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
