"""The query process's `decompile` and `disassemble` requests, as ghidra_query.py documents them.

Integration tests: they run only when GENESIS_INTEGRATION=1 (see
test_query_process.py for the environment) and open the project built by
check_support.seeded_project().

The requests and replies:
  {"kind": "decompile", "function": "0x140283670" [, "timeout_s": 60]}
      -> {"signature": "<C prototype>", "c": "<C text>"}
  {"kind": "disassemble", "function": "0x1400c2d10"}
  {"kind": "disassemble", "start": "0x...", "stop": "0x..."}      (the range is [start, stop))
      -> [{"address": "0x...", "bytes": "<hex>", "text": "<Ghidra syntax>"}, ...] in address order

Expected values come from independent readings of WildStar64.exe (SHA-256
565c2fa1...fe0b10): the PE import table (client_pe), the .pdata function table
and llvm-objdump's listing of it, and the file's own bytes.
Run: GENESIS_INTEGRATION=1 python3 -I test_code_requests.py
"""

import os
import subprocess
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_support as cs  # noqa: E402
from check_support import hx  # noqa: E402
from client_refs import LINE_RE  # noqa: E402

FN_FIVE_IMPORTS = 0x140283670  # fact file record 0x140283670
FIVE_IMPORTS = [
    "gdi32.dll!AddFontMemResourceEx",
    "kernel32.dll!DebugBreak",
    "kernel32.dll!GetLastError",
    "kernel32.dll!TlsGetValue",
    "kernel32.dll!TlsSetValue",
]
FN_ENCRYPT = 0x1400C2D10  # EncryptMessageBody (fact file record 0x1400c2d10)
MAX_RANGE = 1 << 20
# fact file record 0x1404e5760: `call 0x14003b4f0` at 0x1404e576d, five bytes, to a .pdata start
CALL_SITE = 0x1404E576D
CALLED = 0x14003B4F0


def objdump_addresses(low: int, high: int) -> list[int]:
    """The address of each instruction llvm-objdump lists in [low, high)."""
    out = subprocess.run(
        [
            str(cs.objdump()), "-d", "--no-show-raw-insn", "--x86-asm-syntax=intel",
            "--start-address=0x%x" % low, "--stop-address=0x%x" % high, str(cs.client_exe()),
        ],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    return [int(m.group(1), 16) for m in map(LINE_RE.match, out.splitlines()) if m]


@cs.integration_only
class DecompileTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pe = cs.client_pe()
        cls.qp = cs.QueryProcess(cs.seeded_project().project_dir)
        cls.qp.ask("seed_report")

    @classmethod
    def tearDownClass(cls):
        cls.qp.close()

    def assert_still_answering(self):
        self.assertEqual(
            self.qp.ask("bytes", address="0x1404a4e30", length=16).answer, "48895c24084889742410574883ec4041"
        )
        self.assertIn("{", self.qp.ask("decompile", function=hx(FN_FIVE_IMPORTS)).answer["c"])

    def test_the_c_of_0x140283670_names_each_of_its_five_imports_and_the_pe_import_table_lists_them(self):
        in_the_table = set(self.pe.imports().values())
        answer = self.qp.ask("decompile", function=hx(FN_FIVE_IMPORTS)).answer
        self.assertIsInstance(answer["signature"], str)
        self.assertNotEqual(answer["signature"], "")
        for name in FIVE_IMPORTS:
            with self.subTest(name=name):
                self.assertIn(name, in_the_table)
                self.assertIn(name.split("!")[1], answer["c"])

    def test_an_address_where_no_function_starts_gets_an_error_reply_and_the_next_request_is_answered(self):
        inside = FN_FIVE_IMPORTS + 1  # inside the function, where no function starts
        reply = self.qp.ask("decompile", function=hx(inside))
        self.assertIs(reply.body["ok"], False)
        self.assertIn(hx(inside), reply.body["error"])
        self.assert_still_answering()

    def test_a_timeout_that_is_not_finite_or_over_an_hour_gets_an_error_reply_and_the_next_request_is_answered(self):
        for timeout in (float("inf"), 7200):
            with self.subTest(timeout=timeout):
                reply = self.qp.ask("decompile", function=hx(FN_FIVE_IMPORTS), timeout_s=timeout)
                self.assertIs(reply.body["ok"], False)
                self.assertIn("timeout_s", reply.body["error"])
        self.assert_still_answering()

    def test_a_timeout_of_a_thousandth_of_a_second_gets_an_error_reply_naming_the_timeout_and_the_next_request_is_answered(self):
        reply = self.qp.ask("decompile", function=hx(FN_FIVE_IMPORTS), timeout_s=0.001)
        self.assertIs(reply.body["ok"], False)
        self.assertIn("timeout", reply.body["error"])
        self.assert_still_answering()


@cs.integration_only
class DisassembleTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pe = cs.client_pe()
        cls.qp = cs.QueryProcess(cs.seeded_project().project_dir)
        cls.qp.ask("seed_report")

    @classmethod
    def tearDownClass(cls):
        cls.qp.close()

    def function_listing(self) -> list[dict]:
        return self.qp.ask("disassemble", function=hx(FN_ENCRYPT)).answer

    def test_encrypt_message_body_by_function_lists_the_addresses_llvm_objdump_lists_over_its_pdata_range(self):
        want = sorted(a for low, high in self.pe.root_ranges(FN_ENCRYPT) for a in objdump_addresses(low, high))
        listing = self.function_listing()
        self.assertEqual([int(i["address"], 16) for i in listing], want)
        for instruction in listing:
            address = int(instruction["address"], 16)
            self.assertEqual(instruction["bytes"], self.pe.read(address, len(instruction["bytes"]) // 2).hex())
            self.assertNotEqual(instruction["text"], "")

    def test_a_range_gives_the_same_instructions_as_the_function_form_over_the_same_addresses(self):
        listing = self.function_listing()
        first = int(listing[0]["address"], 16)
        last = listing[-1]
        stop = int(last["address"], 16) + len(last["bytes"]) // 2
        self.assertEqual(self.qp.ask("disassemble", start=hx(first), stop=hx(stop)).answer, listing)

    def test_a_call_names_the_function_it_calls_as_the_project_names_it(self):
        self.assertIn(CALLED, self.pe.function_starts())
        name = self.qp.ask("function_at", address=hx(CALLED)).answer["name"]
        listing = self.qp.ask("disassemble", start=hx(CALL_SITE), stop=hx(CALL_SITE + 5)).answer
        self.assertEqual(len(listing), 1)
        self.assertIn(name, listing[0]["text"])
        self.assertNotIn(hx(CALLED), listing[0]["text"])  # the name, never the bare address

    def test_a_range_with_stop_at_or_before_start_or_over_one_mebibyte_gets_an_error_reply(self):
        for name, start, stop in (
            ("stop equals start", FN_ENCRYPT, FN_ENCRYPT),
            ("stop before start", FN_ENCRYPT, FN_ENCRYPT - 1),
            ("over 1 MiB", FN_ENCRYPT, FN_ENCRYPT + MAX_RANGE + 1),
        ):
            with self.subTest(name):
                reply = self.qp.ask("disassemble", start=hx(start), stop=hx(stop))
                self.assertIs(reply.body["ok"], False)
                self.assertIsInstance(reply.body["error"], str)
        self.assertEqual(self.function_listing()[0]["address"], hx(FN_ENCRYPT))  # still answering


if __name__ == "__main__":
    unittest.main(verbosity=2)
