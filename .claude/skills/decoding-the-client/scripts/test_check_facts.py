"""check_facts: the fact file's checker.

Expected values come from the issue 7 approved test list (comment "Re-scoped
plan and test list", 2026-10-25; items cited below) and the rules in the
docstring of check_facts.py and in SKILL.md (decoding-the-client). Every
record, file and address here is planted: the checker is run on text and on
temporary git repositories made for the test, never on a judgement of the
client. Addresses are assigned once to PLANTED_ names, as the checker's own
coverage rule asks, so these tests cite no client address a record must hold.
Run: python3 -I test_check_facts.py
"""

import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_facts  # noqa: E402
import check_support as cs  # noqa: E402
from check_facts import Problem, Record  # noqa: E402

PLANTED_A = "0x1408296a3"
PLANTED_B = "0x140001010"
PLANTED_C = "0x14aabbccd"
PLANTED_MIXED = "0x140aBcDeF"
PLANTED_SKIPPED_ONE = "0x140002020"
PLANTED_SKIPPED_TWO = "0x140003030"
PLANTED_FACT_FILE_ONLY = "0x140004040"
PLANTED_UNTRACKED = "0x140005050"
PLANTED_FIVE_DIGITS = "0x14abcde"
PLANTED_SIX_DIGITS = "0x14abcdef"
PLANTED_OTHER_PREFIX = "0x2408296a3"

FACT_FILE_RELATIVE = check_facts.FACT_FILE.relative_to(check_facts.REPOSITORY)

CLEAN_STATEMENT = "Scales the damage by the caster's level before the target's armour is applied."
INSTRUCTION_PROOF = f"{PLANTED_A} mulss reads the level scale from the table"
TEST_PROOF = "test_emulator.py runs the function and checks the result"


def record(key="Spell4.damageScale", **fields) -> Record:
    """A record that breaks no rule, with the given fields replaced."""
    values = dict(statement=CLEAN_STATEMENT, proof=TEST_PROOF, grade="sure", gap=None, name=None)
    values.update(fields)
    return Record(key=key, **values)


def problems_of(*records: Record, entries=()) -> list[Problem]:
    return check_facts.record_problems({r.key: r for r in records}, set(entries))


def toml_text(key: str, **fields) -> str:
    lines = [f"[{json.dumps(key)}]"]
    lines += [f"{name} = {json.dumps(value)}" for name, value in fields.items()]
    return "\n".join(lines) + "\n"


def load_text(text: str) -> dict[str, Record]:
    with tempfile.TemporaryDirectory() as d:
        path = Path(d) / "client-facts.toml"
        path.write_text(text)
        return check_facts.load(path)


def refusals(text: str, entries=()) -> list[tuple[str, str]]:
    """(where, what) of every refusal of a planted fact file. A ValueError from
    load counts as a refusal that names the record in its message; a problem
    from record_problems carries the record's key as its where."""
    try:
        records = load_text(text)
    except ValueError as error:
        return [(str(error), str(error))]
    return [(p.where, p.what) for p in check_facts.record_problems(records, set(entries))]


class Refusal(unittest.TestCase):
    def assertRefused(self, found: list[tuple[str, str]], key: str, field: str):
        """item 5: the refusal names the record and the rule (the field) broken."""
        self.assertTrue(found, "nothing was refused")
        self.assertTrue(all(key in where for where, _what in found), found)
        self.assertTrue(any(field in what for _where, what in found), found)


class LoadTest(unittest.TestCase):
    def test_a_record_is_read_with_every_field_as_written(self):
        # docstring: fields statement, proof, grade, gap, name; a record is one table keyed by its address
        text = toml_text(
            PLANTED_A, statement="S", proof="P", grade="fairly sure", gap="G", name="CastSpell"
        ) + toml_text("Spell4.damageScale", statement="S2", proof="P2", grade="sure")
        self.assertEqual(
            load_text(text),
            {
                PLANTED_A: Record(PLANTED_A, "S", "P", "fairly sure", "G", "CastSpell"),
                "Spell4.damageScale": Record("Spell4.damageScale", "S2", "P2", "sure", None, None),
            },
        )

    def test_a_duplicate_key_raises_value_error_naming_it(self):
        # item 2; docstring of load
        text = toml_text(PLANTED_A, statement="S", proof="P", grade="sure") * 2
        with self.assertRaises(ValueError) as raised:
            load_text(text)
        self.assertIn(PLANTED_A, str(raised.exception))


