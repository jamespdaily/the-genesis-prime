"""Adds to the Ghidra project every switch case that Ghidra's analysis did not recover.

For each function Ghidra lists, jump_tables.read_function reads the switch tables from the client's own
bytes. A table whose distinct targets are not all among the flow references Ghidra holds at its jmp is
recovered by Ghidra's own switch override (Ghidra's ghidra_scripts/SwitchOverride.java): a COMPUTED_JUMP
reference from the jmp to each target, each target disassembled, JumpTable.writeOverride for the
function, CreateFunctionCmd.fixupFunctionBody so the case blocks join the function. The decompiler then
holds the cases, and `callers` and the saved C see them.

Read-only by default: reports the switches found, the ones agreeing with Ghidra, the ones it would
recover, the tables it could not read (with the reason) and other differences: a jmp Ghidra has no
instruction at, references Ghidra holds that the table does not, and a jump through a register that
Ghidra holds with no destination and read_function found no jmp for (what FindUnrecoveredSwitchesScript
lists, less the jumps through memory).
With GHIDRA_WRITE=1 it makes every change in one transaction and saves the project: a run that ends
before the save leaves the project as it was. A table whose target Ghidra cannot disassemble is
reported as failed and not written; any other error ends the run with nothing saved. Before the save it
tells decompiled.py which functions' bodies changed (decompiled.note_changed_bodies), so the next
`decompiled.py refresh` redoes them: run it after a write. A second write run recovers nothing.

It opens the project itself: it refuses while a query process holds it (`python3 -I query.py stop`).
Run with the pinned Python and the environment ghidra_env reads, as name_functions.py is.

Usage: python3 -I recover_switches.py          (GHIDRA_WRITE=1 to write)
"""

import os
import sys
from dataclasses import dataclass, field, replace

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import decompiled  # noqa: E402
import ghidra_env  # noqa: E402
import ghidra_project  # noqa: E402
import ghidra_query  # noqa: E402
import query  # noqa: E402
from client_pe import ClientPE  # noqa: E402
from jump_tables import JumpTable, read_function  # noqa: E402

SAVE_MESSAGE = "Recover the switches Ghidra missed"
SHOWN_TARGETS = 3


@dataclass(frozen=True)
class Change:
    function: int
    jmp: int
    targets: list[int]  # the table's distinct targets, ascending
    missing: list[int]  # those among them that Ghidra holds no reference for, ascending


@dataclass(frozen=True)
class Unreadable:
    function: int
    jmp: int
    reason: str


@dataclass(frozen=True)
class Difference:
    function: int
    jmp: int
    reason: str


@dataclass(frozen=True)
class Plan:
    found: int  # tables read
    changes: list[Change]
    agreeing: list[int]  # jmps whose table targets are all among Ghidra's references
    unreadable: list[Unreadable]
    differences: list[Difference]


@dataclass(frozen=True)
class Report:
    plan: Plan
    recovered: list[Change] | None  # None when nothing was written
    failed: list[tuple[Change, str]]
    unread: list[int] = field(default_factory=list)  # register jumps with no destination that no table was read for


def plan(tables: dict[int, list[JumpTable]], ghidra_targets: dict[int, set[int] | None]) -> Plan:
    """What each function's switch tables ask of the project. ghidra_targets maps every jmp to the
    addresses of the flow references Ghidra holds there, or None where Ghidra has no instruction."""
    found = 0
    changes, agreeing, unreadable, differences = [], [], [], []
    for function in sorted(tables):
        for table in tables[function]:
            if not table.found:
                unreadable.append(Unreadable(function, table.jmp, table.reason))
                continue
            found += 1
            held = ghidra_targets[table.jmp]
            if held is None:
                differences.append(Difference(function, table.jmp, "Ghidra has no instruction at the jmp"))
                continue
            wanted = sorted(set(table.targets))
            missing = [t for t in wanted if t not in held]
            if missing:
                changes.append(Change(function, table.jmp, wanted, missing))
            else:
                agreeing.append(table.jmp)
            extra = sorted(held - set(wanted))
            if extra:
                differences.append(
                    Difference(function, table.jmp, "Ghidra holds references the table does not: " + ", ".join("0x%x" % a for a in extra))
                )
    return Plan(found, changes, agreeing, unreadable, differences)


