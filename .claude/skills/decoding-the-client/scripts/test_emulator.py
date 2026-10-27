"""Client code run on Ghidra's emulator, through the query process's `emulate` kind.

Integration tests: they run only when GENESIS_INTEGRATION=1 (see
test_query_process.py for the environment). They open the project built by
check_support.seeded_project().

The request and reply, as ghidra_query.py documents them:
  {"kind": "emulate", "function": "0x140882470", "args": [x, ...]}
  -> {"result": {"rax": <unsigned int>, "xmm0_low": <unsigned int>}, "steps": n}
Each argument is a JSON integer (an integer register) or a JSON float (an XMM
register, passed as float32). `rax` and `xmm0_low` are client_emulator.Run's
fields: RAX, and the low 64 bits of XMM0 (a float32 result is its low 32).

EmulateRangesTest uses the fuller form, as ghidra_query.py documents it:
  {"kind": "emulate", "function": "0x..." | "start": "0x...", "stop": "0x...",
   "args": [...], "registers": {"rbx": int, ...}, "memory": [{"address": "0x...", "bytes": "<hex>"}],
   "read": [{"address": "0x...", "length": n}], "stand_ins": {"0x...": {"kind": "heap_alloc"}},
   "follow_calls": bool, "max_steps": n}
  -> {"result": {...}, "registers": {"rax": int, ...}, "read": ["<hex>", ...], "steps": n, "stopped_at": "0x..."}
Every request starts from a clean machine.

Expected values are formulas_by_hand.py, copied by hand from llvm-objdump's
disassembly of WildStar64.exe (SHA-256 565c2fa1...fe0b10) at 0x140882470
(formula A) and 0x1408296a0 (formula B); the two readings are independent.
EmulateRangesTest's come from the fact file's records and vectors, named at each
test, and from llvm-objdump and the PE import table.
Run: GENESIS_INTEGRATION=1 python3 -I test_emulator.py
"""

import os
import random
import statistics
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_support as cs  # noqa: E402
from check_support import hx  # noqa: E402
from formulas_by_hand import M32, f32, f32_bits, formula_a, formula_b  # noqa: E402

FORMULA_A = 0x140882470
FORMULA_B = 0x1408296A0

# The addresses of the fuller form's tests. PLANTED_ addresses are not the client's.
PLANTED_GAME_OBJECT = 0x2000_0000_0000
PLANTED_OUT_CELL = 0x2100_0000_0000
PLANTED_CIPHER_OBJECT = 0x2200_0000_0000
PLANTED_BUFFER = 0x2300_0000_0000
HEAP_BASE = 0x6000_0000_0000  # the first block heap_alloc returns, as ghidra_query.py documents

BASE_KEY_SEED = 0x718DA9074F2DEB91  # constructor 0x14000a490 leaves it in rdi (fact file record 0x14000a6db)
BASE_KEY = 0xD283F5B34A8DC685  # fact file record 0x14000a6db
# vector.0x1400c2eb0.base_key: the sixteen words under the base key, and the chaining start h
BASE_KEY_WORDS = [
    0x5E5632D58E9AC486, 0x3E99523E2158E443, 0x8CA81D11B739AE08, 0x696C006343452715,
    0xBB4864FAC37046AA, 0x87D80E73E857C607, 0xC84B2B519EF3706C, 0xBB8D2B5A1E55F319,
    0x96F2844490AD2D4E, 0x7068E86380D7004B, 0xE1EF14E2ECFE9F50, 0xF13A1A4082D65F9D,
    0x75A929E1A3220872, 0x3E071ED02065A30F, 0x836922F247ACCAB4, 0x6A6F8BE7EA7E7CA1,
]
BASE_KEY_H = 0x7D546D1D1994C849
# vector.0x1400c2d10.base_key: EncryptMessageBody on the bytes 00 01 02 .. of length n
ENCRYPTED = {
    1: "19",
    7: "25b96584484319",
    8: "cf0d0c94cc5a0424",
    9: "195668f6fb7cbd9b8c",
    15: "25b96584484319b234433a911e659a",
    16: "cf0d0c94cc5a042484e05ebefe059315",
    17: "195668f6fb7cbd9b8c00b47fb76b8965ee",
    100: "07e43b8a5deca0ec44ede6013209c69304630afec4083f658125c667980f1b8bd30cc6e75d0394d9f48689eca130bdc8707d17986727e27ce9385349bc91b3292fbd8b842de6a330241099ee5ff974417ceff20a1ab18a9a3191ed1225ecb8acfbb6ffb2",
}

