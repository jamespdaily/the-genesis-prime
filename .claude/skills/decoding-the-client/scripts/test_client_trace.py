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

    def read(self, address, size):
        return b"\x90" * size  # no function holds an indirect jmp, so no jump table is read


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

    def test_a_body_smaller_than_its_share_gives_the_rest_to_the_others(self):
        small = "small body\n" + "s\n" * 19
        parts = [client_trace.Part("head"), client_trace.Part(small, shrinkable=True), client_trace.Part("big body\n" + "b%d\n" % 1 * 10000, shrinkable=True)]
        fitted = client_trace.fit(parts, 3000)
        self.assertIn(small, fitted)
        self.assertLessEqual(len(fitted), 3000)
        self.assertGreater(len(fitted), 2900)

    def test_a_body_with_too_little_room_is_left_out_with_a_note(self):
        parts = [client_trace.Part("f" * 500), client_trace.Part("body\n" + "c\n" * 500, shrinkable=True)]
        fitted = client_trace.fit(parts, 1000)
        self.assertNotIn("body", fitted)
        self.assertIn("1 bodies left out", fitted)
        self.assertLessEqual(len(fitted), 1000)

    def test_the_note_of_a_left_out_body_fits_inside_the_bound_when_the_lists_nearly_fill_it(self):
        # a list part of 979 characters and a limit of 1000 left the note 48 characters over the bound
        parts = [client_trace.Part("f" * 979), client_trace.Part("body\n" + "c\n" * 500, shrinkable=True)]
        fitted = client_trace.fit(parts, 1000)
        self.assertLessEqual(len(fitted), 1000)
        self.assertIn("1 bodies left out", fitted.split("\n")[-1])

    def test_lists_larger_than_the_bound_are_cut_and_the_bodies_named_as_left_out(self):
        parts = [client_trace.Part("\n".join("row %d" % n for n in range(500))), client_trace.Part("body", shrinkable=True)]
        fitted = client_trace.fit(parts, 1000)
        self.assertLessEqual(len(fitted), 1000)
        self.assertIn("lines cut", fitted)
        self.assertIn("1 bodies left out", fitted.split("\n")[-1])


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
        self.assertEqual(facts.citing(0x150000001), [])
        self.assertEqual(facts.keyed(0x14053F090).key, "0x14053f090")


class LevelsTest(unittest.TestCase):
    graph = {1: [2, 3], 2: [3, 4], 3: [], 4: [1]}

    def test_each_function_is_listed_once_at_the_first_level_that_reaches_it(self):
        levels = client_trace._levels(lambda at: self.graph[at], 1, 3)
        self.assertEqual(levels, [[(2, 1), (3, 1)], [(4, 2)]])

    def test_the_walk_stops_at_the_depth(self):
        self.assertEqual(client_trace._levels(lambda at: self.graph[at], 1, 1), [[(2, 1), (3, 1)]])


class SharedCallPathsTest(unittest.TestCase):
    A, B, C = 0x150001000, 0x150002000, 0x150003000

    def index(self):
        return FakeIndex(
            [self.A, self.B, self.C],
            [
                Ref(self.A + 0x10, self.B, "call"),
                Ref(self.A + 0x20, self.B, "call"),
                Ref(self.A + 0x30, self.C, "jmp"),
                Ref(self.A + 0x40, self.A, "call"),
                Ref(self.A + 0x50, 0x150009999, "call"),
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
                Ref(0x150900000, self.A, "jmp"),
                Ref(0x150900008, self.A, "pointer"),
            ],
        )
        self.assertEqual(
            call_paths.reference_phrases(index, self.A),
            ["rip-lea at 0x150002020", "call from itself at 0x150001030", "jmp from code outside .pdata at 0x150900000", "pointer at 0x150900008"],
        )
        self.assertEqual(call_paths.reference_phrases(index, self.A, lambda root: "0x%x" % root)[0], "rip-lea at 0x150002020 in 0x150002000")