def _held_targets(opened, jmp: int) -> set[int] | None:
    """The flow references Ghidra holds at the jmp, as the query process's switch_targets answers them."""
    try:
        answer = ghidra_query.handle(opened, {"kind": "switch_targets", "jmp": "0x%x" % jmp})
    except ghidra_query.BadRequest:
        return None
    return {int(a, 16) for a in answer}


def read_tables(opened, pe: ClientPE, scope: set[int] | None) -> dict[int, list[JumpTable]]:
    """The tables of every function Ghidra lists (those in scope, when a scope is given)."""
    tables = {}
    for entry in sorted(int(a, 16) for a in ghidra_query.handle(opened, {"kind": "functions"})):
        if scope is not None and entry not in scope:
            continue
        read = read_function(pe, entry)
        if read:
            tables[entry] = read
    return tables


def plan_in(opened, pe: ClientPE, scope: set[int] | None = None) -> Plan:
    """The plan for the open project: read_tables against the references Ghidra holds."""
    tables = read_tables(opened, pe, scope)
    return plan(tables, {t.jmp: _held_targets(opened, t.jmp) for read in tables.values() for t in read})


def computed_jumps_without_destination(program) -> list[int]:
    """The jumps through a register that Ghidra holds with no flow reference that is not a fall-through,
    as FindUnrecoveredSwitchesScript finds them, less the jumps through memory, which are calls through
    a table of functions and not switches."""
    found = []
    for instruction in program.getListing().getInstructions(True):
        flow = instruction.getFlowType()
        if not (flow.isJump() and flow.isComputed()) or instruction.getRegister(0) is None:
            continue
        for reference in instruction.getReferencesFrom():
            reference_type = reference.getReferenceType()
            if reference_type.isFlow() and not reference_type.isFallthrough():
                break
        else:
            found.append(instruction.getAddress().getOffset())
    return found


def apply_changes(program, changes: list[Change]) -> tuple[list[Change], list[tuple[Change, str]]]:
    """Makes each change in one transaction, by Ghidra's own switch override (see the module's
    description). Returns the changes made, each with the function whose body now holds the cases, and
    the ones not made with the reason. A change whose target cannot be disassembled is skipped before
    anything of it is written; any other error rolls the whole transaction back and propagates."""
    import pyghidra
    from ghidra.app.cmd.disassemble import DisassembleCommand
    from ghidra.app.cmd.function import CreateFunctionCmd
    from ghidra.program.model.pcode import JumpTable as SwitchOverride
    from ghidra.program.model.symbol import RefType, SourceType
    from java.util import ArrayList

    listing = program.getListing()
    functions = program.getFunctionManager()
    space = program.getAddressFactory().getDefaultAddressSpace()
    recovered, failed = [], []
    with pyghidra.transaction(program, SAVE_MESSAGE):
        for change in changes:
            jmp = space.getAddress(change.jmp)
            instruction = listing.getInstructionAt(jmp)
            function = functions.getFunctionContaining(jmp)
            if instruction is None or function is None:
                failed.append((change, "Ghidra holds no instruction or no function at the jmp"))
                continue
            targets = [space.getAddress(t) for t in change.targets]
            unmade = [
                t for t in targets
                if listing.getInstructionAt(t) is None and not DisassembleCommand(t, None, True).applyTo(program)
            ]
            if unmade:
                failed.append((change, "no instruction could be made at 0x%x" % unmade[0].getOffset()))
                continue
            for target in targets:
                instruction.addOperandReference(0, target, RefType.COMPUTED_JUMP, SourceType.USER_DEFINED)
            destinations = ArrayList()
            for target in targets:
                destinations.add(target)
            SwitchOverride(jmp, destinations, True, 0).writeOverride(function)
            CreateFunctionCmd.fixupFunctionBody(program, function, pyghidra.task_monitor())
            recovered.append(replace(change, function=function.getEntryPoint().getOffset()))
    return recovered, failed


