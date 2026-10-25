"""Opens the analysed Ghidra project of the client, making it on first use.

The first open imports the client, applies the seed, runs Ghidra's default
analysis and saves the project. Every later open reads the saved project and
runs no analysis.
"""

from dataclasses import dataclass, field
from pathlib import Path

from ghidra_env import Settings


@dataclass
class SeedReport:
    lines: int
    created: int = 0
    already_present: int = 0
    failed: list[int] = field(default_factory=list)
    unmapped: list[int] = field(default_factory=list)

    def adds_up(self) -> bool:
        return self.created + self.already_present + len(self.failed) + len(self.unmapped) == self.lines


@dataclass
class Opened:
    program: object  # ghidra.program.model.listing.Program, held open until close()
    analysed_now: bool
    seed_report: SeedReport | None  # set only when analysed_now
    seconds: float

    def close(self) -> None:
        raise NotImplementedError


def open_project(settings: Settings, seed_path: Path | None) -> Opened:
    """Starts Ghidra through PyGhidra (once per process) and opens the project."""
    raise NotImplementedError


def apply_seed(program, lines: list[tuple[int, str, str]]) -> SeedReport:
    """Creates each seeded function and names it, before analysis runs."""
    raise NotImplementedError
