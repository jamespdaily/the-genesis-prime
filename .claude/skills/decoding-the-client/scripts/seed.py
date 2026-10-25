"""The seed file applied to the Ghidra project before analysis.

One line per function: `0x<address>\\tfunction\\t<name>`. Until the fact file
names them, functions are named `seed_<address>`: every .pdata start, and
every function reached only through a relocated pointer.
"""

import re
from pathlib import Path

from client_pe import ClientPE

PLANTED_UNMAPPED = 0x1BFFFF000  # outside every section; used only by tests
_ADDRESS = re.compile(r"0x[0-9a-fA-F]{1,16}")


def seed_lines(pe: ClientPE) -> list[tuple[int, str, str]]:
    """(address, 'function', name), sorted, without duplicates."""
    addresses = sorted(set(pe.function_starts()) | set(pe.pointer_only_functions()))
    return [(a, "function", "seed_%x" % a) for a in addresses]


def write_seed(lines: list[tuple[int, str, str]], path: Path) -> None:
    with open(path, "w", newline="\n") as f:
        for address, kind, name in lines:
            f.write("0x%x\t%s\t%s\n" % (address, kind, name))


def read_seed(path: Path) -> list[tuple[int, str, str]]:
    """Refuses a malformed line, a duplicate address or a name with whitespace."""
    lines = []
    seen = set()
    for number, line in enumerate(Path(path).read_text().splitlines(), 1):
        fields = line.split("\t")
        if len(fields) != 3:
            raise ValueError("seed line %d has %d fields, not 3" % (number, len(fields)))
        address_text, kind, name = fields
        if not _ADDRESS.fullmatch(address_text):
            raise ValueError("seed line %d: %r is not 0x followed by hex digits" % (number, address_text))
        address = int(address_text, 16)
        if address in seen:
            raise ValueError("seed line %d: duplicate address %s" % (number, address_text))
        if not name or any(c.isspace() for c in name):
            raise ValueError("seed line %d: the name must be non-empty without whitespace" % number)
        seen.add(address)
        lines.append((address, kind, name))
    return lines
