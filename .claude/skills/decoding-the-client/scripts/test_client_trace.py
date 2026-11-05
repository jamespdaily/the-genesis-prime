"""client_trace.py's own logic: reading its input, the size bound, the registration lines, the dispatch tables.

Expected values come from the client: the registration lines are two lines of the saved C of the function at
0x14006c290; the table origins are the instructions in llvm-objdump's listing of the dispatchers (fact file
records 0x1403ec6a0 and 0x140003fb0, whose messages start at 0x966); the case addresses are the ones the fact
file records for messages 0x7fb and 0x96b. Run: python3 -I test_client_trace.py
"""

import io
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import call_paths  # noqa: E402
import check_facts  # noqa: E402
import check_support as cs  # noqa: E402
import client_trace  # noqa: E402
import decompiled  # noqa: E402
import jump_tables  # noqa: E402
from client_pe import ClientPE  # noqa: E402
from client_refs import Ref  # noqa: E402


def instruction(address, mnemonic, *operands):
    return jump_tables.Instruction(address, mnemonic, list(operands), None)


FUNCTION_SIZE = 0x100


class FakePE:
    """The parts of ClientPE a trace asks: functions of FUNCTION_SIZE bytes at the given starts, no leaf functions."""

    def __init__(self, starts):
        self.starts = sorted(starts)

    def function_starts(self):
        return self.starts

    def root_of(self, address):
        return next((s for s in self.starts if s <= address < s + FUNCTION_SIZE), None)

    def root_ranges(self, start):
        return [(start, start + FUNCTION_SIZE)]

    def imports(self):
        return {}

    def section_of(self, address):
        return None


class FakeIndex:
    """The parts of RefIndex a trace asks, over a list of Ref."""

    def __init__(self, starts, refs):
        self.pe = FakePE(starts)
        self.refs = refs

    def refs_to(self, target):
        return [r for r in self.refs if r.target == target]

    def callers(self, function):
        found = {}
        for r in self.refs_to(function):
            root = self.pe.root_of(r.source)
            if r.kind in ("call", "jmp") and root is not None:
                found.setdefault(root, []).append(r.source)
        return found

    def sites_from(self, function, kinds):
        return [r for r in self.refs if r.kind in kinds and self.pe.root_of(r.source) == function]

    def callees(self, function):
        return [], []


def build_client(test, functions, calls=(), refs=(), facts=()):
    """A Client over planted data. functions: start -> (saved name or None, saved C text or None); calls:
    (caller, callee) pairs, each a `call` in the caller's range; refs: more Ref; facts: check_facts.Record."""
    directory = tempfile.TemporaryDirectory()
    test.addCleanup(directory.cleanup)
    names = {}
    for start, (name, text) in functions.items():
        names[start] = name or "FUN_%x" % start
        if text is not None:
            (Path(directory.name) / ("0x%x.c" % start)).write_text("// 0x%x %s made under abc\n\n%s\n" % (start, names[start], text))
    all_refs = [Ref(caller + 0x10 + 4 * n, callee, "call") for n, (caller, callee) in enumerate(calls)] + list(refs)
    state = decompiled.State("abc", names, {})
    return client_trace.Client(FakeIndex(functions, all_refs), Path(directory.name), state, client_trace.Facts({f.key: f for f in facts}))


class ParseSubjectTest(unittest.TestCase):
    def test_an_address_from_the_image_base_up_is_an_address(self):
        self.assertEqual(client_trace.parse_subject("0x1403ec6a0"), client_trace.Subject("address", 0x1403EC6A0))

    def test_a_hex_number_up_to_0xffff_is_an_opcode_in_either_case(self):
        self.assertEqual(client_trace.parse_subject("0x4DB"), client_trace.Subject("opcode", 0x4DB))
        self.assertEqual(client_trace.parse_subject("0x4db"), client_trace.Subject("opcode", 0x4DB))

    def test_a_decimal_number_is_an_opcode(self):
        self.assertEqual(client_trace.parse_subject("1243"), client_trace.Subject("opcode", 0x4DB))

    def test_an_identifier_is_a_name(self):
        self.assertEqual(client_trace.parse_subject("HandleWorldMessage"), client_trace.Subject("name", "HandleWorldMessage"))
        self.assertEqual(client_trace.parse_subject("FUN_14001c280"), client_trace.Subject("name", "FUN_14001c280"))

    def test_a_hex_number_between_the_opcodes_and_the_image_is_refused(self):
        with self.assertRaises(client_trace.Refused):
            client_trace.parse_subject("0x20000")

    def test_a_decimal_number_past_the_opcodes_is_refused(self):
        with self.assertRaises(client_trace.Refused):
            client_trace.parse_subject("70000")

    def test_anything_else_is_refused(self):
        for text in ("", "0x", "two words", "1.5", "-3", "0x14.5"):
            with self.subTest(text=text), self.assertRaises(client_trace.Refused):
                client_trace.parse_subject(text)


