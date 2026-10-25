"""The seed file applied to the Ghidra project before analysis.

One line per function: `0x<address>\\tfunction\\t<name>`. Until the fact file
names them, functions are named `seed_<address>`: every .pdata start, and
every function reached only through a relocated pointer.
"""

from pathlib import Path

from client_pe import ClientPE

PLANTED_UNMAPPED = 0x1BFFFF000  # outside every section; used only by tests


def seed_lines(pe: ClientPE) -> list[tuple[int, str, str]]:
    """(address, 'function', name), sorted, without duplicates."""
    raise NotImplementedError


def write_seed(lines: list[tuple[int, str, str]], path: Path) -> None:
    raise NotImplementedError


def read_seed(path: Path) -> list[tuple[int, str, str]]:
    """Refuses a malformed line, a duplicate address or a name with whitespace."""
    raise NotImplementedError
