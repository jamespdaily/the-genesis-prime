"""A reference index of WildStar64.exe from llvm-objdump and the relocations,
independent of Ghidra. Tests use it as the expected answer for the query
process.

Built by a linear sweep of the executable sections: data inside .text can
decode as stray instructions, so a query names the .pdata function of each site.
"""

from dataclasses import dataclass
from pathlib import Path

from client_pe import ClientPE


@dataclass(frozen=True)
class Ref:
    source: int
    target: int
    kind: str  # call, jmp, jcc, rip-data, rip-lea, call-mem, jmp-mem, pointer


class RefIndex:
    @staticmethod
    def build(pe: ClientPE, objdump: Path, jobs: int) -> "RefIndex":
        raise NotImplementedError

    @staticmethod
    def load(path: Path) -> "RefIndex":
        raise NotImplementedError

    def save(self, path: Path) -> None:
        raise NotImplementedError

    def refs_to(self, target: int) -> list[Ref]:
        raise NotImplementedError

    def callers(self, function_start: int) -> dict[int, list[int]]:
        """Caller function start -> call sites, counting a jmp to the entry as a
        call, as Ghidra does. Sites outside every function are left out."""
        raise NotImplementedError

    def callees(self, function_start: int) -> tuple[list[int], list[str]]:
        """(direct call targets, imports called through the IAT as 'dll!name')."""
        raise NotImplementedError

    def string_refs(self, text: str) -> dict[int, list[tuple[int, int | None]]]:
        """String address -> (site, function start) for each ASCII or UTF-16 copy of text."""
        raise NotImplementedError