class FieldsTest(Refusal):
    def test_a_record_that_breaks_no_rule_is_not_refused(self):
        # item 3, "a clean record passes"
        self.assertEqual(problems_of(record()), [])

    def test_a_missing_statement_is_refused(self):
        # item 2
        text = toml_text("Spell4.damageScale", proof=TEST_PROOF, grade="sure")
        self.assertRefused(refusals(text), "Spell4.damageScale", "statement")

    def test_a_missing_proof_is_refused(self):
        # item 2
        text = toml_text("Spell4.damageScale", statement=CLEAN_STATEMENT, grade="sure")
        self.assertRefused(refusals(text), "Spell4.damageScale", "proof")

    def test_a_missing_grade_is_refused(self):
        # item 2
        text = toml_text("Spell4.damageScale", statement=CLEAN_STATEMENT, proof=TEST_PROOF)
        self.assertRefused(refusals(text), "Spell4.damageScale", "grade")

    def test_an_unknown_grade_is_refused(self):
        # item 2; docstring: grade is "sure", "fairly sure" or "guess"
        text = toml_text("Spell4.damageScale", statement=CLEAN_STATEMENT, proof=TEST_PROOF, grade="certain")
        self.assertRefused(refusals(text), "Spell4.damageScale", "grade")

    def test_each_of_the_three_grades_is_accepted(self):
        # docstring: GRADES; gap present exactly where the rules want it
        for grade, gap in (("sure", None), ("fairly sure", "the second branch is unread"), ("guess", "unread")):
            with self.subTest(grade=grade):
                self.assertEqual(problems_of(record(grade=grade, gap=gap)), [])

    def test_a_fairly_sure_record_without_a_gap_is_refused(self):
        # item 2
        self.assertRefused(
            [(p.where, p.what) for p in problems_of(record(grade="fairly sure", gap=None))],
            "Spell4.damageScale",
            "gap",
        )

    def test_a_guess_without_a_gap_is_refused(self):
        # item 2
        self.assertRefused(
            [(p.where, p.what) for p in problems_of(record(grade="guess", gap=None))],
            "Spell4.damageScale",
            "gap",
        )

    def test_a_sure_record_with_a_gap_is_refused(self):
        # item 2; docstring: gap is for "fairly sure" and "guess" only
        self.assertRefused(
            [(p.where, p.what) for p in problems_of(record(grade="sure", gap="not yet read"))],
            "Spell4.damageScale",
            "gap",
        )

    def test_a_function_entry_without_a_name_is_refused(self):
        # item 2
        found = problems_of(record(key=PLANTED_A), entries={PLANTED_A})
        self.assertRefused([(p.where, p.what) for p in found], PLANTED_A, "name")

    def test_a_function_entry_with_a_name_is_accepted(self):
        # item 2, the other side of the rule
        self.assertEqual(problems_of(record(key=PLANTED_A, name="CastSpell"), entries={PLANTED_A}), [])

    def test_a_name_on_a_key_that_is_not_a_function_entry_is_refused(self):
        # item 2
        found = problems_of(record(key=PLANTED_B, name="CastSpell"), entries={PLANTED_A})
        self.assertRefused([(p.where, p.what) for p in found], PLANTED_B, "name")


