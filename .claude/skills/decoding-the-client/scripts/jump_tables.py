"""Reads MSVC x64 switch tables from the client's bytes, with no analyser.

Pattern: cmp IDX, N / ja DEFAULT, lea BASE, [image base], an optional byte
index table, mov R32, [BASE + IDX*4 + table], add R, BASE, jmp R. Anything
else is reported as not found, with the reason; nothing is guessed.
"""

from dataclasses import dataclass

from client_pe import ClientPE


@dataclass(frozen=True)
class JumpTable:
    jmp: int
    found: bool
    reason: str | None
    case_count: int
    default: int | None
    targets: list[int]  # one per switch value, in order


def read_function(pe: ClientPE, function_start: int) -> list[JumpTable]:
    """Every indirect `jmp REG64` in the function's .pdata ranges, read."""
    raise NotImplementedError