A_EDGES = [0, 1, 2**32 - 1, 2**32, 2**63, 2**64 - 1]
B_EDGES = [0.0, -0.0, 360.0, -360.0, 720.0]
# 1e12 / 360 is past cvttss2si's int32 range. The CPU gives the integer
# indefinite value 0x80000000; Ghidra 12.2's p-code wraps the truncation to 32
# bits instead (a known gap of the emulator).
B_OVERFLOW = f32(1e12)
B_OVERFLOW_GHIDRA_BITS = 0x50823C05  # the hand formula fed the wrapped value -1,517,189,376
B_OVERFLOW_CPU_BITS = 0x50825100  # formula_b(1e12): the CPU's rule


def formula_a_inputs() -> list[int]:
    # 1,000 from random.Random(24), each of a random width 1..64 bits so every
    # branch of the function is reached, then the edges
    rng = random.Random(24)
    return [rng.getrandbits(rng.randint(1, 64)) for _ in range(1000)] + A_EDGES


def formula_b_inputs() -> list[float]:
    # 1,000 float32 values uniform in [-1e6, 1e6] from random.Random(24), then the edges
    rng = random.Random(24)
    return [f32(rng.uniform(-1e6, 1e6)) for _ in range(1000)] + B_EDGES


@cs.integration_only
class EmulatorTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.qp = cs.QueryProcess(cs.seeded_project().project_dir)
        cls.qp.ask("seed_report")  # the project is open
        cls.a_inputs = formula_a_inputs()
        cls.b_inputs = formula_b_inputs()
        cls.a_runs = [cls.emulate_once(FORMULA_A, x) for x in cls.a_inputs]
        cls.b_runs = [cls.emulate_once(FORMULA_B, x) for x in cls.b_inputs]

    @classmethod
    def tearDownClass(cls):
        cls.qp.close()

    @classmethod
    def emulate_once(cls, function: int, argument):
        reply = cls.qp.ask("emulate", function=hx(function), args=[argument])
        return reply.answer["result"], reply.answer["steps"], reply.ms

    def test_formula_a_returns_the_index_of_the_highest_set_bit_as_the_hand_transcription_does(self):
        for x, (result, steps, _ms) in zip(self.a_inputs, self.a_runs):
            with self.subTest(x=hex(x)):
                self.assertEqual(result["rax"] & M32, formula_a(x))
                self.assertEqual(result["rax"] >> 32, 0)  # a write to EAX clears the upper half of RAX
                self.assertGreater(steps, 0)

    def test_a_formula_a_transcription_with_one_constant_changed_is_caught(self):
        # planted: every 0x1F replaced by 0x1E
        planted = cs.planted_formula_a()
        caught = [x for x, (result, _s, _m) in zip(self.a_inputs, self.a_runs) if result["rax"] & M32 != planted(x)]
        self.assertGreaterEqual(len(caught), 1)

    def test_formula_b_reads_the_clients_constants_and_returns_the_float_the_hand_transcription_does(self):
        for x, (result, steps, _ms) in zip(self.b_inputs, self.b_runs):
            with self.subTest(x=repr(x)):
                self.assertEqual(result["xmm0_low"] & M32, f32_bits(formula_b(x)))
                self.assertGreater(steps, 0)

    def test_a_formula_b_transcription_with_its_constant_moved_one_ulp_is_caught(self):
        # planted: C_PI_OVER_180 (.rdata 0x140b79d50) plus one float32 ulp
        planted = cs.planted_formula_b()
        caught = [
            x for x, (result, _s, _m) in zip(self.b_inputs, self.b_runs) if result["xmm0_low"] & M32 != f32_bits(planted(x))
        ]
        self.assertGreaterEqual(len(caught), 1)

    def test_ghidras_emulator_wraps_an_out_of_range_cvttss2si_where_the_cpu_gives_0x80000000(self):
        # a known gap, kept as a test so a fix in Ghidra shows up here
        self.assertEqual(f32_bits(formula_b(B_OVERFLOW)), B_OVERFLOW_CPU_BITS)
        result, _steps, _ms = self.emulate_once(FORMULA_B, B_OVERFLOW)
        self.assertEqual(result["xmm0_low"] & M32, B_OVERFLOW_GHIDRA_BITS)

    def test_the_time_per_emulated_call_is_recorded_for_both_formulas(self):
        a = statistics.median(ms for _r, _s, ms in self.a_runs)
        b = statistics.median(ms for _r, _s, ms in self.b_runs)
        print("median time per emulated call: formula A %.2f ms (%d calls), formula B %.2f ms (%d calls)"
              % (a, len(self.a_runs), b, len(self.b_runs)))
        self.assertGreater(a, 0)
        self.assertGreater(b, 0)