class WordingTest(Refusal):
    def refused_statement(self, statement: str) -> list[tuple[str, str]]:
        return [(p.where, p.what) for p in problems_of(record(statement=statement))]

    def test_a_statement_holding_a_register_name_is_refused(self):
        # item 3
        for register in ("rax", "ecx", "xmm0", "rsp"):
            with self.subTest(register=register):
                found = self.refused_statement(f"Returns the scaled value in {register}.")
                self.assertRefused(found, "Spell4.damageScale", "statement")

    def test_a_statement_holding_a_struct_offset_is_refused(self):
        # item 3
        found = self.refused_statement("Reads the level from the caster at +0x1678.")
        self.assertRefused(found, "Spell4.damageScale", "statement")

    def test_a_statement_holding_the_word_vtable_is_refused(self):
        # item 3
        found = self.refused_statement("Calls the second entry of the vtable of the unit.")
        self.assertRefused(found, "Spell4.damageScale", "statement")

    def test_a_register_name_inside_the_proof_is_allowed(self):
        # item 3: "A register name inside the proof is allowed"
        for register in ("rax", "ecx", "xmm0", "rsp"):
            with self.subTest(register=register):
                proof = f"{PLANTED_A} mulss {register}, xmm1 scales the level"
                self.assertEqual(problems_of(record(proof=proof)), [])

    def test_another_server_named_in_any_field_is_refused(self):
        # item 3: "NexusForever", "Nexus Forever", in any field
        for server in ("NexusForever", "Nexus Forever"):
            for field, fields in (
                ("statement", dict(statement=f"Matches what {server} does.")),
                ("proof", dict(proof=f"{TEST_PROOF}; {server} agrees")),
                ("gap", dict(grade="guess", gap=f"{server} would settle it")),
                ("name", dict(key=PLANTED_A, name=f"{server}Cast")),
            ):
                with self.subTest(server=server, field=field):
                    found = problems_of(record(**fields), entries={PLANTED_A})
                    self.assertRefused([(p.where, p.what) for p in found], fields.get("key", "Spell4.damageScale"), field)

    def test_an_issue_or_pull_request_named_in_any_field_is_refused(self):
        # item 3: "#16", "issue 16", "pull request 25"
        for reference in ("#16", "issue 16", "pull request 25"):
            for field, fields in (
                ("statement", dict(statement=f"Scales the damage, see {reference}.")),
                ("proof", dict(proof=f"{TEST_PROOF}; found in {reference}")),
                ("gap", dict(grade="fairly sure", gap=f"tracked in {reference}")),
            ):
                with self.subTest(reference=reference, field=field):
                    found = problems_of(record(**fields))
                    self.assertRefused([(p.where, p.what) for p in found], "Spell4.damageScale", field)

    def test_an_import_by_ordinal_is_not_an_issue_number(self):
        # item 3 refuses issue numbers; `ws2_32.dll!#115` is how the client's import
        # table names an ordinal import (test_client_pe.py)
        self.assertEqual(problems_of(record(proof=f"{TEST_PROOF}; the slot holds ws2_32.dll!#115")), [])

    def test_a_register_name_is_matched_in_lower_case_only(self):
        # item 3: a register is written lower-case by the disassembler; "SP" in a
        # statement is an ordinary abbreviation
        self.assertEqual(problems_of(record(statement="Adds the SP cost to the ability.")), [])

    def test_a_decision_record_named_in_any_field_is_refused(self):
        # item 3: "decision record"
        for field, fields in (
            ("statement", dict(statement="Scales the damage, as the decision record says.")),
            ("proof", dict(proof=f"{TEST_PROOF}; the decision record has it")),
            ("gap", dict(grade="guess", gap="the decision record would settle it")),
        ):
            with self.subTest(field=field):
                found = problems_of(record(**fields))
                self.assertRefused([(p.where, p.what) for p in found], "Spell4.damageScale", field)


