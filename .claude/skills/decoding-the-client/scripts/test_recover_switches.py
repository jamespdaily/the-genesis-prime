"""recover_switches.py: what it plans from the client's switch tables and Ghidra's references, and what a
recovery in a project does.

The plan tests build the shapes jump_tables.read_function returns, with planted addresses, so they need
neither Ghidra nor the client. The client test reads HandleWorldMessage's table from WildStar64.exe
(SHA-256 565c2fa1...fe0b10) as the fact file records it: function 0x1403ec6a0, jmp 0x1403ec719, 636
distinct targets (record 0x1403ec6a0, cited in test_jump_tables.py), among them 0x1403f103d, the case of
message 0x92 that calls GetCamp 0x14054f210 (records 0x14054f190 and opcode.0x92). The tests under
GENESIS_INTEGRATION=1 run the recovery on a copy of the shared project, in a pinned-Python subprocess
as the real run is, and read the result through the query process.
Run: python3 -I test_recover_switches.py   (GENESIS_INTEGRATION=1 adds the real-project tests)
"""

import hashlib
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
import recover_switches  # noqa: E402
from client_pe import ClientPE  # noqa: E402
from jump_tables import JumpTable, read_function  # noqa: E402
from query_client import open_query_client  # noqa: E402

PLANTED_FUNCTION = 0x140000100
PLANTED_OTHER_FUNCTION = 0x140000900
PLANTED_JMP = 0x140000140
PLANTED_SECOND_JMP = 0x140000180
PLANTED_JMP_OF_OTHER = 0x140000940
PLANTED_DEFAULT = 0x1400001F0
PLANTED_A = 0x140000200
PLANTED_B = 0x140000210
PLANTED_C = 0x140000220
PLANTED_EXTRA = 0x140000230


def table(jmp: int, targets: list[int]) -> JumpTable:
    return JumpTable(jmp, True, None, len(targets), PLANTED_DEFAULT, targets)


def unreadable(jmp: int, reason: str) -> JumpTable:
    return JumpTable(jmp, False, reason, 0, None, [])


