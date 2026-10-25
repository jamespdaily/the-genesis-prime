"""client_pe.ClientPE against WildStar64.exe.

Expected values come from the issue 16 trial's checkers (its pe.py and
test_checkers.py) run on WildStar64.exe, SHA-256
565c2fa1a1cf4b08cf5a93e0bff90bf09bde5772d03615402132d72db5fe0b10, or from
check_support.RawPE, a second reading of the same file written for the tests.
Run: python3 -I test_client_pe.py
"""

import hashlib
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_support as cs  # noqa: E402
import ghidra_env  # noqa: E402
from client_pe import ClientPE  # noqa: E402


class ClientPETest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pe = ClientPE(cs.client_exe())
        cls.raw = cs.raw_pe()

    def test_the_client_file_is_the_one_the_expected_values_were_measured_on(self):
        blob = cs.client_exe().read_bytes()
        self.assertEqual(len(blob), 13927576)  # issue 16 trial: test_checkers.test_file_identity
        self.assertEqual(
            hashlib.sha256(blob).hexdigest(),
            "565c2fa1a1cf4b08cf5a93e0bff90bf09bde5772d03615402132d72db5fe0b10",  # issue 16 trial
        )
        self.assertEqual(ghidra_env.CLIENT_SHA256, hashlib.sha256(blob).hexdigest())

    def test_the_image_base_is_0x140000000(self):
        self.assertEqual(self.pe.image_base, 0x140000000)  # issue 16 trial: test_header

    def test_the_entry_point_is_a_function_start(self):
        # issue 16 trial: entry 0x1400088c0. ClientPE has no entry attribute, so
        # the entry is checked as a function start; the entry value itself is
        # reported to the main session as not expressible.
        self.assertEqual(self.pe.root_of(0x1400088C0), 0x1400088C0)
        self.assertIn(0x1400088C0, self.pe.function_starts())

    def test_the_eight_sections_are_in_the_pe_header_order(self):
        # issue 16 trial: test_header
        self.assertEqual(
            [s.name for s in self.pe.sections],
            [".text", "BINK", ".rdata", ".data", ".pdata", "_RDATA", ".rsrc", ".reloc"],
        )

    def test_the_text_section_has_the_pe_headers_numbers(self):
        # issue 16 trial: test_header (.text va 0x140001000, vsize 9792556, raw 1024 + 9793024, chars 0x60000020)
        text = self.pe.sections[0]
        self.assertEqual(
            (text.va, text.virtual_size, text.raw_offset, text.raw_size, text.executable),
            (0x140001000, 9792556, 1024, 9793024, True),
        )

    def test_every_section_matches_a_second_reading_of_the_header(self):
        self.assertEqual(len(self.pe.sections), len(self.raw.sections))
        for ours, (name, rva, vsize, raw_off, raw_size, chars) in zip(self.pe.sections, self.raw.sections):
            with self.subTest(section=name):
                self.assertEqual(
                    (ours.name, ours.va, ours.virtual_size, ours.raw_offset, ours.raw_size, ours.executable),
                    (name, self.raw.base + rva, vsize, raw_off, raw_size, bool(chars & self.raw.SCN_EXECUTE)),
                )

    def test_a_section_ends_where_its_virtual_size_ends(self):
        text = self.pe.sections[0]
        self.assertEqual(text.end, 0x140001000 + 9792556)

    def test_section_of_names_the_section_holding_an_address(self):
        text = self.pe.sections[0]
        self.assertEqual(self.pe.section_of(0x140001000).name, ".text")
        self.assertEqual(self.pe.section_of(text.end - 1).name, ".text")
        self.assertEqual(self.pe.section_of(0x140B47EC8).name, ".rdata")  # the string "Lighting" (issue 16 trial)

    def test_an_address_outside_every_section_has_no_section(self):
        self.assertIsNone(self.pe.section_of(0x1BFFFF000))  # seed.PLANTED_UNMAPPED
        self.assertIsNone(self.pe.section_of(0x13FFFFFFF))  # one below the image
        self.assertIsNone(self.pe.section_of(0x140957FFF))  # the page gap before BINK (PE header: .text ends at 0x140957c2c, its file data at 0x140957e00; BINK starts at 0x140958000)

    def test_read_returns_the_files_bytes_at_a_known_address(self):
        # issue 16 trial: the 16 bytes at two function starts
        self.assertEqual(self.pe.read(0x1404A4E30, 16).hex(), "48895c24084889742410574883ec4041")
        self.assertEqual(self.pe.read(0x14063E550, 16).hex(), "40534883ec50ba9ec90600e870d8d0ff")

    def test_read_equals_the_file_at_the_text_sections_offset(self):
        # .text raw offset 1024 at va 0x140001000 (PE header, issue 16 trial)
        blob = cs.client_exe().read_bytes()
        for va in (0x140001000, 0x1400088C0, 0x1404A4E30, 0x14063E550):
            with self.subTest(va=hex(va)):
                off = 1024 + (va - 0x140001000)
                self.assertEqual(self.pe.read(va, 32), blob[off : off + 32])

    def test_read_follows_a_changed_file(self):
        # planted: the harness can fail. Change one byte of the copy; read must see it.
        with tempfile.TemporaryDirectory() as d:
            copy = Path(d) / "copy.exe"
            blob = bytearray(cs.client_exe().read_bytes())
            blob[1024 + (0x1404A4E30 - 0x140001000)] ^= 0xFF
            copy.write_bytes(bytes(blob))
            changed = ClientPE(copy).read(0x1404A4E30, 16).hex()
        self.assertEqual(changed, "b7895c24084889742410574883ec4041")  # first byte 0x48 XOR 0xff
        self.assertNotEqual(changed, "48895c24084889742410574883ec4041")

    def test_read_refuses_an_address_outside_every_section(self):
        with self.assertRaises(ValueError):
            self.pe.read(0x1BFFFF000, 16)

    def test_read_refuses_the_uninitialised_tail_of_a_section(self):
        # .data: virtual size 1799016 but raw size 329216 (PE header), so the rest is not in the file
        data = next(s for s in self.pe.sections if s.name == ".data")
        self.assertGreater(data.virtual_size, data.raw_size)
        with self.assertRaises(ValueError):
            self.pe.read(data.va + data.raw_size + 16, 16)

    def test_pdata_has_46407_entries_of_which_23153_are_chained(self):
        # issue 16 trial
        entries = self.pe.runtime_functions()
        self.assertEqual(len(entries), 46407)
        self.assertEqual(sum(1 for e in entries if e.chained_to is not None), 23153)

    def test_function_starts_are_the_23254_entries_that_are_not_chained(self):
        # issue 16 trial: 23,254 function starts = 46,407 - 23,153
        starts = self.pe.function_starts()
        self.assertEqual(len(starts), 23254)
        self.assertEqual(
            set(starts), {e.begin for e in self.pe.runtime_functions() if e.chained_to is None}
        )

    def test_pdata_entries_are_sorted_and_do_not_overlap(self):
        # issue 16 trial: test_pdata_sorted_non_overlapping
        entries = self.pe.runtime_functions()
        for a, b in zip(entries, entries[1:]):
            self.assertLess(a.begin, a.end)
            self.assertLessEqual(a.end, b.begin, "overlap at 0x%x" % b.begin)

    def test_every_pdata_entry_and_chain_link_matches_the_unwind_info_read_by_hand(self):
        # RawPE reads each entry's unwind flags and chained parent from the file's bytes
        expected = self.raw.pdata()
        ours = [(e.begin, e.end, e.chained_to) for e in self.pe.runtime_functions()]
        self.assertEqual(ours, expected)

    def test_every_chained_entry_names_a_parent_that_is_an_entry(self):
        entries = {e.begin for e in self.pe.runtime_functions()}
        for e in self.pe.runtime_functions():
            if e.chained_to is not None:
                self.assertIn(e.chained_to, entries)

    def test_root_of_follows_chains_to_the_function_start(self):
        parent = {b: p for b, _e, p in self.raw.pdata()}

        def root(begin):
            while parent[begin] is not None:
                begin = parent[begin]
            return begin

        chained = [b for b, p in parent.items() if p is not None]
        self.assertEqual(len(chained), 23153)
        for begin in chained[:: max(1, len(chained) // 500)]:
            with self.subTest(begin=hex(begin)):
                self.assertEqual(self.pe.root_of(begin), root(begin))
                self.assertEqual(self.pe.root_of(begin + 1), root(begin))

    def test_root_of_a_function_start_and_its_last_byte_is_that_start(self):
        for begin, end, p in self.raw.pdata()[:300]:
            if p is None:
                self.assertEqual(self.pe.root_of(begin), begin)
                self.assertEqual(self.pe.root_of(end - 1), begin)

    def test_root_of_an_address_in_no_pdata_range_is_none(self):
        self.assertIsNone(self.pe.root_of(0x1BFFFF000))
        self.assertIsNone(self.pe.root_of(0x140B47EC8))  # data in .rdata
        # issue 16 trial: pointer-only functions lie outside every .pdata range
        self.assertIsNone(self.pe.root_of(cs.POINTER_ONLY_A))
        self.assertIsNone(self.pe.root_of(cs.POINTER_ONLY_B))

    def test_root_ranges_hold_the_entry_and_every_entry_chained_to_it(self):
        entries = self.raw.pdata()
        parent = {b: p for b, _e, p in entries}
        end_of = {b: e for b, e, _p in entries}

        def root(begin):
            while parent[begin] is not None:
                begin = parent[begin]
            return begin

        expected: dict[int, list] = {}
        for begin in parent:
            expected.setdefault(root(begin), []).append((begin, end_of[begin]))
        for start in self.pe.function_starts():
            self.assertEqual(sorted(self.pe.root_ranges(start)), sorted(expected[start]), hex(start))

    def test_imports_are_384_slots_named_dll_bang_name_in_lower_case(self):
        imports = self.pe.imports()
        self.assertEqual(len(imports), 384)  # issue 16 trial: import + delay-import directories
        self.assertEqual(imports[0x140959298], "kernel32.dll!SetErrorMode")
        self.assertEqual(imports[0x1409598F8], "user32.dll!ShowCursor")
        self.assertEqual(imports[0x140959A78], "ws2_32.dll!#115")  # ordinal import
        for name in imports.values():
            dll, _, symbol = name.partition("!")
            self.assertEqual(dll, dll.lower(), name)
            self.assertTrue(dll.endswith(".dll") and symbol, name)

    def test_every_import_slot_is_in_the_iat_inside_a_data_section(self):
        for slot in self.pe.imports():
            self.assertEqual(self.pe.section_of(slot).name, ".rdata", hex(slot))

    def test_there_are_46525_dir64_relocations_whose_value_is_the_stored_pointer(self):
        relocations = self.pe.relocations()
        self.assertEqual(len(relocations), 46525)  # issue 16 trial
        self.assertEqual(len({a for a, _v in relocations}), 46525)
        for address, value in relocations:
            self.assertEqual(value, self.raw.u64(address), hex(address))

    def test_pointer_only_functions_are_the_pointer_targets_outside_every_pdata_range(self):
        found = self.pe.pointer_only_functions()
        # issue 16 trial found 2,677 targets that plain Ghidra also missed, a subset of these
        self.assertGreaterEqual(len(found), 2677)
        self.assertIn(cs.POINTER_ONLY_A, found)  # issue 16 trial
        self.assertIn(cs.POINTER_ONLY_B, found)  # issue 16 trial
        self.assertEqual(len(set(found)), len(found))
        for target in found:
            self.assertIsNone(self.pe.root_of(target), hex(target))
            self.assertEqual(self.pe.section_of(target).name, ".text", hex(target))

    def test_every_pointer_only_function_is_the_value_of_some_relocation(self):
        values = {v for _a, v in self.pe.relocations()}
        self.assertLessEqual(set(self.pe.pointer_only_functions()), values)

    def test_a_relocated_text_pointer_in_a_pdata_range_is_not_pointer_only(self):
        # the definition: the targets outside every .pdata range, nothing else
        found = set(self.pe.pointer_only_functions())
        inside = [v for _a, v in self.pe.relocations()
                  if self.pe.section_of(v) is not None and self.pe.section_of(v).name == ".text"
                  and self.pe.root_of(v) is not None]
        self.assertGreater(len(inside), 0)
        self.assertFalse(found & set(inside))


if __name__ == "__main__":
    unittest.main(verbosity=2)