class GradeAgainstProofTest(Refusal):
    def refused_proof(self, proof: str, grade="sure", gap=None) -> list[tuple[str, str]]:
        return [(p.where, p.what) for p in problems_of(record(proof=proof, grade=grade, gap=gap))]

    def test_a_sure_record_whose_proof_names_no_instruction_or_test_is_refused(self):
        # item 4
        for proof in (
            "Read the function by hand and it looked right.",
            f"The function at {PLANTED_A}",  # an address with no mnemonic after it
        ):
            with self.subTest(proof=proof):
                self.assertRefused(self.refused_proof(proof), "Spell4.damageScale", "proof")

    def test_a_sure_record_whose_proof_names_an_instruction_is_accepted(self):
        # item 4: an address followed by a mnemonic
        self.assertEqual(self.refused_proof(f"{PLANTED_A} mulss"), [])

    def test_a_sure_record_whose_proof_names_a_test_file_is_accepted(self):
        # item 4: a test file
        self.assertEqual(self.refused_proof("test_emulator.py"), [])

    def test_a_fairly_sure_record_needs_no_instruction_or_test_in_its_proof(self):
        # SKILL.md: "Fairly sure: read, with a named gap"; only "sure" is held to the proof
        self.assertEqual(self.refused_proof("Read by hand.", grade="fairly sure", gap="one branch unread"), [])


def git(root: Path, *args: str) -> None:
    subprocess.run(
        ["git", "-c", "user.name=planted", "-c", "user.email=planted@example.invalid", "-c", "commit.gpgsign=false", *args],
        cwd=root,
        check=True,
        capture_output=True,
    )


def plant_repository(root: Path, tracked: dict[str, str], untracked: dict[str, str] | None = None) -> Path:
    """A git repository at root holding the tracked files, committed, and the untracked files beside them."""
    root.mkdir(parents=True, exist_ok=True)
    git(root, "init", "-q")
    for files in (tracked, untracked or {}):
        for relative, text in files.items():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
    git(root, "add", "--", *tracked)
    git(root, "commit", "-q", "-m", "planted")
    return root


class CitedAddressesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._dir = tempfile.TemporaryDirectory()
        tracked = {
            "src/a.gleam": f"// first line\nlet scale = {PLANTED_A}\n",
            "docs/b.txt": f"{PLANTED_MIXED} then {PLANTED_B}\n",
            "src/c.gleam": f"let again = {PLANTED_A}\n\n\nlet other = {PLANTED_C}\n",
            "src/planted.py": (
                f"PLANTED_ONE = {PLANTED_SKIPPED_ONE}\n"
                f"    PLANTED_TWO = {PLANTED_SKIPPED_TWO}  # indented, with a comment\n"
                f"let kept = {PLANTED_B}\n"
            ),
            "src/short.gleam": (
                f"{PLANTED_FIVE_DIGITS} {PLANTED_SIX_DIGITS} {PLANTED_OTHER_PREFIX}\n"
            ),
            str(FACT_FILE_RELATIVE): toml_text(
                PLANTED_FACT_FILE_ONLY, statement="S", proof="P", grade="guess", gap="G"
            ),
        }
        untracked = {"src/untracked.gleam": f"let x = {PLANTED_UNTRACKED}\n"}
        cls.repository = plant_repository(Path(cls._dir.name) / "repository", tracked, untracked)
        cls.cited = check_facts.cited_addresses(cls.repository)

    @classmethod
    def tearDownClass(cls):
        cls._dir.cleanup()

    def citations(self, address: str) -> list[str]:
        return sorted(self.cited.get(address, []))

    def test_every_address_in_a_tracked_file_is_found_with_its_file_and_line(self):
        # item 1
        self.assertEqual(self.citations(PLANTED_A), ["src/a.gleam:2", "src/c.gleam:1"])
        self.assertEqual(self.citations(PLANTED_C), ["src/c.gleam:4"])

    def test_two_addresses_on_one_line_are_both_found_there(self):
        # item 1
        self.assertIn("docs/b.txt:1", self.citations(PLANTED_B))
        self.assertEqual(self.citations(PLANTED_MIXED.lower()), ["docs/b.txt:1"])

    def test_an_address_is_reported_lower_case_whatever_case_it_was_written_in(self):
        # item 1: "any case, reported lower-case"
        self.assertIn(PLANTED_MIXED.lower(), self.cited)
        self.assertNotIn(PLANTED_MIXED, self.cited)
        self.assertEqual(self.cited, {k: v for k, v in self.cited.items() if k == k.lower()})

    def test_a_number_that_is_not_seven_digits_after_0x14_is_not_an_address(self):
        # item 1: "7 hex digits after 0x14"
        for text in (PLANTED_FIVE_DIGITS, PLANTED_SIX_DIGITS, PLANTED_OTHER_PREFIX):
            with self.subTest(text=text):
                self.assertNotIn(text, self.cited)

    def test_the_fact_file_itself_is_skipped(self):
        # item 1; docstring of cited_addresses
        self.assertNotIn(PLANTED_FACT_FILE_ONLY, self.cited)

    def test_a_line_assigning_a_planted_name_is_skipped(self):
        # item 1; docstring: PLANTED_ lines, indented or commented too
        self.assertNotIn(PLANTED_SKIPPED_ONE, self.cited)
        self.assertNotIn(PLANTED_SKIPPED_TWO, self.cited)

    def test_a_planted_line_skips_only_its_own_line(self):
        # item 1: the next line of the same file is still read
        self.assertIn("src/planted.py:3", self.citations(PLANTED_B))

    def test_a_file_git_does_not_track_is_not_read(self):
        # item 1: "git-tracked files"
        self.assertNotIn(PLANTED_UNTRACKED, self.cited)

    def test_exactly_the_planted_addresses_are_found(self):
        self.assertEqual(
            set(self.cited), {PLANTED_A, PLANTED_B, PLANTED_C, PLANTED_MIXED.lower()}
        )