class PlanTest(unittest.TestCase):
    """Item 1: what a table and Ghidra's references make of a jmp."""

    def test_a_table_whose_targets_are_all_among_ghidras_references_gives_no_change(self):
        # a target several cases share is one target
        plan = recover_switches.plan(
            {PLANTED_FUNCTION: [table(PLANTED_JMP, [PLANTED_A, PLANTED_B, PLANTED_A, PLANTED_C])]},
            {PLANTED_JMP: {PLANTED_A, PLANTED_B, PLANTED_C}},
        )
        self.assertEqual(plan.changes, [])
        self.assertEqual(plan.agreeing, [PLANTED_JMP])
        self.assertEqual(plan.unreadable, [])
        self.assertEqual(plan.differences, [])

    def test_a_table_with_missing_targets_gives_a_change_listing_exactly_those(self):
        plan = recover_switches.plan(
            {PLANTED_FUNCTION: [table(PLANTED_JMP, [PLANTED_C, PLANTED_A, PLANTED_B, PLANTED_A])]},
            {PLANTED_JMP: {PLANTED_A}},
        )
        (change,) = plan.changes
        self.assertEqual((change.function, change.jmp), (PLANTED_FUNCTION, PLANTED_JMP))
        self.assertEqual(change.missing, [PLANTED_B, PLANTED_C])
        self.assertEqual(change.targets, [PLANTED_A, PLANTED_B, PLANTED_C])
        self.assertEqual(plan.agreeing, [])

    def test_a_jmp_with_no_reference_in_ghidra_has_all_its_distinct_targets_missing(self):
        plan = recover_switches.plan(
            {PLANTED_FUNCTION: [table(PLANTED_JMP, [PLANTED_B, PLANTED_A, PLANTED_B])]}, {PLANTED_JMP: set()}
        )
        (change,) = plan.changes
        self.assertEqual(change.missing, [PLANTED_A, PLANTED_B])

    def test_an_unreadable_table_is_reported_with_its_reason_and_gives_no_change(self):
        plan = recover_switches.plan(
            {PLANTED_FUNCTION: [unreadable(PLANTED_JMP, "no `cmp IDX, imm` found for the index register")]},
            {PLANTED_JMP: set()},
        )
        self.assertEqual(plan.changes, [])
        self.assertEqual(plan.agreeing, [])
        (entry,) = plan.unreadable
        self.assertEqual((entry.function, entry.jmp), (PLANTED_FUNCTION, PLANTED_JMP))
        self.assertEqual(entry.reason, "no `cmp IDX, imm` found for the index register")

    def test_a_jmp_ghidra_has_no_instruction_at_is_a_difference_with_its_reason_and_gives_no_change(self):
        plan = recover_switches.plan({PLANTED_FUNCTION: [table(PLANTED_JMP, [PLANTED_A])]}, {PLANTED_JMP: None})
        self.assertEqual(plan.changes, [])
        self.assertEqual(plan.agreeing, [])
        (difference,) = plan.differences
        self.assertEqual((difference.function, difference.jmp), (PLANTED_FUNCTION, PLANTED_JMP))
        self.assertIn("no instruction", difference.reason)

    def test_references_in_ghidra_that_the_table_does_not_hold_are_a_difference_naming_them(self):
        plan = recover_switches.plan(
            {PLANTED_FUNCTION: [table(PLANTED_JMP, [PLANTED_A])]}, {PLANTED_JMP: {PLANTED_A, PLANTED_EXTRA}}
        )
        self.assertEqual(plan.changes, [])
        self.assertEqual(plan.agreeing, [PLANTED_JMP])
        (difference,) = plan.differences
        self.assertEqual(difference.jmp, PLANTED_JMP)
        self.assertIn("0x%x" % PLANTED_EXTRA, difference.reason)
        self.assertNotIn("0x%x" % PLANTED_A, difference.reason)

    def test_every_jmp_of_every_function_is_judged_on_its_own(self):
        plan = recover_switches.plan(
            {
                PLANTED_FUNCTION: [
                    table(PLANTED_JMP, [PLANTED_A, PLANTED_B]),
                    table(PLANTED_SECOND_JMP, [PLANTED_C]),
                ],
                PLANTED_OTHER_FUNCTION: [unreadable(PLANTED_JMP_OF_OTHER, "not a switch")],
            },
            {PLANTED_JMP: {PLANTED_A, PLANTED_B}, PLANTED_SECOND_JMP: set(), PLANTED_JMP_OF_OTHER: set()},
        )
        self.assertEqual(plan.agreeing, [PLANTED_JMP])
        self.assertEqual([c.jmp for c in plan.changes], [PLANTED_SECOND_JMP])
        self.assertEqual([u.jmp for u in plan.unreadable], [PLANTED_JMP_OF_OTHER])


class ReportTest(unittest.TestCase):
    def test_the_report_counts_the_switches_found_agreeing_to_recover_unreadable_and_other_differences(self):
        plan = recover_switches.plan(
            {
                PLANTED_FUNCTION: [
                    table(PLANTED_JMP, [PLANTED_A]),
                    table(PLANTED_SECOND_JMP, [PLANTED_B, PLANTED_C]),
                ],
                PLANTED_OTHER_FUNCTION: [unreadable(PLANTED_JMP_OF_OTHER, "not a switch")],
            },
            {PLANTED_JMP: {PLANTED_A, PLANTED_EXTRA}, PLANTED_SECOND_JMP: {PLANTED_B}, PLANTED_JMP_OF_OTHER: set()},
        )
        lines = recover_switches.format_report(recover_switches.Report(plan, None, []), write=False).splitlines()
        self.assertEqual(
            lines[0], "switches found 2: agreeing 1, would recover 1, unreadable 1, other differences 1"
        )
        self.assertIn("would recover 0x%x in 0x%x: 1 missing target: 0x%x" % (PLANTED_SECOND_JMP, PLANTED_FUNCTION, PLANTED_C), lines)
        self.assertIn("unreadable 0x%x in 0x%x: not a switch" % (PLANTED_JMP_OF_OTHER, PLANTED_OTHER_FUNCTION), lines)

    def test_a_written_report_counts_what_was_recovered_and_what_could_not_be(self):
        plan = recover_switches.plan(
            {PLANTED_FUNCTION: [table(PLANTED_JMP, [PLANTED_A]), table(PLANTED_SECOND_JMP, [PLANTED_B])]},
            {PLANTED_JMP: set(), PLANTED_SECOND_JMP: set()},
        )
        first, second = plan.changes
        report = recover_switches.Report(plan, [first], [(second, "the bytes at 0x%x decode to no instruction" % PLANTED_B)])
        text = recover_switches.format_report(report, write=True)
        self.assertEqual(text.splitlines()[0], "switches found 2: agreeing 0, recovered 1, failed 1, unreadable 0, other differences 0")
        self.assertIn("failed 0x%x in 0x%x: the bytes at 0x%x decode to no instruction" % (PLANTED_SECOND_JMP, PLANTED_FUNCTION, PLANTED_B), text)