class SizeBoundTest(unittest.TestCase):
    def test_text_inside_the_bound_is_returned_as_it_is(self):
        self.assertEqual(client_trace.trim_to("a\nb\nc", 100), "a\nb\nc")

    def test_text_over_the_bound_is_cut_at_a_line_and_says_how_many_lines(self):
        text = "\n".join("line %d" % n for n in range(100))
        cut = client_trace.trim_to(text, 200)
        self.assertLessEqual(len(cut), 200)
        kept = [line for line in cut.split("\n") if line.startswith("line ")]
        self.assertEqual(kept, ["line %d" % n for n in range(len(kept))])
        self.assertIn("[%d of 100 lines cut" % (100 - len(kept)), cut.split("\n")[-1])

    def test_the_report_never_exceeds_the_bound(self):
        parts = [client_trace.Part("header\n" + "fact line\n" * 30)] + [
            client_trace.Part("body %d\n" % n + "code line\n" * 400, shrinkable=True) for n in range(3)
        ]
        for limit in (500, 2000, 5000, 20000):
            with self.subTest(limit=limit):
                self.assertLessEqual(len(client_trace.fit(parts, limit)), limit)

    def test_bodies_share_what_the_other_parts_leave_equally(self):
        parts = [client_trace.Part("x" * 99)] + [client_trace.Part("body %d\n" % n + "z\n" * 3000, shrinkable=True) for n in range(2)]
        fitted = client_trace.fit(parts, 3100)
        second_at = fitted.index("body 1")
        first, second = fitted[fitted.index("body 0") : second_at], fitted[second_at:]
        self.assertAlmostEqual(len(first), len(second), delta=8)
        self.assertGreater(len(first), 1000)

    def test_a_body_with_too_little_room_is_left_out_with_a_note(self):
        parts = [client_trace.Part("f" * 900), client_trace.Part("body\n" + "c\n" * 500, shrinkable=True)]
        fitted = client_trace.fit(parts, 1000)
        self.assertNotIn("body", fitted)
        self.assertIn("1 bodies left out", fitted)

    def test_lists_larger_than_the_bound_are_cut_and_the_bodies_named_as_left_out(self):
        parts = [client_trace.Part("\n".join("row %d" % n for n in range(500))), client_trace.Part("body", shrinkable=True)]
        fitted = client_trace.fit(parts, 1000)
        self.assertLessEqual(len(fitted), 1000)
        self.assertIn("lines cut", fitted)


class GlobalAddressesTest(unittest.TestCase):
    def test_each_global_is_listed_once_in_order_of_first_use(self):
        # the world global 0x140c65898, the clock 0x140c636a8 and the network object 0x140c65808 (fact file records)
        text = "if (DAT_140c65898 == 0) { x = DAT_140c636a8; y = DAT_140c65898; z = PTR_DAT_140c65808; }"
        self.assertEqual(client_trace.global_addresses(text), [0x140C65898, 0x140C636A8, 0x140C65808])

    def test_other_names_are_not_globals(self):
        self.assertEqual(client_trace.global_addresses("FUN_140093580(local_28, PTR_FUN_140b69230); undefined DAT_1;"), [])