def u64(value: int) -> bytes:
    return value.to_bytes(8, "little")


def cipher_object() -> bytes:
    """The 0xb0-byte connection cipher object as InitConnectionCipher (0x1400c2bd0) leaves it under the base
    key, as far as the encrypt and decrypt routines read it: the key words at +0x28 and h at +0xa8."""
    return bytes(0x28) + b"".join(u64(w) for w in BASE_KEY_WORDS) + u64(BASE_KEY_H)


def counting_bytes(n: int) -> bytes:
    return bytes(i % 256 for i in range(n))


@cs.integration_only
class EmulateRangesTest(unittest.TestCase):
    """Items 7 to 12: the fuller form of `emulate`."""

    @classmethod
    def setUpClass(cls):
        cls.pe = cs.client_pe()
        cls.qp = cs.QueryProcess(cs.seeded_project().project_dir)
        cls.qp.ask("seed_report")

    @classmethod
    def tearDownClass(cls):
        cls.qp.close()

    def emulate(self, **fields):
        return self.qp.ask("emulate", timeout=300, **fields)

    def test_the_constructor_range_leaves_the_base_key_in_the_planted_game_object(self):
        # fact file record 0x14000a6db: the range is its ten instructions; rbx and rdi are as the constructor leaves them
        game_object = bytes(0x1630) + u64(BASE_KEY_SEED)
        answer = self.emulate(
            start="0x14000a6db",
            stop="0x14000a716",
            registers={"rbx": PLANTED_GAME_OBJECT, "rdi": BASE_KEY_SEED},
            memory=[{"address": hx(PLANTED_GAME_OBJECT), "bytes": game_object.hex()}],
            read=[{"address": hx(PLANTED_GAME_OBJECT + 0x1630), "length": 8}],
        ).answer
        self.assertEqual(answer["read"], [u64(BASE_KEY).hex()])
        self.assertEqual(answer["stopped_at"], "0x14000a716")
        self.assertEqual(answer["steps"], 10)

    def test_new_connection_cipher_with_the_heap_stand_in_and_followed_calls_builds_the_vectors_key_words(self):
        # fact file records 0x1400c2eb0 (rcx the cell the object's pointer goes to, r8 the key; the allocator
        # 0x14018b280 takes 0xb0 bytes) and vector.0x1400c2eb0.base_key; the object's words are at +0x28, h at +0xa8
        answer = self.emulate(
            function="0x1400c2eb0",
            registers={"rcx": PLANTED_OUT_CELL, "r8": BASE_KEY},
            memory=[{"address": hx(PLANTED_OUT_CELL), "bytes": bytes(8).hex()}],
            stand_ins={"0x14018b280": {"kind": "heap_alloc"}},
            follow_calls=True,
            read=[{"address": hx(PLANTED_OUT_CELL), "length": 8}, {"address": hx(HEAP_BASE), "length": 0xB0}],
        ).answer
        cell, built = answer["read"]
        self.assertEqual(cell, u64(HEAP_BASE).hex())  # the pointer the allocator returned is the one stored
        object_bytes = bytes.fromhex(built)
        words = [int.from_bytes(object_bytes[0x28 + 8 * i : 0x30 + 8 * i], "little") for i in range(16)]
        self.assertEqual(words, BASE_KEY_WORDS)
        self.assertEqual(int.from_bytes(object_bytes[0xA8:0xB0], "little"), BASE_KEY_H)

    def test_encrypt_message_body_in_place_on_a_planted_buffer_gives_the_vectors_bytes(self):
        # vector.0x1400c2d10.base_key; rcx the cipher object, rdx the body, r8 its length
        for n, want in sorted(ENCRYPTED.items()):
            with self.subTest(length=n):
                answer = self.emulate(
                    function="0x1400c2d10",
                    registers={"rcx": PLANTED_CIPHER_OBJECT, "rdx": PLANTED_BUFFER, "r8": n},
                    memory=[
                        {"address": hx(PLANTED_CIPHER_OBJECT), "bytes": cipher_object().hex()},
                        {"address": hx(PLANTED_BUFFER), "bytes": counting_bytes(n).hex()},
                    ],
                    read=[{"address": hx(PLANTED_BUFFER), "length": n}],
                ).answer
                self.assertEqual(answer["read"], [want])

    def test_a_128_kib_buffer_encrypted_then_decrypted_comes_back_unchanged(self):
        # the pair 0x1400c2d10 and 0x1400c2de0 is checked on a length of 17 by vector.0x1400c2de0.length_17;
        # each run starts clean, so the ciphertext of the first is planted for the second
        size = 128 * 1024
        plain = counting_bytes(size)

        def run(function: str, body: bytes) -> bytes:
            answer = self.emulate(
                function=function,
                registers={"rcx": PLANTED_CIPHER_OBJECT, "rdx": PLANTED_BUFFER, "r8": size},
                memory=[
                    {"address": hx(PLANTED_CIPHER_OBJECT), "bytes": cipher_object().hex()},
                    {"address": hx(PLANTED_BUFFER), "bytes": body.hex()},
                ],
                read=[{"address": hx(PLANTED_BUFFER), "length": size}],
                max_steps=5_000_000,
            ).answer
            return bytes.fromhex(answer["read"][0])

        encrypted = run("0x1400c2d10", plain)
        self.assertNotEqual(encrypted, plain)
        self.assertEqual(run("0x1400c2de0", encrypted), plain)

    def test_a_run_starts_from_a_clean_machine_with_nothing_from_the_run_before(self):
        constructor_range = {"start": "0x14000a6db", "stop": "0x14000a716"}
        first = self.emulate(
            **constructor_range,
            registers={"rbx": PLANTED_GAME_OBJECT, "rdi": BASE_KEY_SEED},
            memory=[{"address": hx(PLANTED_GAME_OBJECT + 0x1630), "bytes": u64(BASE_KEY_SEED).hex()}],
            read=[{"address": hx(PLANTED_GAME_OBJECT + 0x1630), "length": 8}],
        ).answer
        self.assertEqual(first["read"], [u64(BASE_KEY).hex()])  # the run wrote the planted address and set rbx
        # the same address read again, not planted: unmapped memory
        unplanted = self.emulate(**constructor_range, registers={"rbx": PLANTED_GAME_OBJECT})
        self.assertIs(unplanted.body["ok"], False)
        self.assertIn("unmapped", unplanted.body["error"])
        # one instruction (movabs rcx, 0x5b88d61139619662 at 0x14000a6e2) that touches neither rbx nor memory
        second = self.emulate(start="0x14000a6e2", stop="0x14000a6ec").answer
        self.assertEqual(second["registers"]["rbx"], 0)
        self.assertEqual(second["registers"]["rcx"], 0x5B88D61139619662)

    def test_a_call_to_an_import_with_no_stand_in_fails_naming_it_and_an_internal_call_fails_with_follow_calls_off(self):
        # llvm-objdump: `call qword ptr [rip + 0x94f891]` at 0x14000a061, six bytes, through the ShowCursor
        # slot (check_support.IAT_SHOWCURSOR, in the PE import table)
        name = self.pe.imports()[cs.IAT_SHOWCURSOR]
        for follow_calls in (False, True):
            with self.subTest(follow_calls=follow_calls):
                reply = self.emulate(start="0x14000a061", stop=hx(0x14000A061 + 6), follow_calls=follow_calls)
                self.assertIs(reply.body["ok"], False)
                self.assertIn(name, reply.body["error"])
        # fact file record 0x1400c2eb0: `call 0x14018b280` at 0x1400c2f19, five bytes
        reply = self.emulate(start="0x1400c2f19", stop=hx(0x1400C2F19 + 5))
        self.assertIs(reply.body["ok"], False)
        self.assertIn("calls out", reply.body["error"])
        self.assertIn("0x1400c2f19", reply.body["error"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