@cs.needs_client
class PlanOnTheClientTest(unittest.TestCase):
    """Item 2."""

    def test_the_world_message_switch_with_no_references_gives_a_change_of_636_distinct_targets_with_the_0x92_case(self):
        pe = ClientPE(cs.client_exe())
        tables = {cs.FN_BIG_SWITCH: read_function(pe, cs.FN_BIG_SWITCH)}
        plan = recover_switches.plan(tables, {t.jmp: set() for t in tables[cs.FN_BIG_SWITCH]})
        (change,) = plan.changes
        self.assertEqual(change.jmp, cs.JMP_BIG_SWITCH)
        self.assertEqual(change.function, cs.FN_BIG_SWITCH)
        self.assertEqual(len(change.missing), 636)
        self.assertEqual(len(change.targets), 636)
        self.assertIn(0x1403F103D, change.missing)
        self.assertEqual(plan.unreadable, [])


# ---------------------------------------------------------------- the real project

GET_CAMP = 0x14054F210
SCOPE = {cs.FN_BIG_SWITCH, cs.FN_CONTROL_SWITCH}

RECOVER_SCRIPT = r"""
import json, os, sys
sys.path.insert(0, %(scripts)r)
import recover_switches
report = recover_switches.run(os.environ, write=%(write)r, scope=%(scope)r)
print(json.dumps({
    "recovered": [c.jmp for c in report.recovered or []],
    "failed": [c.jmp for c, _reason in report.failed],
    "changes": [c.jmp for c in report.plan.changes],
    "agreeing": report.plan.agreeing,
    "unreadable": [u.jmp for u in report.plan.unreadable],
}))
"""

# opens the project as the real run does, makes the whole change in its transaction, then ends the
# process as a kill would, after the transaction and before the save
KILLED_SCRIPT = r"""
import os, sys
sys.path.insert(0, %(scripts)r)
import ghidra_env, ghidra_project, recover_switches
from client_pe import ClientPE
settings = ghidra_env.settings_from_env(os.environ)
def work(opened):
    changes = recover_switches.plan_in(opened, ClientPE(settings.client_exe), %(scope)r).changes
    assert changes
    recover_switches.apply_changes(opened.program, changes)
    os._exit(9)
ghidra_project.work_on_existing(settings, work, "never saved")
"""


# opens the project as the real run does and applies one change made by hand, to the world switch's jmp
# with the targets given; reports what apply_changes returned or raised and whether the jmp's references
# and the functions' bodies are as they were, all in the same open program
CHANGE_SCRIPT = r"""
import json, os, sys
sys.path.insert(0, %(scripts)r)
import ghidra_env, ghidra_project, recover_switches
from recover_switches import Change
settings = ghidra_env.settings_from_env(os.environ)
def work(opened):
    program = opened.program
    space = program.getAddressFactory().getDefaultAddressSpace()
    instruction = program.getListing().getInstructionAt(space.getAddress(%(jmp)d))
    functions = program.getFunctionManager()
    def state():
        references = sorted(str(r.getToAddress()) for r in instruction.getReferencesFrom())
        bodies = [str(f.getBody()) for f in functions.getFunctions(True)]
        return references, bodies
    before = state()
    change = Change(%(function)d, %(jmp)d, %(targets)r, %(targets)r)
    recovered, failed, raised = [], [], None
    try:
        recovered, failed = recover_switches.apply_changes(program, [change])
    except recover_switches.RecoveryFailed as error:
        raised = str(error)
    return {
        "recovered": [c.jmp for c in recovered],
        "failed": [[c.jmp, reason] for c, reason in failed],
        "raised": raised,
        "unchanged": state() == before,
    }
print(json.dumps(ghidra_project.work_on_existing(settings, work, None)))
"""


