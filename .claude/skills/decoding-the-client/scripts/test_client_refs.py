"""client_refs.RefIndex: the reference index of WildStar64.exe from llvm-objdump.

Expected values come from the issue 16 trial's checkers (refs.py,
test_checkers.py) and its measurements on WildStar64.exe (SHA-256
565c2fa1...fe0b10), or from llvm-objdump on the sites named. The index is
built once per class (about 2 s with 4 jobs).
Run: python3 -I test_client_refs.py
"""

import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_support as cs  # noqa: E402
from client_refs import RefIndex  # noqa: E402


class RefIndexTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pe = cs.client_pe()
        cls.idx = cs.ref_index()

    def test_the_callers_of_0x140663030_are_these_17_functions(self):
        # issue 16 trial; a jmp to the entry counts as a call. The jmp at 0x14042023e lies
        # outside every function and is left out.
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
        # issue 16 trial
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
        # issue 16 trial: the string is at 0x140b47ec8, referenced from 0x140738e19 in function 0x140737da0
        self.assertEqual(self.idx.string_refs("Lighting"), {0x140B47EC8: [(0x140738E19, 0x140737DA0)]})

    def test_the_string_DialogResponseType_ViewQuestIncomplete_has_one_reference(self):
        # issue 16 trial: at 0x140b46b48, one reference from 0x14072f318 in function 0x14072ee90
        self.assertEqual(
            self.idx.string_refs("DialogResponseType_ViewQuestIncomplete"),
            {0x140B46B48: [(0x14072F318, 0x14072EE90)]},
        )

    def test_a_string_that_is_nowhere_in_the_client_has_no_copies(self):
        # planted: the text only exists in this test
        self.assertEqual(self.idx.string_refs("NoSuchString_9f3a7c1e_NotInTheClient"), {})

    def test_the_showcursor_slot_is_referenced_by_two_calls_and_a_jmp_through_it(self):
        # issue 16 trial; llvm-objdump: `call [rip+..]` at 0x14000a061 and 0x14000a0bb (function
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
        # issue 16 trial
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

    def test_the_ten_questions_drawn_with_random_16_are_issue_16s(self):
        # issue 16 trial: questions.py drew these with random.Random(16) from the full index
        drawn = cs.draw_questions(self.pe, self.idx)
        self.assertEqual(drawn, cs.QUESTIONS_16)


if __name__ == "__main__":
    unittest.main(verbosity=2)
