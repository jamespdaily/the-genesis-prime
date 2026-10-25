"""formulas_by_hand: the two client functions copied by hand from llvm-objdump.

They are the emulator tests' expected values, so they are checked here against
what the functions are known to compute, and the planted variants are checked
to differ. Evidence: llvm-objdump of WildStar64.exe at 0x140882470 and
0x1408296a0 (comments in formulas_by_hand.py give each address).
Run: python3 -I test_formulas_by_hand.py
"""

import os
import random
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_support as cs  # noqa: E402
from formulas_by_hand import (  # noqa: E402
    C_PI_OVER_180,
    f32,
    f32_bits,
    formula_a,
    formula_b,
)


class FormulaATest(unittest.TestCase):
    def test_formula_a_is_the_index_of_the_highest_set_bit(self):
        # 0x140882470 computes 63 - clz(x): bit_length() - 1 (llvm-objdump; fact file record 0x140882470)
        rng = random.Random(24)
        checked = 0
        while checked < 100_000:
            x = rng.getrandbits(rng.randint(1, 64))
            if x == 0:
                continue
            self.assertEqual(formula_a(x), x.bit_length() - 1, hex(x))
            checked += 1

    def test_formula_a_of_zero_is_0xffffffff(self):
        # the disassembly sets eax = 0x1f for a zero low word, then decrements: 0 - 1 as 32 bits
        self.assertEqual(formula_a(0), 0xFFFFFFFF)

    def test_formula_a_at_the_edges(self):
        self.assertEqual(formula_a(1), 0)
        self.assertEqual(formula_a(2**32 - 1), 31)
        self.assertEqual(formula_a(2**32), 32)
        self.assertEqual(formula_a(2**63), 63)
        self.assertEqual(formula_a(2**64 - 1), 63)

    def test_the_planted_formula_a_differs_from_the_real_one(self):
        # planted: 0x1F replaced by 0x1E; the harness must be able to see it
        planted = cs.planted_formula_a()
        rng = random.Random(24)
        inputs = [rng.getrandbits(rng.randint(1, 64)) for _ in range(1000)] + [0, 1, 2**32 - 1, 2**32, 2**63, 2**64 - 1]
        self.assertTrue(any(planted(x) != formula_a(x) for x in inputs))


class FormulaBTest(unittest.TestCase):
    def test_formula_b_turns_degrees_into_radians_below_one_turn(self):
        # 0x1408296a0: (x - trunc(x / 360)) * pi / 180 in float32; trunc(90/360) = 0
        self.assertEqual(formula_b(90.0), f32(90.0 * C_PI_OVER_180))

    def test_formula_b_subtracts_the_whole_turns_not_360_times_them(self):
        # disassembly: subss xmm0, xmm2 with xmm2 = float(trunc(x * 1/360)); for 400: 400 - 1 = 399
        self.assertEqual(formula_b(400.0), f32(f32(400.0 - 1.0) * C_PI_OVER_180))
        self.assertNotEqual(formula_b(400.0), formula_b(40.0))

    def test_formula_b_of_negative_zero_keeps_the_sign_bit(self):
        self.assertEqual(f32_bits(formula_b(-0.0)), 0x80000000)

    def test_the_constant_is_pi_over_180_in_float32(self):
        # .rdata 0x140b79d50 holds bytes 35fa8e3c
        self.assertAlmostEqual(C_PI_OVER_180, 3.141592653589793 / 180, delta=1e-9)

    def test_the_planted_formula_b_differs_from_the_real_one(self):
        # planted: C_PI_OVER_180 moved by one float32 ulp
        planted = cs.planted_formula_b()
        rng = random.Random(24)
        inputs = [f32(rng.uniform(-1e6, 1e6)) for _ in range(1000)]
        self.assertTrue(any(f32_bits(planted(x)) != f32_bits(formula_b(x)) for x in inputs))


if __name__ == "__main__":
    unittest.main(verbosity=2)