LOGIN = 0x1400370D0
MESSAGE_03DB = 0x140037F30
REGISTERING = 0x14006C290
READER_03DB = 0x150100000
WRITER_04DB = 0x140093580
CASE_HOLDER = 0x150607D10
LOGIN_C = """undefined8 HandleLoginMessage(longlong param_1,int param_2,int param_3,uint *param_4)

{
  undefined8 uVar1;

    if (param_3 == 3) {
      uVar1 = CheckAuthServerVersion(param_1,param_4);
      return uVar1;
    }
    if (param_3 == 0x3db) {
      uVar1 = HandleMessage03DB(param_1,param_4);
      return uVar1;
    }
    if (param_3 == 0x3ef) {
      return 0;
    }
}"""
REGISTRATIONS_C = """void FUN_14006c290(void)

{
  (**(code **)*puVar1)(puVar1,0x3db,0x38,0,0,ReadMessage03DBBody,0);
  (**(code **)*puVar1)(puVar1,0x4db,0xc,seed_140093570,FUN_140093580,0,0);
  (**(code **)*puVar1)(puVar1,0x4da,0xc,0,0,ReadMessage04DABody,0);
  (**(code **)*puVar1)(puVar1,0x4dc,0xc,0,0,ReadMessage04DCBody,0);
}"""
CASE_C = """void FUN_150607d10(longlong *param_1,undefined8 param_2,undefined4 *param_3,int param_4)

{
  switch(*param_3) {
    case 0x4da:
    case 0x4db:
    case 0x4dc:
      break;
    case 0x507:
      local_48 = 0x506;
      (**(code **)(*param_1 + 0x248))(DAT_140b79ed0,0,&local_48);
      return;
  }
  return;
}"""


def opcode_text(client, opcode, depth=1, limit=50000, extra=()):
    parts, found = client_trace.opcode_parts(client, opcode, depth, list(extra))
    return client_trace.fit(parts, limit), found


def login_client(test, extra_functions=None, facts=()):
    functions = {
        LOGIN: ("HandleLoginMessage", LOGIN_C),
        MESSAGE_03DB: ("HandleMessage03DB", "undefined8 HandleMessage03DB(longlong param_1,undefined4 *param_2)\n\n{\n  return 0;\n}"),
        REGISTERING: (None, REGISTRATIONS_C),
        READER_03DB: ("ReadMessage03DBBody", "void ReadMessage03DBBody(void)\n\n{\n}"),
        WRITER_04DB: (None, "void FUN_140093580(void)\n\n{\n}"),
        CASE_HOLDER: (None, CASE_C),
    }
    functions.update(extra_functions or {})
    return build_client(test, functions, [(LOGIN, MESSAGE_03DB)], facts=facts)


class HandlerTest(unittest.TestCase):
    def test_a_message_a_named_dispatcher_tests_with_equals_is_handled_there_and_its_callee_is_traced(self):
        # saved C of 0x1400370d0 line 29: `if (param_3 == 0x3db) {` then HandleMessage03DB(param_1,param_4)
        text, found = opcode_text(login_client(self), 0x3DB)
        self.assertTrue(found)
        handled = text[text.index("handled by") :]
        self.assertIn("0x1400370d0 HandleLoginMessage line ", handled)
        self.assertIn("if (param_3 == 0x3db) {", handled)
        self.assertIn("calls: 0x140037f30 HandleMessage03DB", handled)
        self.assertIn("== 0x140037f30 HandleMessage03DB", text)

    def test_a_function_named_for_the_message_is_a_handler(self):
        client = build_client(self, {MESSAGE_03DB: ("HandleMessage03DB", "undefined8 HandleMessage03DB(void)\n\n{\n}")})
        text, found = opcode_text(client, 0x3DB)
        self.assertTrue(found)
        self.assertIn("0x140037f30 HandleMessage03DB (named for the message)", text)

    def test_a_case_label_of_a_message_the_client_sends_is_listed_with_its_shared_block(self):
        # saved C of FUN_140607d10 line 141: `case 0x4db:` among the labels of a switch whose group runs to `break;`
        text, found = opcode_text(login_client(self), 0x4DB)
        self.assertTrue(found)
        handled = text[text.index("handled by") :]
        self.assertIn("0x150607d10 line ", handled)
        self.assertIn("case 0x4db:", handled)
        self.assertIn("one of 3 case labels sharing a block: break;", handled)

    def test_a_number_a_function_compares_without_anything_tying_it_to_a_message_is_not_a_handler(self):
        client = build_client(self, {0x140009D00: ("MainWindowProc", "LRESULT MainWindowProc(void)\n\n{\n  switch(uMsg) {\n    case 7:\n      return 0;\n  }\n}")})
        text, found = opcode_text(client, 7)
        self.assertFalse(found)
        self.assertNotIn("handled by (", text)
        self.assertIn("equal numbers", text)
        self.assertIn("MainWindowProc", text)

    def test_a_longer_number_that_starts_with_the_opcode_is_not_a_handler(self):
        client = build_client(self, {LOGIN: ("HandleLoginMessage", "void HandleLoginMessage(void)\n\n{\n  if (param_3 == 0x3dbc) {\n    return 0;\n  }\n}")})
        text, found = opcode_text(client, 0x3DB)
        self.assertFalse(found)
        self.assertNotIn("handled by (", text)


