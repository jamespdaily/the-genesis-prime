"""Runs one client function on Ghidra's p-code emulator.

The Windows x64 calling convention: integer arguments in RCX, RDX, R8 and R9,
the result in RAX. The emulator reads the client's own bytes from the
program, so a function may read its constant tables.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class Run:
    result: int  # RAX after the function returns, as an unsigned 64-bit value
    steps: int


class EmulationFailed(Exception):
    """The function called out, ran past max_steps or touched unmapped memory."""


def run_function(program, function_start: int, args: list[int], max_steps: int = 100_000) -> Run:
    raise NotImplementedError