def run_in_ghidra(project_dir: Path, decompiled_dir: Path, code: str, write: bool = True) -> subprocess.CompletedProcess:
    extra = {"GENESIS_DECOMPILED_DIR": str(decompiled_dir)}
    if write:
        extra["GHIDRA_WRITE"] = "1"
    return cs.run_in_ghidra(project_dir, code, extra)


def recover(project_dir: Path, decompiled_dir: Path, write: bool = True) -> dict:
    code = RECOVER_SCRIPT % {"scripts": str(cs.SCRIPTS), "write": write, "scope": SCOPE}
    done = run_in_ghidra(project_dir, decompiled_dir, code, write)
    assert done.returncode == 0, done.stderr
    return json.loads(done.stdout.strip().splitlines()[-1])


def project_digest(project_dir: Path) -> str:
    """The sha256 over the program's saved database files (db.<n>.gbf), by path: a save writes a new one."""
    digest = hashlib.sha256()
    for path in sorted((project_dir / "WildStar.rep" / "idata").rglob("*.gbf")):
        if path.is_file():
            digest.update(str(path.relative_to(project_dir)).encode())
            digest.update(path.read_bytes())
    return digest.hexdigest()


@cs.integration_only
class RealRecoveryTest(unittest.TestCase):
    """Items 4 and the failure table, on copies of the shared project."""

    @classmethod
    def setUpClass(cls):
        cls.root = Path(tempfile.mkdtemp(prefix="genesis-recover-test-"))
        cls.addClassCleanup(shutil.rmtree, cls.root, True)
        cls.project_dir = cls.root / "project"
        cls.killed_dir = cls.root / "killed"
        shutil.copytree(cs.seeded_project().project_dir, cls.project_dir)
        shutil.copytree(cs.seeded_project().project_dir, cls.killed_dir)
        cls.decompiled_dir = cls.root / "decompiled"
        cls.before = project_digest(cls.project_dir)
        cls.dry = recover(cls.project_dir, cls.decompiled_dir, write=False)
        cls.after_dry = project_digest(cls.project_dir)
        cls.dry_noted = (cls.decompiled_dir / "changed_bodies.json").exists()
        cls.first = recover(cls.project_dir, cls.decompiled_dir)
        cls.second = recover(cls.project_dir, cls.decompiled_dir)
        client = open_query_client(cs.query_environment(cls.project_dir))
        try:
            cls.targets = client.answer("switch_targets", jmp=cs.hx(cs.JMP_BIG_SWITCH))
            cls.callers = client.answer("callers", function=cs.hx(GET_CAMP))
            cls.c = client.answer("decompile", function=cs.hx(cs.FN_BIG_SWITCH), timeout_s=600, timeout=700)["c"]
        finally:
            client.close()

    def test_a_run_without_write_plans_the_world_switch_and_changes_nothing(self):
        self.assertEqual(self.dry["changes"], [cs.JMP_BIG_SWITCH])
        self.assertEqual(self.dry["recovered"], [])
        self.assertEqual(self.after_dry, self.before)
        self.assertFalse(self.dry_noted)

    def test_the_first_write_run_recovers_the_world_switch(self):
        self.assertEqual(self.first["recovered"], [cs.JMP_BIG_SWITCH])
        self.assertEqual(self.first["failed"], [])

    def test_the_second_write_run_recovers_nothing(self):
        self.assertEqual(self.second["recovered"], [])
        self.assertEqual(self.second["changes"], [])
        self.assertIn(cs.JMP_BIG_SWITCH, self.second["agreeing"])

    def test_ghidras_references_at_the_jmp_are_the_tables_636_distinct_targets(self):
        table = [t for t in read_function(cs.client_pe(), cs.FN_BIG_SWITCH) if t.jmp == cs.JMP_BIG_SWITCH][0]
        self.assertEqual(self.targets, [cs.hx(t) for t in sorted(set(table.targets))])

    def test_the_decompile_of_the_world_handler_holds_the_call_to_get_camp(self):
        # the shared project is seeded, not named by the fact file: the callee is GetCamp or FUN_14054f210
        self.assertRegex(self.c, r"\b(GetCamp|FUN_14054f210)\(")

    def test_callers_of_get_camp_lists_the_world_handler(self):
        self.assertIn(cs.hx(cs.FN_BIG_SWITCH), [caller["function"] for caller in self.callers])

    def test_the_recovery_notes_the_changed_function_for_the_next_refresh(self):
        noted = json.loads((self.decompiled_dir / "changed_bodies.json").read_text())["functions"]
        self.assertEqual(noted, [cs.hx(cs.FN_BIG_SWITCH)])

    def test_a_run_killed_after_the_changes_and_before_the_save_leaves_the_saved_project_unchanged_and_the_next_run_recovers_the_switch(self):
        # the transaction has committed in the open program when the process ends; only the save is missing
        before = project_digest(self.killed_dir)
        decompiled_dir = self.root / "killed-decompiled"
        code = KILLED_SCRIPT % {"scripts": str(cs.SCRIPTS), "scope": SCOPE}
        done = run_in_ghidra(self.killed_dir, decompiled_dir, code)
        self.assertEqual(done.returncode, 9, done.stderr)
        self.assertEqual(project_digest(self.killed_dir), before)
        self.assertEqual(recover(self.killed_dir, decompiled_dir)["recovered"], [cs.JMP_BIG_SWITCH])