class ExitStatusTest(unittest.TestCase):
    def alloc_client(self, count):
        functions = {
            0x150100000 + 0x1000 * n: (None, "void FUN_%x(void)\n\n{\n  pvVar1 = AllocMemory(0xfff0,0);\n}" % (0x150100000 + 0x1000 * n))
            for n in range(count)
        }
        return build_client(self, functions)

    def test_an_opcode_seen_only_as_an_argument_constant_ties_to_no_message_and_exits_1(self):
        # AllocMemory(0xfff0,0): the client's allocation size, not a message
        out = io.StringIO()
        self.assertEqual(client_trace.run(self.alloc_client(2), "0xfff0", 1, 20000, [], out), 1)
        text = out.getvalue()
        self.assertIn("nothing ties 0xfff0 to a message", text)
        self.assertIn("equal numbers", text)

    def test_the_equal_numbers_are_listed_under_their_label_and_bounded(self):
        out = io.StringIO()
        client_trace.run(self.alloc_client(10), "0xfff0", 1, 50000, [], out)
        listed = [line for line in out.getvalue().split("\n") if line.startswith("  other ")]
        self.assertEqual(len(listed), client_trace.MAX_OTHER_USES)
        self.assertIn("and 4 more functions", out.getvalue())

    def test_the_label_counts_the_functions_that_pass_the_number_and_the_functions_that_compare_it(self):
        functions = {
            0x150100000: (None, "void FUN_150100000(void)\n\n{\n  pvVar1 = AllocMemory(0xfff0,0);\n  pvVar2 = AllocMemory(0xfff0,1);\n}"),
            0x150101000: (None, "void FUN_150101000(void)\n\n{\n  pvVar1 = AllocMemory(0xfff0,0);\n}"),
            0x150102000: (None, "void FUN_150102000(void)\n\n{\n  switch(x) {\n    case 0xfff0:\n      return;\n  }\n}"),
        }
        out = io.StringIO()
        client_trace.run(build_client(self, functions), "0xfff0", 1, 20000, [], out)
        self.assertIn("(2 functions pass it as a call argument, 1 compare or switch on it)", out.getvalue())

    def test_a_sender_ties_the_number_to_a_message_and_exits_0(self):
        sender = {0x150200000: (None, "void FUN_150200000(void)\n\n{\n  SendWorldMessage(param_1,0x4db,&local_28);\n}")}
        out = io.StringIO()
        self.assertEqual(client_trace.run(build_client(self, sender), "0x4db", 1, 20000, [], out), 0)
        self.assertIn("sent by", out.getvalue())
        self.assertNotIn("nothing ties", out.getvalue())

    def test_a_fact_record_for_the_opcode_ties_it_and_exits_0(self):
        record = check_facts.Record("opcode.0x7fb", "Message 0x7fb", "proof", "sure", None, None)
        out = io.StringIO()
        self.assertEqual(client_trace.run(build_client(self, {0x150200000: (None, None)}, facts=[record]), "0x7fb", 1, 20000, [], out), 0)

    def test_a_registration_ties_it_and_exits_0(self):
        out = io.StringIO()
        self.assertEqual(client_trace.run(login_client(self), "0x4db", 1, 20000, [], out), 0)
        self.assertIn("registered:", out.getvalue())


