"""Opens the analysed Ghidra project of the client, making it on first use.

The first open imports the client, applies the seed, runs Ghidra's default
analysis and saves the project; it needs a seed file, or UNSEEDED said outright,
and raises SeedRequired with neither, before anything is made. Every later open
reads the saved project and runs no analysis. open_existing never makes one.
"""

import time
from dataclasses import dataclass, field
from pathlib import Path

import seed
from ghidra_env import Settings

PROJECT_NAME = "WildStar"
PROGRAM_NAME = "WildStar64.exe"


class SeedRequired(Exception):
    """A first import was asked for with no seed file and no UNSEEDED."""


class ProjectMissing(Exception):
    """open_existing found no project to open; the message names the folder."""


class Unseeded:
    """The explicit choice to import and analyse the client with no seed."""

    def __repr__(self) -> str:
        return "UNSEEDED"


UNSEEDED = Unseeded()


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
    project: object = None
    consumer: object = None

    def close(self) -> None:
        self.program.release(self.consumer)
        self.project.close()


def _consume(project):
    import pyghidra

    return pyghidra.consume_program(project, "/" + PROGRAM_NAME)


def open_project(settings: Settings, seed_path: "Path | Unseeded | None") -> Opened:
    """Starts Ghidra through PyGhidra (once per process) and opens the project, making
    it from the seed file, or from none when seed_path is UNSEEDED, when it does not
    exist. Raises SeedRequired, having made nothing, when it must be made and seed_path is None."""
    if seed_path is None and not (settings.project_dir / (PROJECT_NAME + ".gpr")).is_file():
        raise SeedRequired(
            "there is no project in %s; its first import needs a seed file, or UNSEEDED said outright" % settings.project_dir
        )
    return _open(settings, seed_path, make=True)


def open_existing(settings: Settings) -> Opened:
    """Opens the project that exists; raises ProjectMissing, having made nothing, when there is none."""
    if not (settings.project_dir / (PROJECT_NAME + ".gpr")).is_file():
        raise ProjectMissing("there is no project in %s; it is made by the first start of ghidra_query.py" % settings.project_dir)
    return _open(settings, None, make=False)


def _open(settings: Settings, seed_path: "Path | Unseeded | None", make: bool) -> Opened:
    started = time.monotonic()
    import pyghidra

    if not pyghidra.started():
        pyghidra.start(install_dir=settings.ghidra_dir)
    from ghidra.program.util import GhidraProgramUtilities

    settings.project_dir.mkdir(parents=True, exist_ok=True)
    project = pyghidra.open_project(settings.project_dir, PROJECT_NAME, create=make)
    try:
        report = None
        if project.getProjectData().getFile("/" + PROGRAM_NAME) is None:
            if not make or seed_path is None:
                raise SeedRequired(
                    "the project in %s holds no program, and its import needs a seed file or UNSEEDED" % settings.project_dir
                )
            report = _import_and_analyse(project, settings, seed_path)
        program, consumer = _consume(project)
    except BaseException:
        project.close()
        raise
    if not GhidraProgramUtilities.isAnalyzed(program):
        program.release(consumer)
        project.close()
        raise RuntimeError(
            "the project in %s holds an import that was never analysed; delete the directory to start again"
            % settings.project_dir
        )
    return Opened(program, report is not None, report, time.monotonic() - started, project, consumer)


def _import_and_analyse(project, settings: Settings, seed_path: "Path | Unseeded") -> SeedReport:
    """Import, seed, analyse, save; the project is reopened from disk afterwards."""
    import pyghidra

    loader = pyghidra.program_loader().project(project).source(str(settings.client_exe)).projectFolderPath("/")
    with loader.load() as results:
        results.save(pyghidra.task_monitor())
    program, consumer = _consume(project)
    try:
        lines = [] if seed_path is UNSEEDED else seed.read_seed(seed_path)
        report = apply_seed(program, lines)
        pyghidra.analyze(program)
        program.save("Analysed", pyghidra.task_monitor())
    finally:
        program.release(consumer)
    return report


def apply_seed(program, lines: list[tuple[int, str, str]]) -> SeedReport:
    """Creates each seeded function that does not exist yet and names it, before analysis runs.
    A function that already exists keeps its name, and counts as already present."""
    import pyghidra
    from ghidra.app.cmd.disassemble import DisassembleCommand
    from ghidra.app.cmd.function import CreateFunctionCmd
    from ghidra.program.model.symbol import SourceType

    report = SeedReport(len(lines))
    memory = program.getMemory()
    functions = program.getFunctionManager()
    listing = program.getListing()
    space = program.getAddressFactory().getDefaultAddressSpace()
    with pyghidra.transaction(program, "Apply the seed"):
        for address, _kind, name in lines:
            entry = space.getAddress(address)
            if not memory.contains(entry):
                report.unmapped.append(address)
            elif functions.getFunctionAt(entry) is not None:
                report.already_present += 1
            elif (
                listing.getInstructionAt(entry) is not None or DisassembleCommand(entry, None, True).applyTo(program)
            ) and CreateFunctionCmd(name, entry, None, SourceType.IMPORTED).applyTo(program):
                report.created += 1
            else:
                report.failed.append(address)
    return report