def apply_by_hand(project_dir: Path, targets: list[int]) -> dict:
    code = CHANGE_SCRIPT % {
        "scripts": str(cs.SCRIPTS), "function": cs.FN_BIG_SWITCH, "jmp": cs.JMP_BIG_SWITCH, "targets": targets
    }
    done = cs.run_in_ghidra(project_dir, code)
    assert done.returncode == 0, done.stderr
    return json.loads(done.stdout.strip().splitlines()[-1])


@cs.integration_only
class RealRefusedChangeTest(unittest.TestCase):
    """The failure table's rows for a change Ghidra cannot make, each on its own copy of the shared project."""

    @classmethod
    def setUpClass(cls):
        cls.root = Path(tempfile.mkdtemp(prefix="genesis-recover-refused-"))
        cls.addClassCleanup(shutil.rmtree, cls.root, True)
        cls.inside = cls.root / "inside"
        cls.other = cls.root / "other"
        shutil.copytree(cs.seeded_project().project_dir, cls.inside)
        shutil.copytree(cs.seeded_project().project_dir, cls.other)
        # the byte after the jmp's first is inside the jmp instruction: aligned, executable, and no
        # instruction can start there, though DisassembleCommand.applyTo answers true for it
        cls.inside_result = apply_by_hand(cls.inside, [cs.JMP_BIG_SWITCH + 1])
        # the entry of another function holds an instruction, but the function's body cannot join this one's
        cls.other_result = apply_by_hand(cls.other, [cs.FN_CONTROL_SWITCH])

    def test_a_target_inside_an_existing_instruction_is_reported_failed_with_nothing_recovered_and_no_reference_written(self):
        self.assertEqual(self.inside_result["recovered"], [])
        ((jmp, reason),) = self.inside_result["failed"]
        self.assertEqual(jmp, cs.JMP_BIG_SWITCH)
        self.assertIn("0x%x" % (cs.JMP_BIG_SWITCH + 1), reason)
        self.assertIsNone(self.inside_result["raised"])
        self.assertTrue(self.inside_result["unchanged"])

    def test_a_target_the_functions_body_cannot_hold_raises_and_the_transaction_leaves_the_program_as_it_was(self):
        self.assertEqual(self.other_result["recovered"], [])
        self.assertEqual(self.other_result["failed"], [])
        self.assertIn("0x%x" % cs.FN_CONTROL_SWITCH, self.other_result["raised"])
        self.assertTrue(self.other_result["unchanged"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