class MainTest(unittest.TestCase):
    def run_main(self, argv, client):
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(client_trace, "open_client", return_value=client), mock.patch("sys.stderr", err):
            return client_trace.main(argv, env={}, out=out), out.getvalue(), err.getvalue()

    def test_a_function_name_is_traced_and_the_status_is_0(self):
        status, out, _err = self.run_main(["HandleLoginMessage"], login_client(self))
        self.assertEqual(status, 0)
        self.assertIn("== 0x1400370d0 HandleLoginMessage", out)

    def test_a_name_the_saved_c_does_not_hold_is_refused_with_close_names_and_status_1(self):
        status, out, err = self.run_main(["HandleLoginMessge"], login_client(self))
        self.assertEqual(status, 1)
        self.assertEqual(out, "")
        self.assertIn("no function is named HandleLoginMessge", err)
        self.assertIn("close: HandleLoginMessage", err)

    def test_an_unknown_dispatcher_is_refused_with_status_1(self):
        status, _out, err = self.run_main(["0x3db", "--dispatcher", "NoSuchDispatcher"], login_client(self))
        self.assertEqual(status, 1)
        self.assertIn("NoSuchDispatcher", err)

    def test_an_input_that_is_none_of_the_forms_is_refused_with_status_1(self):
        status, _out, err = self.run_main(["0x20000"], login_client(self))
        self.assertEqual(status, 1)
        self.assertIn("neither an opcode", err)

    def test_an_opcode_nothing_ties_exits_1_and_still_prints_the_report(self):
        status, out, _err = self.run_main(["0xfff0"], login_client(self))
        self.assertEqual(status, 1)
        self.assertIn("nothing ties 0xfff0 to a message", out)

    def test_a_depth_out_of_range_is_refused_by_the_parser(self):
        with self.assertRaises(SystemExit) as raised, mock.patch("sys.stderr", io.StringIO()):
            client_trace.main(["0x3db", "--depth", "9"], env={}, out=io.StringIO())
        self.assertEqual(raised.exception.code, 2)

    def test_a_folder_with_no_saved_c_is_refused_with_status_1(self):
        with tempfile.TemporaryDirectory() as empty:
            err = io.StringIO()
            with mock.patch("sys.stderr", err):
                status = client_trace.main(["0x3db"], env={"GENESIS_DECOMPILED_DIR": empty}, out=io.StringIO())
        self.assertEqual(status, 1)
        self.assertIn("no saved C", err.getvalue())


class FunctionPartsTest(unittest.TestCase):
    A, B, C = 0x140001000, 0x150002000, 0x150003000

    def client(self, c_text="void FUN_140001000(void)\n\n{\n}", facts=()):
        functions = {self.A: (None, c_text), self.B: ("Callee", "void Callee(void)\n\n{\n}"), self.C: (None, "void FUN_150003000(void)\n\n{\n}")}
        return build_client(self, functions, [(self.A, self.B), (self.A, self.C), (self.C, self.B)], facts=facts)

    def text(self, client, function, depth=1, registrations=(), compact=False):
        return "\n".join(part.text for part in client_trace.function_parts(client, function, depth, list(registrations), compact))

    def test_a_function_lists_its_callers_and_callees_with_their_call_sites(self):
        text = self.text(self.client(), self.B)
        self.assertIn("called by (2 functions):", text)
        self.assertIn("0x140001000  (call at 0x140001010)", text)
        self.assertIn("0x150003000  (call at 0x150003018)", text)
        self.assertIn("calls (0 functions):", text)
        self.assertIn("calls (2 functions):", self.text(self.client(), self.A))

    def test_the_registration_that_names_a_function_is_said_with_its_role_and_place(self):
        registration = client_trace.Registration(0x4DB, 0xC, None, "Callee", None, REGISTERING, 7)
        text = self.text(self.client(), self.B, registrations=[registration])
        self.assertIn("registered as the writer of message 0x4db (record 12 bytes) in 0x14006c290 line 7", text)

    def test_a_function_with_no_table_column_record_says_the_saved_c_reads_records_by_offset(self):
        text = self.text(self.client(), self.A)
        self.assertIn("no table column recorded for this function (the saved C reads records by offset)", text)

    def test_a_function_a_table_column_record_cites_shows_the_record_and_not_the_gap_line(self):
        record = check_facts.Record("Creature2.donutDrawDistance", "read at 0x140001000 as a float", "proof", "guess", None, None)
        text = self.text(self.client(facts=[record]), self.A)
        self.assertIn("(table column or enum) Creature2.donutDrawDistance [guess]", text)
        self.assertNotIn("no table column recorded", text)

    def test_the_gap_line_is_given_in_the_compact_form_too(self):
        self.assertIn("no table column recorded", self.text(self.client(), self.A, compact=True))

    def test_inline_strings_and_string_symbols_are_listed(self):
        # saved C of 0x140056d60 lines 35-43 holds these symbols and no inline literal; u_BGColor_140a31b38 is a wide string's label
        body = (
            'void FUN_140001000(void)\n\n{\n  puVar7 = PTR_s_number_140a123c8;\n  pcVar6 = s_no_value_140c1dc88;\n'
            '  FUN_140058780(param_1,s__s_expected__got__s_140c1db70,puVar7,pcVar6);\n  x = u_BGColor_140a31b38;\n  y = "plain";\n}'
        )
        text = self.text(self.client(body), self.A)
        strings = next(line for line in text.split("\n") if line.startswith("strings: "))
        for held in ("s_no_value_140c1dc88", "s__s_expected__got__s_140c1db70", "PTR_s_number_140a123c8", "u_BGColor_140a31b38", '"plain"'):
            self.assertIn(held, strings)

    def test_a_name_that_only_looks_like_a_string_symbol_is_not_listed(self):
        body = "void FUN_140001000(void)\n\n{\n  x = s_value_1;\n  y = FUN_140058780(1);\n  z = s_no_value_140c1dc8;\n}"
        text = self.text(self.client(body), self.A)
        self.assertNotIn("strings: ", text)


