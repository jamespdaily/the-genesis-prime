"""client_refs.RefIndex: the reference index of WildStar64.exe from llvm-objdump.

Expected values come from llvm-objdump on the sites named, on WildStar64.exe
(SHA-256 565c2fa1...fe0b10), and from the fact file's records at those
addresses. The index is built once per class (about 2 s with 4 jobs).
Run: python3 -I test_client_refs.py
"""

import hashlib
import os
import re
import shutil
import sys
import tempfile
import unittest
from array import array
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_support as cs  # noqa: E402
from check_support import hx  # noqa: E402
from client_refs import ObjdumpFailed, RefIndex  # noqa: E402


@cs.needs_client
class RefIndexTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pe = cs.client_pe()
        cls.idx = cs.ref_index()

    def test_the_callers_of_0x140663030_are_these_17_functions(self):
        # a jmp to the entry counts as a call. The jmp at 0x14042023e lies outside every
        # function and is left out (fact file records 0x140663030 and 0x14042023e).
        want = {
            0x140409330, 0x1404165E0, 0x140419AC0, 0x14050F800, 0x140664840, 0x140664880,
            0x140672840, 0x140680180, 0x1406A30D0, 0x1406EE640, 0x140708120, 0x14072DC90,
            0x14072E210, 0x14072E480, 0x14072EA40, 0x14074A750, 0x140764A20,
        }
        callers = self.idx.callers(0x140663030)
        self.assertEqual(set(callers), want)
        self.assertNotIn(0x14042023E, [s for sites in callers.values() for s in sites])

    def test_every_call_site_lies_in_the_function_named_as_its_caller(self):
        for function, sites in self.idx.callers(0x140663030).items():
            self.assertTrue(sites)
            self.assertEqual(sites, sorted(sites))
            for site in sites:
                self.assertEqual(self.pe.root_of(site), function, hex(site))

    def test_a_function_nothing_calls_has_no_callers(self):
        # planted: an address that is no instruction in the image
        self.assertEqual(self.idx.callers(0x1BFFFF000), {})

    def test_the_callees_of_0x140283670_are_five_functions_and_five_imports(self):
        # fact file record 0x140283670
        internal, imports = self.idx.callees(0x140283670)
        self.assertEqual(sorted(internal), [0x1401971E0, 0x1401A3130, 0x1401B54E0, 0x1401B6D00, 0x140288100])
        self.assertEqual(
            sorted(imports),
            [
                "gdi32.dll!AddFontMemResourceEx",
                "kernel32.dll!DebugBreak",
                "kernel32.dll!GetLastError",
                "kernel32.dll!TlsGetValue",
                "kernel32.dll!TlsSetValue",
            ],
        )

    def test_the_string_Lighting_has_one_reference_from_0x140737da0(self):
        # the string is at 0x140b47ec8, referenced from 0x140738e19 in function 0x140737da0 (fact file records)
        self.assertEqual(self.idx.string_refs("Lighting"), {0x140B47EC8: [(0x140738E19, 0x140737DA0)]})

    def test_the_string_DialogResponseType_ViewQuestIncomplete_has_one_reference(self):
        # at 0x140b46b48, one reference from 0x14072f318 in function 0x14072ee90 (fact file records)
        self.assertEqual(
            self.idx.string_refs("DialogResponseType_ViewQuestIncomplete"),
            {0x140B46B48: [(0x14072F318, 0x14072EE90)]},
        )

    def test_a_string_that_is_nowhere_in_the_client_has_no_copies(self):
        # planted: the text only exists in this test
        self.assertEqual(self.idx.string_refs("NoSuchString_9f3a7c1e_NotInTheClient"), {})

    def test_the_showcursor_slot_is_referenced_by_two_calls_and_a_jmp_through_it(self):
        # llvm-objdump: `call [rip+..]` at 0x14000a061 and 0x14000a0bb (function
        # 0x140009d00) and `jmp [rip+..]` at 0x1402801f3, which lies outside every function
        refs = self.idx.refs_to(cs.IAT_SHOWCURSOR)
        self.assertEqual({r.source for r in refs}, {0x14000A061, 0x14000A0BB, 0x1402801F3})
        self.assertEqual({r.target for r in refs}, {cs.IAT_SHOWCURSOR})
        kinds = {r.source: r.kind for r in refs}
        self.assertEqual(kinds[0x14000A061], "call-mem")
        self.assertEqual(kinds[0x14000A0BB], "call-mem")
        self.assertEqual(kinds[0x1402801F3], "jmp-mem")
        self.assertEqual(self.pe.root_of(0x14000A061), 0x140009D00)
        self.assertEqual(self.pe.root_of(0x14000A0BB), 0x140009D00)
        self.assertIsNone(self.pe.root_of(0x1402801F3))

    def test_the_pointer_only_function_0x14077ed70_has_one_reference_a_pointer_from_0x140b6d240(self):
        # fact file record 0x14077ed70
        refs = self.idx.refs_to(cs.POINTER_ONLY_A)
        self.assertEqual([(r.source, r.target, r.kind) for r in refs], [(0x140B6D240, cs.POINTER_ONLY_A, "pointer")])

    def test_an_address_nothing_refers_to_has_no_references(self):
        # planted
        self.assertEqual(self.idx.refs_to(0x1BFFFF000), [])

    def test_a_saved_index_loads_back_with_the_same_answers(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "index"
            self.idx.save(path)
            loaded = RefIndex.load(path)
        for target in (0x140663030, 0x140283670, cs.IAT_SHOWCURSOR, cs.POINTER_ONLY_A, 0x1BFFFF000):
            self.assertEqual(loaded.refs_to(target), self.idx.refs_to(target), hex(target))
        for function in (0x140663030, 0x140283670):
            self.assertEqual(loaded.callers(function), self.idx.callers(function), hex(function))
            self.assertEqual(loaded.callees(function), self.idx.callees(function), hex(function))
        self.assertEqual(loaded.string_refs("Lighting"), self.idx.string_refs("Lighting"))

    def test_the_ten_questions_drawn_with_random_16_are_the_fixed_ten(self):
        # draw_questions draws from the full index with random.Random(16)
        drawn = cs.draw_questions(self.pe, self.idx)
        self.assertEqual(drawn, cs.QUESTIONS_16)


def planted_objdump(directory: Path, script: str) -> Path:
    """An executable standing in for llvm-objdump, running the shell script."""
    path = Path(directory) / "llvm-objdump"
    path.write_text("#!/bin/sh\n" + script + "\n")
    path.chmod(0o755)
    return path


@cs.needs_client
class RefIndexBuildFailureTest(unittest.TestCase):
    """Item 16: a disassembler error fails the build, naming the chunk, and leaves no silent hole."""

    @classmethod
    def setUpClass(cls):
        cls.pe = cs.client_pe()

    def test_a_planted_llvm_objdump_that_exits_1_fails_the_build_naming_the_chunk(self):
        # planted: exits 1 with no output at all
        first = next(s for s in self.pe.sections if s.executable)
        with tempfile.TemporaryDirectory() as d:
            objdump = planted_objdump(Path(d), "exit 1")
            with self.assertRaises(ObjdumpFailed) as caught:
                RefIndex.build(self.pe, objdump, 1)
            with self.subTest("four jobs at once"):
                with self.assertRaises(ObjdumpFailed) as pooled:
                    RefIndex.build(self.pe, objdump, 4)
        # with one job the first chunk is the first executable section as a whole
        self.assertIn(hx(first.va), str(caught.exception))
        self.assertIn(hx(first.end), str(caught.exception))
        self.assertRegex(str(pooled.exception), r"0x[0-9a-f]+-0x[0-9a-f]+")

    def test_a_planted_llvm_objdump_that_exits_0_but_writes_an_error_line_fails_the_build_naming_the_chunk(self):
        # planted: exits 0 and writes one line to stderr
        first = next(s for s in self.pe.sections if s.executable)
        with tempfile.TemporaryDirectory() as d:
            objdump = planted_objdump(Path(d), "echo 'llvm-objdump: error: planted' >&2")
            with self.assertRaises(ObjdumpFailed) as caught:
                RefIndex.build(self.pe, objdump, 1)
        self.assertIn(hx(first.va), str(caught.exception))
        self.assertIn(hx(first.end), str(caught.exception))
        self.assertIn("planted", str(caught.exception))  # the disassembler's own words


@cs.needs_client
class RefIndexOfAnotherClientTest(unittest.TestCase):
    """Item 17: a saved index is for one client, named by its SHA-256."""

    def test_load_refuses_an_index_saved_for_another_clients_sha256_naming_both_digests(self):
        # planted: an index saved against a copy of the client, then the copy replaced by a client with one
        # 4-byte value changed (check_support.planted_client_exe); the index holds no records, which
        # leaves what is checked, the digest
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            copy = root / "client.exe"
            shutil.copyfile(cs.client_exe(), copy)
            saved_digest = hashlib.sha256(copy.read_bytes()).hexdigest()
            index_path = root / "index"
            RefIndex(copy, array("Q"), array("Q"), b"").save(index_path)
            other = cs.planted_client_exe(root, 0x400, 1)
            shutil.copyfile(other, copy)
            other_digest = hashlib.sha256(copy.read_bytes()).hexdigest()
            self.assertNotEqual(saved_digest, other_digest)
            with self.assertRaises(ValueError) as caught:
                RefIndex.load(index_path)
        self.assertIn(saved_digest, str(caught.exception))
        self.assertIn(other_digest, str(caught.exception))


if __name__ == "__main__":
    unittest.main(verbosity=2)