class RegistrationTest(unittest.TestCase):
    def test_a_message_the_client_receives_has_a_reader_and_no_writer(self):
        # saved C of 0x14006c290, line 662
        line = "  (**(code **)*puVar1)(puVar1,0x7fb,0x10,0,0,ReadMessage07FBBody,0);"
        self.assertEqual(
            client_trace.parse_registration(line, 0x14006C290, 662),
            client_trace.Registration(0x7FB, 0x10, None, None, "ReadMessage07FBBody", 0x14006C290, 662),
        )

    def test_a_message_the_client_sends_has_a_sizer_and_a_writer_and_no_reader(self):
        # saved C of 0x14006c290, line 644
        line = "  (**(code **)*puVar1)(puVar1,0x4db,0xc,seed_140093570,FUN_140093580,0,0);"
        self.assertEqual(
            client_trace.parse_registration(line, 0x14006C290, 644),
            client_trace.Registration(0x4DB, 0xC, "seed_140093570", "FUN_140093580", None, 0x14006C290, 644),
        )

    def test_a_decimal_id_and_size_are_read(self):
        line = "  (**(code **)*puVar1)(puVar1,3,8,0,0,FUN_1,0);"
        self.assertEqual(client_trace.parse_registration(line, 0x1000, 1).opcode, 3)

    def test_another_line_is_not_a_registration(self):
        for line in ("  SendWorldMessage(param_1,0x4db,&local_28);", "  FUN_140200220(0x4db);", ""):
            with self.subTest(line=line):
                self.assertIsNone(client_trace.parse_registration(line, 0x1000, 1))


def planted_table(jmp, compare, register):
    """A table as jump_tables reads it: its compare's address and the index register that compare tests."""
    return jump_tables.JumpTable(jmp, True, None, 3, 0x500, [0x600] * 3, compare, register)


class TableOriginTest(unittest.TestCase):
    def test_a_lea_of_the_id_minus_a_constant_gives_that_constant(self):
        # HandleWorldMessage: lea eax, [rbx - 0x61] / cmp eax, 0x911 / ja / ... / jmp rcx
        code = [
            instruction(0x10, "lea", "eax", "[rbx - 0x61]"),
            instruction(0x13, "mov", "qword ptr [rsp + 0xd8]", "r14"),
            instruction(0x1B, "cmp", "eax", "0x911"),
            instruction(0x21, "ja", "0x500"),
            instruction(0x40, "jmp", "rcx"),
        ]
        self.assertEqual(client_trace.first_opcode(code, planted_table(0x40, 0x1B, "rax")), 0x61)

    def test_an_add_of_a_wrapped_negative_gives_the_id_it_undoes(self):
        # HandleMessages0966To0980: add r8d, 0xfffff69a / cmp r8d, 0x1a (the messages start at 0x966)
        code = [
            instruction(0x10, "add", "r8d", "0xfffff69a"),
            instruction(0x17, "cmp", "r8d", "0x1a"),
            instruction(0x1B, "ja", "0x500"),
            instruction(0x38, "jmp", "rdx"),
        ]
        self.assertEqual(client_trace.first_opcode(code, planted_table(0x38, 0x17, "r8")), 0x966)

    def test_the_last_write_before_the_compare_is_the_one_read(self):
        # HandleMessages0987To0991: a first lea, a compare, then the lea of the table index (messages start at 0x987)
        code = [
            instruction(0x10, "lea", "eax", "[r8 - 0x986]"),
            instruction(0x17, "cmp", "eax", "0xb"),
            instruction(0x1A, "ja", "0x500"),
            instruction(0x20, "lea", "eax", "[r8 - 0x987]"),
            instruction(0x27, "cmp", "eax", "0xa"),
            instruction(0x2A, "ja", "0x500"),
            instruction(0x41, "jmp", "rcx"),
        ]
        self.assertEqual(client_trace.first_opcode(code, planted_table(0x41, 0x27, "rax")), 0x987)

    def test_a_sub_of_a_constant_gives_that_constant(self):
        code = [
            instruction(0x10, "sub", "eax", "0x3d8"),
            instruction(0x13, "cmp", "eax", "0x14"),
            instruction(0x16, "ja", "0x500"),
            instruction(0x20, "jmp", "rdx"),
        ]
        self.assertEqual(client_trace.first_opcode(code, planted_table(0x20, 0x13, "rax")), 0x3D8)

    def test_an_index_made_any_other_way_is_not_read(self):
        code = [
            instruction(0x10, "imul", "eax", "ecx", "3"),
            instruction(0x13, "cmp", "eax", "0x14"),
            instruction(0x16, "ja", "0x500"),
            instruction(0x20, "jmp", "rdx"),
        ]
        self.assertIsNone(client_trace.first_opcode(code, planted_table(0x20, 0x13, "rax")))

    def test_a_table_whose_compare_is_unknown_is_not_read(self):
        self.assertIsNone(client_trace.first_opcode([instruction(0x20, "jmp", "rdx")], planted_table(0x20, None, None)))

    def test_a_call_between_the_index_write_and_the_compare_hides_the_origin(self):
        # a call clobbers eax (a volatile register), so the lea before it did not make the compared value
        code = [
            instruction(0x10, "lea", "eax", "[rbx - 0x61]"),
            instruction(0x13, "call", "0x700"),
            instruction(0x18, "cmp", "eax", "0x911"),
            instruction(0x1E, "ja", "0x500"),
            instruction(0x40, "jmp", "rcx"),
        ]
        self.assertIsNone(client_trace.first_opcode(code, planted_table(0x40, 0x18, "rax")))

    def test_the_origin_is_the_index_registers_not_the_nearest_compare(self):
        # the table's index is eax (compared at 0x13); a later compare of edx must not be taken for it
        code = [
            instruction(0x10, "lea", "eax", "[rbx - 0x61]"),
            instruction(0x13, "cmp", "eax", "0x911"),
            instruction(0x19, "ja", "0x500"),
            instruction(0x1B, "sub", "edx", "0x9"),
            instruction(0x1E, "cmp", "edx", "0x4"),
            instruction(0x21, "ja", "0x500"),
            instruction(0x40, "jmp", "rcx"),
        ]
        self.assertEqual(client_trace.first_opcode(code, planted_table(0x40, 0x13, "rax")), 0x61)