def run(env, write: bool, scope: set[int] | None = None) -> Report:
    """Reads the project and the client, and with write makes the changes (see the module's description).
    scope limits the functions read; only the tests pass one. Raises ghidra_env.WrongVersion,
    query.BadLock, ghidra_project.ProjectHeld, ghidra_project.ProjectMissing and decompiled.Refused."""
    settings = ghidra_env.settings_from_env(env)
    directory = decompiled.copy_directory(env) if write else None
    ghidra_project.refuse_while_held(env)
    pe = ClientPE(settings.client_exe)

    def work(opened) -> Report:
        found = plan_in(opened, pe, scope)
        recovered, failed = None, []
        if write:
            recovered, failed = apply_changes(opened.program, found.changes)
            if recovered:
                decompiled.note_changed_bodies(directory, [c.function for c in recovered])
        return Report(found, recovered, failed, _unread(opened, found, scope))

    return ghidra_project.work_on_existing(settings, work, SAVE_MESSAGE if write else None)


def _unread(opened, found: Plan, scope: set[int] | None) -> list[int]:
    """The register jumps without a destination that no table was read for; none when a scope limits the read."""
    if scope is not None:
        return []
    read = {c.jmp for c in found.changes} | set(found.agreeing) | {u.jmp for u in found.unreadable} | {d.jmp for d in found.differences}
    return [a for a in computed_jumps_without_destination(opened.program) if a not in read]


def _targets_line(change: Change) -> str:
    count = len(change.missing)
    if count == 1:
        return "1 missing target: 0x%x" % change.missing[0]
    shown = ", ".join("0x%x" % t for t in change.missing[:SHOWN_TARGETS])
    return "%d missing targets, the first %s" % (count, shown)


def format_report(report: Report, write: bool) -> str:
    """The report a run prints: one line of counts, then a line for each change, failure, unreadable table
    and difference."""
    plan_ = report.plan
    differences = len(plan_.differences) + len(report.unread)
    if write:
        made = "recovered %d, failed %d" % (len(report.recovered or []), len(report.failed))
    else:
        made = "would recover %d" % len(plan_.changes)
    lines = [
        "switches found %d: agreeing %d, %s, unreadable %d, other differences %d"
        % (plan_.found, len(plan_.agreeing), made, len(plan_.unreadable), differences)
    ]
    for change in (report.recovered or []) if write else plan_.changes:
        lines.append("%s 0x%x in 0x%x: %s" % ("recovered" if write else "would recover", change.jmp, change.function, _targets_line(change)))
    for change, reason in report.failed:
        lines.append("failed 0x%x in 0x%x: %s" % (change.jmp, change.function, reason))
    for entry in plan_.unreadable:
        lines.append("unreadable 0x%x in 0x%x: %s" % (entry.jmp, entry.function, entry.reason))
    for difference in plan_.differences:
        lines.append("difference 0x%x in 0x%x: %s" % (difference.jmp, difference.function, difference.reason))
    for jmp in report.unread:
        lines.append("difference 0x%x: Ghidra holds a jump through a register with no destination, and no switch table was read for it" % jmp)
    return "\n".join(lines)


def main(env=os.environ) -> int:
    write = env.get("GHIDRA_WRITE") == "1"
    try:
        report = run(env, write)
    except (
        ghidra_env.WrongVersion, query.BadLock, ghidra_project.ProjectHeld, ghidra_project.ProjectMissing, decompiled.Refused
    ) as error:
        sys.exit("recover_switches: %s" % error)
    print(format_report(report, write))
    if report.recovered:
        print("changed functions: run `python3 -I decompiled.py refresh`")
    return 1 if report.failed else 0


if __name__ == "__main__":
    sys.exit(main())
