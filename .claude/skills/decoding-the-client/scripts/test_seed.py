"""seed.py: the seed file applied to the Ghidra project before analysis.

Expected values come from the issue 24 test list (item 2: the .pdata function
starts plus the pointer-only functions) and the issue 16 trial's seed.py and
test_checkers.py (line format `0x<hex>\\tfunction\\t<name>`, lower-case hex,
names `seed_<hex>`, no duplicate address). Run: python3 -I test_seed.py
"""

import os
import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_support as cs  # noqa: E402
import seed  # noqa: E402
from client_pe import ClientPE  # noqa: E402

LINE = re.compile(r"^0x[0-9a-f]+\tfunction\tseed_[0-9a-f]+\n$")
PLANTED_ONE = 0x140001010
PLANTED_TWO = 0x140001020


class SeedLinesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pe = ClientPE(cs.client_exe())
        cls.lines = seed.seed_lines(cls.pe)

    def test_the_seed_is_every_pdata_start_and_every_pointer_only_function(self):
        # issue 24 test list, item 2
        starts = set(self.pe.function_starts())
        pointer_only = set(self.pe.pointer_only_functions())
        self.assertFalse(starts & pointer_only)  # pointer-only targets lie outside every .pdata range
        self.assertEqual({a for a, _k, _n in self.lines}, starts | pointer_only)
        self.assertEqual(len(self.lines), 23254 + len(pointer_only))  # issue 16 trial: 23,254 starts

    def test_lines_are_sorted_with_no_duplicate_address(self):
        addresses = [a for a, _k, _n in self.lines]
        self.assertEqual(addresses, sorted(addresses))
        self.assertEqual(len(addresses), len(set(addresses)))  # issue 16 trial: test_checkers.check_lines

    def test_each_line_is_a_function_named_seed_and_its_hex_address(self):
        # issue 24 test list, item 2; issue 16 trial: names are seed_<address>
        for address, kind, name in self.lines:
            self.assertEqual(kind, "function")
            self.assertEqual(name, "seed_%x" % address)

    def test_the_planted_unmapped_address_is_outside_every_section_and_not_seeded(self):
        self.assertIsNone(self.pe.section_of(seed.PLANTED_UNMAPPED))
        self.assertNotIn(seed.PLANTED_UNMAPPED, {a for a, _k, _n in self.lines})


class SeedFileTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lines = seed.seed_lines(ClientPE(cs.client_exe()))

    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._dir.cleanup)
        self.dir = Path(self._dir.name)

    def test_write_seed_writes_one_tab_separated_line_per_function_in_lower_case_hex(self):
        # issue 16 trial: test_checkers.test_cli_file (no CR, final newline)
        path = self.dir / "seed.tsv"
        seed.write_seed(self.lines, path)
        data = path.read_bytes()
        self.assertNotIn(b"\r", data)
        self.assertTrue(data.endswith(b"\n"))
        text = data.decode("ascii").splitlines(keepends=True)
        self.assertEqual(len(text), len(self.lines))
        for line, (address, _k, name) in zip(text, self.lines):
            self.assertRegex(line, LINE)
            self.assertEqual(line, "0x%x\tfunction\t%s\n" % (address, name))

    def test_a_written_seed_reads_back_equal(self):
        path = self.dir / "seed.tsv"
        seed.write_seed(self.lines, path)
        self.assertEqual(seed.read_seed(path), self.lines)

    def test_a_seed_with_the_planted_unmapped_line_appended_reads_back_with_it_last(self):
        lines = self.lines + [(seed.PLANTED_UNMAPPED, "function", "seed_planted_unmapped")]
        path = self.dir / "seed.tsv"
        seed.write_seed(lines, path)
        self.assertEqual(seed.read_seed(path)[-1], (seed.PLANTED_UNMAPPED, "function", "seed_planted_unmapped"))

    def test_read_seed_accepts_the_good_lines_the_planted_ones_are_made_from(self):
        # proves the planted cases below fail only because of their one bad line
        path = self.dir / "good.tsv"
        path.write_text(f"0x{PLANTED_ONE:x}\tfunction\tseed_{PLANTED_ONE:x}\n0x{PLANTED_TWO:x}\tfunction\tseed_{PLANTED_TWO:x}\n")
        self.assertEqual(
            seed.read_seed(path),
            [(PLANTED_ONE, "function", f"seed_{PLANTED_ONE:x}"), (PLANTED_TWO, "function", f"seed_{PLANTED_TWO:x}")],
        )

    def _refused(self, text):
        path = self.dir / "bad.tsv"
        path.write_text(f"0x{PLANTED_ONE:x}\tfunction\tseed_{PLANTED_ONE:x}\n" + text)
        with self.assertRaises(ValueError):
            seed.read_seed(path)

    def test_read_seed_refuses_a_line_with_two_fields(self):
        self._refused(f"0x{PLANTED_TWO:x}\tfunction\n")

    def test_read_seed_refuses_a_line_with_four_fields(self):
        self._refused(f"0x{PLANTED_TWO:x}\tfunction\tseed_{PLANTED_TWO:x}\textra\n")

    def test_read_seed_refuses_an_address_without_the_0x_prefix(self):
        self._refused(f"{PLANTED_TWO:x}\tfunction\tseed_{PLANTED_TWO:x}\n")

    def test_read_seed_refuses_an_address_that_is_not_hex(self):
        self._refused("0x14000zz20\tfunction\tseed_x\n")

    def test_read_seed_refuses_a_duplicate_address(self):
        self._refused(f"0x{PLANTED_ONE:x}\tfunction\tother_name\n")

    def test_read_seed_refuses_a_name_with_a_space(self):
        self._refused(f"0x{PLANTED_TWO:x}\tfunction\tseed {PLANTED_TWO:x}\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