class CoverageProblemsTest(unittest.TestCase):
    CITED = {PLANTED_A: ["src/a.gleam:2", "src/c.gleam:1"]}

    def problems(self, *records: Record, cited=None) -> list[Problem]:
        return check_facts.coverage_problems({r.key: r for r in records}, self.CITED if cited is None else cited)

    def test_a_cited_address_no_record_holds_is_one_problem_naming_it_and_a_citation(self):
        # item 1 and item 5
        found = self.problems(record(key="Spell4.damageScale"))
        self.assertEqual(len(found), 1)
        self.assertIn(PLANTED_A, found[0].what)
        self.assertIn(found[0].where, self.CITED[PLANTED_A])

    def test_each_address_no_record_holds_is_its_own_problem(self):
        # item 1: "one problem per cited address"
        cited = {PLANTED_A: ["src/a.gleam:2"], PLANTED_B: ["docs/b.txt:1"], PLANTED_C: ["src/c.gleam:4"]}
        found = self.problems(record(key=PLANTED_B, name="Held"), cited=cited)
        self.assertEqual({p.where for p in found}, {"src/a.gleam:2", "src/c.gleam:4"})
        self.assertEqual(sum(PLANTED_A in p.what for p in found), 1)
        self.assertEqual(sum(PLANTED_C in p.what for p in found), 1)
        self.assertEqual(len(found), 2)

    def test_an_address_cited_twice_is_still_one_problem(self):
        # item 1: one per address, not per citation
        self.assertEqual(len(self.problems(record())), 1)

    def test_an_address_held_as_a_records_key_is_covered(self):
        # item 1
        self.assertEqual(self.problems(record(key=PLANTED_A, name="Held")), [])

    def test_an_address_inside_a_statement_is_covered(self):
        # item 1
        self.assertEqual(self.problems(record(statement=f"Calls the function at {PLANTED_A} first.")), [])

    def test_an_address_inside_a_proof_is_covered(self):
        # item 1
        self.assertEqual(self.problems(record(proof=INSTRUCTION_PROOF)), [])

    def test_an_address_held_only_in_another_records_proof_is_covered(self):
        # item 1: "an address held only in another record's proof counts as held"
        owner = record(key="Spell4.damageScale", proof=INSTRUCTION_PROOF)
        other = record(key="Spell4.effectType")
        self.assertEqual(self.problems(owner, other), [])

    def test_nothing_cited_is_no_problem(self):
        self.assertEqual(self.problems(record(), cited={}), [])


