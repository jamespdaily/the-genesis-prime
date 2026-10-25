"""Runs one client function on Ghidra's p-code emulator.

The Windows x64 calling convention: the first four arguments go in RCX, RDX,
R8 and R9 when integers, or XMM0 to XMM3 when floats, by position. The result
is in RAX, or in XMM0 for a float. The emulator reads the client's own bytes
from the program, so a function may read its constant tables.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class Run:
    rax: int  # RAX after the function returns, unsigned 64-bit
    xmm0_low: int  # the low 64 bits of XMM0 after it returns; a float32 result is the low 32
    steps: int


class EmulationFailed(Exception):
    """The function called out, ran past max_steps or touched unmapped memory."""


def run_function(program, function_start: int, args: list[int | float], max_steps: int = 100_000) -> Run:
    """Each argument is an int (an integer register) or a float (an XMM
    register, passed as float32), by position."""
    raise NotImplementedError