class CaseBlockTest(unittest.TestCase):
    functions = {0x500, 0x600}

    def test_the_calls_of_a_case_are_listed_to_its_jmp_and_a_tail_call_ends_it(self):
        code = [
            instruction(0x100, "mov", "edx", "dword ptr [rdi]"),
            instruction(0x103, "call", "0x500"),
            instruction(0x108, "je", "0x900"),
            instruction(0x10A, "call", "0x700"),
            instruction(0x10F, "jmp", "0x600"),
            instruction(0x114, "call", "0x500"),
        ]
        calls, ends_at = client_trace.case_block(code, 0x100, lambda a: a in self.functions)
        self.assertEqual(calls, [(0x103, 0x500), (0x10F, 0x600)])
        self.assertEqual(ends_at, "a jmp at 0x10f")

    def test_a_case_that_is_not_in_the_listing_says_so(self):
        calls, ends_at = client_trace.case_block([instruction(0x100, "ret")], 0x200, lambda a: True)
        self.assertEqual(calls, [])
        self.assertIn("not in the listing", ends_at)


class FactsForAnOpcodeTest(unittest.TestCase):
    def test_the_opcode_record_and_its_sub_records_are_found_and_no_other(self):
        def record(key):
            return check_facts.Record(key, "s", "p", "guess", "g", None)

        keys = ["opcode.0x4db", "opcode.0x4db.held", "opcode.0x4dba", "opcode.0x4d", "0x1403bd8b0", "cast.hold_repeat"]
        facts = client_trace.Facts({k: record(k) for k in keys})
        self.assertEqual([r.key for r in facts.for_opcode(0x4DB)], ["opcode.0x4db", "opcode.0x4db.held"])


class FactsCitingTest(unittest.TestCase):
    def test_a_record_is_found_by_each_address_its_text_names_and_not_by_its_own_key(self):
        def record(key, statement):
            return check_facts.Record(key, statement, "proof", "guess", None, None)

        facts = client_trace.Facts(
            {
                "opcode.0x7fb": record("opcode.0x7fb", "HandleWorldMessage case: 0x1403EE1FE calls 0x14053f090"),
                "0x14053f090": record("0x14053f090", "reads the cast; see 0x14053f090 and 0x1403ee1fe"),
            }
        )
        self.assertEqual([r.key for r in facts.citing(0x1403EE1FE)], ["opcode.0x7fb", "0x14053f090"])
        self.assertEqual([r.key for r in facts.citing(0x14053F090)], ["opcode.0x7fb"])
        self.assertEqual(facts.citing(0x140000001), [])
        self.assertEqual(facts.keyed(0x14053F090).key, "0x14053f090")


