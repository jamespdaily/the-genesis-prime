"""Saves every name in the fact file into the Ghidra project.

Read-only by default: reports, for each record with a name, whether its
function exists and what it is called now. With GHIDRA_WRITE=1 it creates a
missing function, renames each one and saves the project. Run with the pinned
Python and the environment ghidra_env reads, while no query process holds the
project open.

Usage: python3 -I name_functions.py
"""

import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_facts  # noqa: E402
import ghidra_env  # noqa: E402
import ghidra_project  # noqa: E402

_ADDRESS_KEY = re.compile(r"0x14[0-9a-f]{7}")


@dataclass(frozen=True)
class Outcome:
    address: str
    name: str
    found: str | None  # the name the project held, or None when there was no function
    failed: str | None  # why it could not be named, or None


def name_pairs(records: dict[str, check_facts.Record]) -> list[tuple[int, str]]:
    """(address, name) for every record keyed by an address that has a name, sorted."""
    return sorted(
        (int(key, 16), r.name) for key, r in records.items() if r.name and _ADDRESS_KEY.fullmatch(key.lower())
    )


def apply_names(program, pairs: list[tuple[int, str]], write: bool) -> list[Outcome]:
    """Names each function in an open program; with write, inside one transaction."""
    import pyghidra
    from ghidra.app.cmd.disassemble import DisassembleCommand
    from ghidra.app.cmd.function import CreateFunctionCmd
    from ghidra.program.model.symbol import SourceType

    memory = program.getMemory()
    functions = program.getFunctionManager()
    listing = program.getListing()
    space = program.getAddressFactory().getDefaultAddressSpace()
    outcomes = []

    def name_one(address: int, name: str) -> Outcome:
        entry = space.getAddress(address)
        function = functions.getFunctionAt(entry)
        found = function.getName() if function is not None else None
        outcome = Outcome("0x%x" % address, name, found, None)
        if not write:
            return outcome
        if function is None:
            if not memory.contains(entry):
                return Outcome(outcome.address, name, found, "the address is outside every section")
            if listing.getInstructionAt(entry) is None and not DisassembleCommand(entry, None, True).applyTo(program):
                return Outcome(outcome.address, name, found, "no instruction could be made at the address")
            if not CreateFunctionCmd(name, entry, None, SourceType.USER_DEFINED).applyTo(program):
                return Outcome(outcome.address, name, found, "no function could be made at the address")
            function = functions.getFunctionAt(entry)
        try:
            function.setName(name, SourceType.USER_DEFINED)
        except Exception as error:  # a Java exception: a duplicate or an invalid name
            return Outcome(outcome.address, name, found, str(error))
        return outcome

    if write:
        with pyghidra.transaction(program, "Name the functions of the fact file"):
            outcomes = [name_one(address, name) for address, name in pairs]
    else:
        outcomes = [name_one(address, name) for address, name in pairs]
    return outcomes


def main() -> int:
    pairs = name_pairs(check_facts.load(check_facts.FACT_FILE))
    write = os.environ.get("GHIDRA_WRITE") == "1"
    opened = ghidra_project.open_project(ghidra_env.settings_from_env(os.environ), None)
    try:
        outcomes = apply_names(opened.program, pairs, write)
        if write:
            import pyghidra

            opened.program.save("Names from the fact file", pyghidra.task_monitor())
    finally:
        opened.close()
    failures = [o for o in outcomes if o.failed]
    in_place = sum(1 for o in outcomes if not o.failed and o.found == o.name)
    print(
        "%s %d, already in place %d, failed %d"
        % ("named" if write else "would name", len(outcomes) - len(failures) - in_place, in_place, len(failures))
    )
    for o in failures:
        print("%s %s: %s" % (o.address, o.name, o.failed))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