LEAF_FUNCTION = 0x1408296A0  # a leaf function: no .pdata entry (formulas_by_hand.py)
PDATA_START = 0x140003FB0  # a .pdata start (test_jump_tables.py)
INSIDE_PDATA_FUNCTION = 0x140003FE8  # the switch jump inside it
RDATA_CONSTANT = 0x140B79D14  # a constant in .rdata (formulas_by_hand.py)


class FunctionEntriesTest(unittest.TestCase):
    """item 2's name rule on the real client: .pdata lists no leaf function."""

    @classmethod
    def setUpClass(cls):
        from client_pe import ClientPE

        cls.pe = ClientPE(cs.client_exe())

    def entries(self, *keys: int) -> set[str]:
        records = {"0x%x" % k: record(key="0x%x" % k, name="Named") for k in keys}
        return check_facts.function_entries(self.pe, records)

    def test_a_pdata_start_is_an_entry_with_or_without_a_record(self):
        self.assertIn("0x%x" % PDATA_START, self.entries())

    def test_a_named_leaf_function_outside_every_pdata_function_is_an_entry(self):
        self.assertIn("0x%x" % LEAF_FUNCTION, self.entries(LEAF_FUNCTION))

    def test_a_named_address_inside_a_pdata_function_is_not_an_entry(self):
        self.assertNotIn("0x%x" % INSIDE_PDATA_FUNCTION, self.entries(INSIDE_PDATA_FUNCTION))

    def test_a_named_address_outside_code_is_not_an_entry(self):
        self.assertNotIn("0x%x" % RDATA_CONSTANT, self.entries(RDATA_CONSTANT))


class MainTest(unittest.TestCase):
    def run_main(self, argv=()) -> tuple[int, str]:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = check_facts.main(list(argv))
        return code, out.getvalue()

    def test_the_real_repository_passes_and_prints_no_problem(self):
        # item 1: "main([]) exits 0 and prints no problem"; fails until the records land. The
        # client is named so the name rule runs; without it main prints that the rule was not checked.
        with mock.patch.dict(os.environ, {"WILDSTAR_CLIENT_EXE": str(cs.client_exe())}):
            code, printed = self.run_main()
        self.assertEqual((code, printed), (0, ""))

    def test_main_exits_non_zero_and_prints_each_problem(self):
        # item 5: a planted repository with one bad record and one address no record holds
        with tempfile.TemporaryDirectory() as d:
            facts = toml_text(
                PLANTED_A, statement=CLEAN_STATEMENT, proof=INSTRUCTION_PROOF, grade="certain"
            )
            repository = plant_repository(
                Path(d) / "repository",
                {str(FACT_FILE_RELATIVE): facts, "src/c.gleam": f"let other = {PLANTED_C}\n"},
            )
            fact_file = repository / FACT_FILE_RELATIVE
            expected = check_facts.record_problems(check_facts.load(fact_file), set()) + check_facts.coverage_problems(
                check_facts.load(fact_file), check_facts.cited_addresses(repository)
            )
            env = {k: v for k, v in os.environ.items() if k != "WILDSTAR_CLIENT_EXE"}
            with (
                mock.patch.dict(os.environ, env, clear=True),
                mock.patch.object(check_facts, "REPOSITORY", repository),
                mock.patch.object(check_facts, "FACT_FILE", fact_file),
            ):
                code, printed = self.run_main()
        self.assertTrue(any(p.where == PLANTED_A for p in expected), expected)  # the bad grade
        self.assertTrue(any(p.where == "src/c.gleam:1" for p in expected), expected)  # the address no record holds
        self.assertNotEqual(code, 0)
        for problem in expected:
            with self.subTest(where=problem.where):
                self.assertIn(problem.where, printed)
                self.assertIn(problem.what, printed)


if __name__ == "__main__":
    unittest.main(verbosity=2)
