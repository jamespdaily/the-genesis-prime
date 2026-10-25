"""jump_tables.read_function against WildStar64.exe.

Expected values come from the issue 16 trial's jumptable.py and
test_checkers.py, measured on WildStar64.exe (SHA-256 565c2fa1...fe0b10), and
from check_support.RawPE, which reads each table's 4-byte entries (RVAs from
the image base) straight from the file. Run: python3 -I test_jump_tables.py
"""

import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_support as cs  # noqa: E402
from client_pe import ClientPE  # noqa: E402
from jump_tables import read_function  # noqa: E402


def table_at(jump_tables, jmp):
    (found,) = [t for t in jump_tables if t.jmp == jmp]
    return found


class JumpTableTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pe = ClientPE(cs.client_exe())
        cls.raw = cs.raw_pe()

    def test_the_27_case_switch_has_its_jmp_default_and_case_count(self):
        # issue 16 trial: function 0x140003fb0, jmp rdx at 0x140003fe8, 27 cases, default 0x1400043ef
        t = table_at(read_function(self.pe, cs.FN_CONTROL_SWITCH), cs.JMP_CONTROL_SWITCH)
        self.assertTrue(t.found)
        self.assertIsNone(t.reason)
        self.assertEqual(t.case_count, 27)
        self.assertEqual(t.default, 0x1400043EF)
        self.assertEqual(len(t.targets), 27)

    def test_the_27_case_switch_targets_are_the_table_entries_in_the_file(self):
        # the table is at 0x140004400 (issue 16 trial); each entry is a 4-byte RVA
        t = table_at(read_function(self.pe, cs.FN_CONTROL_SWITCH), cs.JMP_CONTROL_SWITCH)
        want = [self.raw.base + self.raw.u32(0x140004400 + 4 * k) for k in range(27)]
        self.assertEqual(t.targets, want)

    def test_case_5_of_the_27_case_switch_goes_to_0x1400040fd(self):
        t = table_at(read_function(self.pe, cs.FN_CONTROL_SWITCH), cs.JMP_CONTROL_SWITCH)
        self.assertEqual(t.targets[5], 0x1400040FD)  # issue 16 trial

    def test_the_2322_case_switch_has_636_distinct_targets(self):
        # issue 16 trial: function 0x1403ec6a0, jmp rcx at 0x1403ec719, cmp 0x911 (2,322 cases),
        # table at 0x1403f1344, default 0x1403f12d2, 636 distinct targets
        t = table_at(read_function(self.pe, cs.FN_BIG_SWITCH), cs.JMP_BIG_SWITCH)
        self.assertTrue(t.found)
        self.assertEqual(t.case_count, 2322)
        self.assertEqual(t.case_count, 0x911 + 1)
        self.assertEqual(t.default, 0x1403F12D2)
        self.assertEqual(len(t.targets), 2322)
        self.assertEqual(len(set(t.targets)), 636)

    def test_the_2322_case_switch_targets_are_the_table_entries_in_the_file(self):
        t = table_at(read_function(self.pe, cs.FN_BIG_SWITCH), cs.JMP_BIG_SWITCH)
        want = [self.raw.base + self.raw.u32(0x1403F1344 + 4 * k) for k in range(2322)]
        self.assertEqual(t.targets, want)

    def test_a_computed_jump_that_is_not_a_switch_is_not_found_and_says_why(self):
        # llvm-objdump: `jmp rax` at 0x140001b6b is the end of function 0x140001b30 (.pdata), no table
        t = table_at(read_function(self.pe, cs.FN_NOT_A_SWITCH), cs.JMP_NOT_A_SWITCH)
        self.assertFalse(t.found)
        self.assertIsInstance(t.reason, str)
        self.assertTrue(t.reason.strip())
        self.assertEqual(t.targets, [])
        self.assertIsNone(t.default)
        self.assertEqual(t.case_count, 0)

    def test_read_function_lists_every_indirect_jmp_of_the_function_once(self):
        tables = read_function(self.pe, cs.FN_CONTROL_SWITCH)
        jmps = [t.jmp for t in tables]
        self.assertEqual(len(jmps), len(set(jmps)))
        self.assertIn(cs.JMP_CONTROL_SWITCH, jmps)
        for t in tables:
            self.assertIsNotNone(self.pe.root_of(t.jmp))
            self.assertEqual(self.pe.root_of(t.jmp), cs.FN_CONTROL_SWITCH)

    def test_a_changed_table_entry_changes_exactly_that_target(self):
        # planted (issue 16 trial: plant.py): XOR 0x10 into the 4-byte entry 5 of the table at
        # 0x140004400, file offset 14356 (RVA 0x40fd -> 0x40ed). The reader must see it, and only it.
        original = table_at(read_function(self.pe, cs.FN_CONTROL_SWITCH), cs.JMP_CONTROL_SWITCH).targets
        with tempfile.TemporaryDirectory() as d:
            copy = cs.planted_client_exe(Path(d), 14356, 0x10)
            planted = table_at(read_function(ClientPE(copy), cs.FN_CONTROL_SWITCH), cs.JMP_CONTROL_SWITCH).targets
        self.assertEqual(len(planted), 27)
        self.assertEqual([i for i, (a, b) in enumerate(zip(original, planted)) if a != b], [5])
        self.assertEqual(original[5], 0x1400040FD)
        self.assertEqual(planted[5], 0x1400040ED)


if __name__ == "__main__":
    unittest.main(verbosity=2)
