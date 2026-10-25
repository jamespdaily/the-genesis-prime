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

Expected values are formulas_by_hand.py, copied by hand from llvm-objdump's
disassembly of WildStar64.exe (SHA-256 565c2fa1...fe0b10) at 0x140882470
(formula A) and 0x1408296a0 (formula B); the two readings are independent.
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
