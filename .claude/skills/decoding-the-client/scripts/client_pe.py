"""Reads WildStar64.exe's PE tables straight from its bytes, with no analyser.

It is the independent evidence the query process is checked against:
sections, the .pdata function table, imports and base relocations.
"""

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Section:
    name: str
    va: int
    virtual_size: int
    raw_offset: int
    raw_size: int
    executable: bool

    @property
    def end(self) -> int:
        return self.va + self.virtual_size


@dataclass(frozen=True)
class RuntimeFunction:
    begin: int
    end: int
    unwind: int
    chained_to: int | None  # the parent entry's begin when UNW_FLAG_CHAININFO is set


class ClientPE:
    def __init__(self, path: Path):
        raise NotImplementedError

    image_base: int
    sections: list[Section]

    def read(self, va: int, n: int) -> bytes:
        """n bytes at va, from the file; raises ValueError outside initialised data."""
        raise NotImplementedError

    def section_of(self, va: int) -> Section | None:
        raise NotImplementedError

    def runtime_functions(self) -> list[RuntimeFunction]:
        """Every .pdata entry, sorted by begin."""
        raise NotImplementedError

    def function_starts(self) -> list[int]:
        """The begin of every entry that is not chained."""
        raise NotImplementedError

    def root_of(self, va: int) -> int | None:
        """The function start whose .pdata ranges, chained ones included, hold va."""
        raise NotImplementedError

    def root_ranges(self, function_start: int) -> list[tuple[int, int]]:
        raise NotImplementedError

    def imports(self) -> dict[int, str]:
        """IAT slot address -> 'dll!name' or 'dll!#ordinal', dll lower-case; delay imports included."""
        raise NotImplementedError

    def relocations(self) -> list[tuple[int, int]]:
        """(address, 8-byte value) for every DIR64 base relocation."""
        raise NotImplementedError

    def pointer_only_functions(self) -> list[int]:
        """Targets of relocated pointers into .text that lie outside every .pdata range."""
        raise NotImplementedError