class LevelsTest(unittest.TestCase):
    graph = {1: [2, 3], 2: [3, 4], 3: [], 4: [1]}

    def test_each_function_is_listed_once_at_the_first_level_that_reaches_it(self):
        levels = client_trace._levels(lambda at: self.graph[at], 1, 3)
        self.assertEqual(levels, [[(2, 1), (3, 1)], [(4, 2)]])

    def test_the_walk_stops_at_the_depth(self):
        self.assertEqual(client_trace._levels(lambda at: self.graph[at], 1, 1), [[(2, 1), (3, 1)]])


class SharedCallPathsTest(unittest.TestCase):
    A, B, C = 0x140001000, 0x140002000, 0x140003000

    def index(self):
        return FakeIndex(
            [self.A, self.B, self.C],
            [
                Ref(self.A + 0x10, self.B, "call"),
                Ref(self.A + 0x20, self.B, "call"),
                Ref(self.A + 0x30, self.C, "jmp"),
                Ref(self.A + 0x40, self.A, "call"),
                Ref(self.A + 0x50, 0x140009999, "call"),
                Ref(self.A + 0x60, self.B, "rip-lea"),
            ],
        )

    def test_callee_sites_gives_each_function_a_range_calls_with_its_sites_and_leaves_out_itself(self):
        index = self.index()
        found = call_paths.callee_sites(index, set(index.pe.starts), self.A)
        self.assertEqual(found, {self.B: [self.A + 0x10, self.A + 0x20], self.C: [self.A + 0x30]})

    def test_reference_phrases_name_what_is_not_a_call_from_another_function(self):
        index = FakeIndex(
            [self.A, self.B],
            [
                Ref(self.B + 0x10, self.A, "call"),
                Ref(self.B + 0x20, self.A, "rip-lea"),
                Ref(self.A + 0x30, self.A, "call"),
                Ref(0x140900000, self.A, "jmp"),
                Ref(0x140900008, self.A, "pointer"),
            ],
        )
        self.assertEqual(
            call_paths.reference_phrases(index, self.A),
            ["rip-lea at 0x140002020", "call from itself at 0x140001030", "jmp from code outside .pdata at 0x140900000", "pointer at 0x140900008"],
        )
        self.assertEqual(call_paths.reference_phrases(index, self.A, lambda root: "0x%x" % root)[0], "rip-lea at 0x140002020 in 0x140002000")


@cs.needs_client
class DispatchTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pe = ClientPE(cs.client_exe())
        cls.index_functions = set(cls.pe.function_starts())

    def cases(self, dispatcher, opcode):
        return client_trace.dispatch_cases(self.pe, dispatcher, opcode, lambda a: a in self.index_functions)

    def test_message_0x7fb_is_the_case_the_fact_file_records_in_the_world_dispatcher(self):
        # fact file record opcode.0x7fb: "HandleWorldMessage case: 0x1403ee1fe ... call 0x14053f090"
        (block,) = self.cases(0x1403EC6A0, 0x7FB)
        self.assertEqual(block.target, 0x1403EE1FE)
        self.assertIn(0x14053F090, [callee for _site, callee in block.calls])

    def test_message_0x96b_is_the_case_the_fact_file_records_in_the_0966_to_0980_dispatcher(self):
        # fact file: "Table entry 5 at 0x140004414 is RVA 0x40fd. 0x1400040fd mov rdx, rbx"; it tail-calls 0x140004f60
        (block,) = self.cases(0x140003FB0, 0x96B)
        self.assertEqual(block.target, 0x1400040FD)
        self.assertEqual([callee for _site, callee in block.calls], [0x140004F60])

    def test_a_message_outside_the_table_has_no_case(self):
        # 0x4db is a message the client sends; the 27-case table holds 0x966 to 0x980
        self.assertEqual(self.cases(0x140003FB0, 0x4DB), [])
        self.assertEqual(self.cases(0x140003FB0, 0x981), [])


if __name__ == "__main__":
    unittest.main()
