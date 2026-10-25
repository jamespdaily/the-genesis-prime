"""name_functions: the fact file's names, saved into the Ghidra project.

Expected values come from the docstrings of name_functions.py: name_pairs gives (address,
name) for each record keyed by an address that has a name, sorted; apply_names
is read-only unless told to write, and reports for each pair the name the
project held and why it could not be named. Planted: the records, and the
names ("genesis_test_name_<hex>") given to three functions the project already
holds.

The integration tests run only when GENESIS_INTEGRATION=1 (see check_support),
on a temporary copy of the project at $GENESIS_GHIDRA_PROJECT_DIR, each Ghidra
run in its own process under the pinned Python ($GENESIS_PYGHIDRA_PYTHON), as
the query process is. They assume Outcome.address is the 0x-prefixed
lower-case hex of the function's entry, the form the fact file keys use, and
that apply_names does not save the project (the driver saves after a write).
Run: GENESIS_INTEGRATION=1 python3 -I test_name_functions.py
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_support as cs  # noqa: E402
import name_functions  # noqa: E402
from check_facts import Record  # noqa: E402
from check_support import hx  # noqa: E402

PLANTED_LOW = "0x140001010"
PLANTED_HIGH = "0x1408296a3"
PLANTED_NO_NAME = "0x140002020"


def record(key: str, name: str | None) -> Record:
    return Record(key=key, statement="S", proof="P", grade="guess", gap="G", name=name)


class NamePairsTest(unittest.TestCase):
    def test_a_record_keyed_by_an_address_with_a_name_gives_its_address_and_name(self):
        pairs = name_functions.name_pairs({PLANTED_LOW: record(PLANTED_LOW, "CastSpell")})
        self.assertEqual(pairs, [(int(PLANTED_LOW, 16), "CastSpell")])

    def test_pairs_are_sorted_by_address_whatever_the_order_of_the_records(self):
        records = {
            PLANTED_HIGH: record(PLANTED_HIGH, "Later"),
            PLANTED_LOW: record(PLANTED_LOW, "Earlier"),
        }
        self.assertEqual(
            name_functions.name_pairs(records),
            [(int(PLANTED_LOW, 16), "Earlier"), (int(PLANTED_HIGH, 16), "Later")],
        )

    def test_a_record_keyed_by_something_else_is_left_out(self):
        # records keyed by something else are left out, even with a name
        records = {
            "Spell4.damageScale": record("Spell4.damageScale", "NotAFunction"),
            "CMSG_EXAMPLE": record("CMSG_EXAMPLE", "AlsoNot"),
            PLANTED_LOW: record(PLANTED_LOW, "Kept"),
        }
        self.assertEqual(name_functions.name_pairs(records), [(int(PLANTED_LOW, 16), "Kept")])

    def test_a_record_keyed_by_an_address_without_a_name_is_left_out(self):
        # records without a name are left out
        records = {PLANTED_NO_NAME: record(PLANTED_NO_NAME, None), PLANTED_LOW: record(PLANTED_LOW, "Kept")}
        self.assertEqual(name_functions.name_pairs(records), [(int(PLANTED_LOW, 16), "Kept")])

    def test_no_records_give_no_pairs(self):
        self.assertEqual(name_functions.name_pairs({}), [])


# Run by the pinned Python with the environment of the query process. argv:
# scripts directory, result file, then a JSON request:
#   {"pick": n}                      -> functions: n [address, name] pairs the project holds
#   {"pairs": [[address, name]], "write": bool}
#                                    -> outcomes, and names: the name each address holds afterwards
DRIVER = r"""
import dataclasses, json, os, sys
sys.path.insert(0, sys.argv[1])
import ghidra_env, ghidra_project, name_functions
import pyghidra

request = json.loads(sys.argv[3])
opened = ghidra_project.open_project(ghidra_env.settings_from_env(os.environ), None)
try:
    program = opened.program
    functions = program.getFunctionManager()
    space = program.getAddressFactory().getDefaultAddressSpace()
    result = {}
    if "pick" in request:
        found = []
        for function in functions.getFunctions(True):
            found.append(["0x%x" % function.getEntryPoint().getOffset(), function.getName()])
            if len(found) >= request["pick"] + 50:
                break
        result["functions"] = found[50:]
    else:
        pairs = [(a, n) for a, n in request["pairs"]]
        outcomes = name_functions.apply_names(program, pairs, request["write"])
        if request["write"]:
            program.save("Names", pyghidra.task_monitor())
        result["outcomes"] = [dataclasses.asdict(o) for o in outcomes]
        result["names"] = {}
        for address, _name in pairs:
            function = functions.getFunctionAt(space.getAddress(address))
            result["names"]["0x%x" % address] = function.getName() if function else None
finally:
    opened.close()
with open(sys.argv[2], "w") as out:
    json.dump(result, out)
"""


@cs.integration_only
class NamesInGhidraTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._root = Path(tempfile.mkdtemp(prefix="genesis-names-test-"))
        cls.project = cls._root / "project"
        shutil.copytree(cs.require_env("GENESIS_GHIDRA_PROJECT_DIR"), cls.project)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls._root, ignore_errors=True)

    def drive(self, request: dict) -> dict:
        result_file = self._root / "result.json"
        result_file.unlink(missing_ok=True)
        completed = subprocess.run(
            [cs.require_env("GENESIS_PYGHIDRA_PYTHON"), "-I", "-c", DRIVER, str(cs.SCRIPTS), str(result_file), json.dumps(request)],
            env=cs.query_environment(self.project),
            cwd=self.project,
            capture_output=True,
            text=True,
            timeout=900,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return json.loads(result_file.read_text())

    def held(self) -> dict[str, str]:
        """Three functions the project holds, address -> the name each has now."""
        return {address: name for address, name in self.drive({"pick": 3})["functions"]}

    def picked_pairs(self) -> list[tuple[int, str]]:
        """The same three, each with a name no function has yet."""
        return [(int(address, 16), "genesis_test_name_%x" % int(address, 16)) for address in self.held()]

    def test_a_read_only_run_reports_no_failure_and_changes_no_name(self):
        before = self.held()
        pairs = self.picked_pairs()
        run = self.drive({"pairs": pairs, "write": False})
        self.assertEqual([o["failed"] for o in run["outcomes"]], [None] * len(pairs))
        self.assertEqual({o["address"]: o["found"] for o in run["outcomes"]}, before)  # found: the name held now
        self.assertEqual(run["names"], before)  # nothing renamed in the run
        self.assertEqual(self.held(), before)  # nor on a fresh open

    def test_a_write_run_renames_and_a_later_read_only_run_finds_each_name_in_place(self):
        pairs = self.picked_pairs()
        wanted = {hx(a): n for a, n in pairs}
        written = self.drive({"pairs": pairs, "write": True})
        self.assertEqual([o["failed"] for o in written["outcomes"]], [None] * len(pairs))
        self.assertEqual(written["names"], wanted)
        later = self.drive({"pairs": pairs, "write": False})
        self.assertEqual([o["failed"] for o in later["outcomes"]], [None] * len(pairs))
        self.assertEqual({o["address"]: o["found"] for o in later["outcomes"]}, wanted)
        self.assertEqual(self.held(), wanted)


if __name__ == "__main__":
    unittest.main(verbosity=2)