class TrimmedOutputSaysSoTest(unittest.TestCase):
    def test_globals_with_more_than_forty_other_users_are_counted_as_left_out(self):
        # planted: 41 other functions read DAT_140c65898 (the world global), and 2 read DAT_140c636a8 (the clock)
        starts = [0x150100000 + 0x1000 * n for n in range(43)]
        functions = {start: (None, "void FUN_%x(void)\n\n{\n}" % start) for start in starts}
        functions[starts[0]] = (None, "void FUN_%x(void)\n\n{\n  a = DAT_140c65898;\n  b = DAT_140c636a8;\n}" % starts[0])
        refs = [Ref(start + 0x20, 0x140C65898, "rip-data") for start in starts[1:42]] + [Ref(start + 0x20, 0x140C636A8, "rip-data") for start in starts[1:3]]
        client = build_client(self, functions, refs=refs)
        text = "\n".join(part.text for part in client_trace.function_parts(client, starts[0], 1, []))
        self.assertIn("DAT_140c636a8: 2 other function(s)", text)
        self.assertNotIn("DAT_140c65898:", text)
        self.assertIn("1 global used by more than 40 other functions is left out", text)

    def senders(self, count):
        functions = {
            0x150200000 + 0x1000 * n: (None, "void FUN_%x(void)\n\n{\n  SendWorldMessage(param_1,0x4db,&local_28);\n}" % (0x150200000 + 0x1000 * n))
            for n in range(count)
        }
        return build_client(self, functions)

    def test_senders_past_the_fourth_are_listed_but_say_they_are_not_traced(self):
        text, _found = opcode_text(self.senders(6), 0x4DB)
        self.assertEqual(text.count("  sender "), 6)
        self.assertIn("2 senders past the first 4 are listed but not traced", text)
        self.assertEqual(text.count("== 0x1502"), 4)

    def test_four_senders_need_no_note(self):
        text, _found = opcode_text(self.senders(4), 0x4DB)
        self.assertNotIn("not traced", text)

    def test_case_callees_past_the_fourth_say_they_are_not_traced(self):
        callees = {0x150300000 + 0x1000 * n: (None, "void FUN_%x(void)\n\n{\n}" % (0x150300000 + 0x1000 * n)) for n in range(6)}
        dispatcher = {0x1403EC6A0: ("HandleWorldMessage", "void HandleWorldMessage(void)\n\n{\n}")}
        client = build_client(self, {**callees, **dispatcher})
        block = client_trace.CaseBlock(0x1403EC6A0, 0x1503EC700, 0x1403EE1FE, [(0x1503EE200 + 5 * n, a) for n, a in enumerate(callees)], "a jmp at 0x1503ee300")
        with mock.patch.object(client_trace, "dispatch_cases", return_value=[block]):
            text, found = opcode_text(client, 0x7FB)
        self.assertTrue(found)
        self.assertIn("2 callees of the case past the first 4 are listed but not traced", text)
        self.assertEqual(text.count("== 0x1503"), 4)

    def test_callee_bodies_past_the_sixth_at_depth_2_say_they_are_left_out(self):
        caller = 0x140001000
        callees = {0x150400000 + 0x1000 * n: (None, "void FUN_%x(void)\n\n{\n}" % (0x150400000 + 0x1000 * n)) for n in range(8)}
        client = build_client(self, {caller: (None, "void FUN_140001000(void)\n\n{\n}"), **callees}, [(caller, callee) for callee in callees])
        parts = client_trace.function_parts(client, caller, 2, [])
        self.assertEqual(len([p for p in parts if p.shrinkable]), 1 + client_trace.MAX_CALLEE_BODIES)
        self.assertIn("the bodies of 2 callees past the first 6 are left out", "\n".join(p.text for p in parts))

    def test_six_callee_bodies_need_no_note(self):
        caller = 0x140001000
        callees = {0x150400000 + 0x1000 * n: (None, "void FUN_%x(void)\n\n{\n}" % (0x150400000 + 0x1000 * n)) for n in range(6)}
        client = build_client(self, {caller: (None, "void FUN_140001000(void)\n\n{\n}"), **callees}, [(caller, callee) for callee in callees])
        self.assertNotIn("left out", "\n".join(p.text for p in client_trace.function_parts(client, caller, 2, [])))


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


def _saved_c_present():
    try:
        return (decompiled.copy_directory(os.environ) / decompiled.STATE_FILE).is_file()
    except decompiled.Refused:
        return False


PLANTED_SAVED_CASE_HOLDER = 0x140607D10
needs_saved_c = unittest.skipUnless(not cs.NO_CLIENT and _saved_c_present(), "the client and its saved C are not on this machine")


@needs_saved_c
class SavedClientTest(unittest.TestCase):
    """The saved C of the client; the expected values are lines of it and the fact file's records."""

    @classmethod
    def setUpClass(cls):
        cls.client = client_trace.open_client(os.environ)

    def report(self, subject, limit=24000):
        out = io.StringIO()
        status = client_trace.run(self.client, subject, 1, limit, [], out)
        return status, out.getvalue()

    def test_message_0x3db_is_handled_by_the_login_dispatcher_and_handle_message_03db(self):
        # saved C of 0x1400370d0 line 29: `if (param_3 == 0x3db) {` calling HandleMessage03DB
        status, text = self.report("0x3db")
        self.assertEqual(status, 0)
        self.assertIn("0x1400370d0 HandleLoginMessage line 29: if (param_3 == 0x3db) {", text)
        self.assertIn("0x140037f30 HandleMessage03DB", text)
        self.assertIn("== 0x140037f30 HandleMessage03DB", text)

    def test_message_0x4db_has_the_case_label_of_the_switch_in_fun_140607d10(self):
        # saved C of FUN_140607d10 line 141: `case 0x4db:`
        status, text = self.report("0x4db")
        self.assertEqual(status, 0)
        self.assertIn("0x%x line 141: case 0x4db:" % PLANTED_SAVED_CASE_HOLDER, text)

    def test_the_number_7_is_no_message_and_exits_1_with_a_bounded_list(self):
        status, text = self.report("7")
        self.assertEqual(status, 1)
        self.assertIn("nothing ties 0x7 to a message", text)
        self.assertLessEqual(len([line for line in text.split("\n") if line.startswith("  other ")]), client_trace.MAX_OTHER_USES)

    def test_the_allocation_size_0xfff0_is_no_message_and_exits_1(self):
        # AllocMemory(0xfff0,0) in the saved C
        status, text = self.report("0xfff0")
        self.assertEqual(status, 1)
        self.assertIn("nothing ties 0xfff0 to a message", text)

    def test_a_function_that_names_its_strings_by_symbol_lists_them(self):
        # saved C of 0x140056d60 lines 35 to 43
        status, text = self.report("0x140056d60")
        self.assertEqual(status, 0)
        strings = next(line for line in text.split("\n") if line.startswith("strings: "))
        self.assertIn("s_no_value_140c1dc88", strings)
        self.assertIn("s__s_expected__got__s_140c1db70", strings)

    def test_message_0x7fb_keeps_the_world_dispatcher_case_and_exits_0(self):
        status, text = self.report("0x7fb")
        self.assertEqual(status, 0)
        self.assertIn("case at 0x1403ee1fe", text)


if __name__ == "__main__":
    unittest.main()
