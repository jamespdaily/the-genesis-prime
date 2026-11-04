//// A half-precision float as the 16 bits the client packs the vectors of
//// movement commands 8 and 11 in (PackHalfVector 0x1401c9800, IEEE 754
//// binary16). Expected values come from these places.
//// - The client's own packing, run by the emulator: 1.0 gives 0x3c00, -2.0
////   gives 0xc000, 0.5 gives 0x3800, 0.1 gives 0x2e66, 0.0 gives 0, and 65536.0,
////   above the largest half, gives infinity as 0x7c00 (fact 0x1401c9800).
//// - The binary16 definition: a sign bit, 5 bits of exponent with a bias of 15,
////   10 bits of fraction; an exponent of 0 is zero or a subnormal worth
////   fraction x 2^-24, an exponent of 31 is infinity with a fraction of 0 and
////   not a number otherwise.

import genesis_prime/message/half_float.{Finite, Infinite, NotANumber}
import gleam/float
import gleam/int
import owned_test

pub fn the_values_the_clients_packing_gives_read_back_as_the_floats_it_packed_test() -> Nil {
  use <- owned_test.run(5000)
  assert half_float.from_bits(0x3C00) == Ok(Finite(1.0))
    as "0x1401c9800: 1.0 packs to 0x3c00"
  assert half_float.from_bits(0xC000) == Ok(Finite(-2.0))
    as "0x1401c9800: -2.0 packs to 0xc000"
  assert half_float.from_bits(0x3800) == Ok(Finite(0.5))
    as "0x1401c9800: 0.5 packs to 0x3800"
  assert half_float.from_bits(0x0000) == Ok(Finite(0.0))
    as "0x1401c9800: 0.0 packs to 0"
  assert half_float.from_bits(0x2E66) == Ok(Finite(0.0999755859375))
    as "0x1401c9800: 0.1 packs to 0x2e66, whose binary16 value is 2^-4 x (1 + 614/1024)"
}

pub fn an_exponent_of_all_ones_is_infinity_or_not_a_number_test() -> Nil {
  use <- owned_test.run(5000)
  assert half_float.from_bits(0x7C00) == Ok(Infinite(negative: False))
    as "0x1401c9800: 65536.0, above the largest half, packs to infinity, 0x7c00"
  assert half_float.from_bits(0xFC00) == Ok(Infinite(negative: True))
    as "binary16: the sign bit makes it minus infinity"
  assert half_float.from_bits(0x7E00) == Ok(NotANumber)
    as "binary16: an exponent of 31 with a fraction that is not 0"
  assert half_float.from_bits(0x7C01) == Ok(NotANumber)
    as "binary16: any non-zero fraction"
}

pub fn the_largest_the_smallest_normal_and_the_smallest_subnormal_are_the_binary16_limits_test() -> Nil {
  use <- owned_test.run(5000)
  assert half_float.from_bits(0x7BFF) == Ok(Finite(65_504.0))
    as "binary16: the largest finite value is (2 - 2^-10) x 2^15"
  assert half_float.from_bits(0x0400) == Ok(Finite(6.103515625e-5))
    as "binary16: the smallest normal value is 2^-14"
  assert half_float.from_bits(0x0001) == Ok(Finite(5.960464477539063e-8))
    as "binary16: the smallest subnormal is 2^-24"
  assert half_float.from_bits(0x03FF) == Ok(Finite(6.097555160522461e-5))
    as "binary16: the largest subnormal is 1023 x 2^-24"
}

pub fn every_pattern_of_16_bits_is_finite_unless_its_exponent_is_all_ones_test() -> Nil {
  use <- owned_test.run(30_000)
  int.range(from: 0, to: 0x10000, with: Nil, run: fn(_, bits) {
    let all_ones = int.bitwise_and(bits, 0x7C00) == 0x7C00
    let assert Ok(value) = half_float.from_bits(bits)
      as "a pattern of 16 bits is a half float"
    case value {
      Finite(_) -> {
        assert !all_ones
          as "binary16: only an exponent of 31 is not a finite value"
      }
      Infinite(negative:) -> {
        assert all_ones && int.bitwise_and(bits, 0x3FF) == 0
          as "binary16: infinity is an exponent of 31 and a fraction of 0"
        assert negative == { int.bitwise_and(bits, 0x8000) != 0 }
          as "binary16: the sign bit is the sign"
      }
      NotANumber -> {
        assert all_ones && int.bitwise_and(bits, 0x3FF) != 0
          as "binary16: not a number is an exponent of 31 and a fraction other than 0"
      }
    }
  })
}

pub fn the_finite_values_rise_with_their_bits_and_the_sign_bit_negates_them_test() -> Nil {
  use <- owned_test.run(30_000)
  let assert Ok(Finite(zero)) = half_float.from_bits(0)
    as "the pattern 0 is a finite value"
  assert zero == 0.0 as "binary16: the pattern 0 is zero"
  int.range(from: 1, to: 0x7C00, with: Nil, run: fn(_, bits) {
    let assert Ok(Finite(below)) = half_float.from_bits(bits - 1)
      as "a pattern below the infinities is finite"
    let assert Ok(Finite(value)) = half_float.from_bits(bits)
      as "a pattern below the infinities is finite"
    assert value >. below
      as "binary16: of two finite patterns with the sign clear, the larger bits are the larger value"
    let assert Ok(Finite(negative)) = half_float.from_bits(bits + 0x8000)
      as "the same pattern with the sign set is finite"
    assert negative == float.negate(value)
      as "binary16: the sign bit negates the value"
  })
}

pub fn a_number_outside_16_bits_is_no_half_float_test() -> Nil {
  use <- owned_test.run(5000)
  assert half_float.from_bits(-1) == Error(Nil)
    as "binary16 is 16 bits: a negative number has none, and -1 must not read as the bits 0xFFFF, not a number"
  assert half_float.from_bits(0x10000) == Error(Nil)
    as "binary16 is 16 bits: 0x10000 is the 17th bit alone, not the pattern 0"
  assert half_float.from_bits(0x17C00) == Error(Nil)
    as "binary16 is 16 bits: 0x17C00 must not read as 0x7C00, infinity"
  assert half_float.from_bits(0xFFFF) == Ok(NotANumber)
    as "binary16: 0xFFFF is the last 16-bit pattern, an exponent of 31 with a fraction other than 0"
}

pub fn to_bits_packs_as_the_clients_packing_does_test() -> Nil {
  use <- owned_test.run(5000)
  assert half_float.to_bits(value: 1.0) == Ok(0x3C00)
    as "0x1401c9800: 1.0 packs to 0x3c00"
  assert half_float.to_bits(value: -2.0) == Ok(0xC000)
    as "0x1401c9800: -2.0 packs to 0xc000"
  assert half_float.to_bits(value: 0.5) == Ok(0x3800)
    as "0x1401c9800: 0.5 packs to 0x3800"
  assert half_float.to_bits(value: 0.1) == Ok(0x2E66)
    as "0x1401c9800: 0.1, between two halves, packs to the nearer, 0x2e66"
  assert half_float.to_bits(value: 10.0) == Ok(0x4900)
    as "binary16: 10.0 is 2^3 x (1 + 256/1024), exponent 18, fraction 256"
}

pub fn to_bits_takes_the_largest_half_and_refuses_beyond_it_test() -> Nil {
  use <- owned_test.run(5000)
  assert half_float.to_bits(value: 65_504.0) == Ok(0x7BFF)
    as "binary16: the largest finite value, (2 - 2^-10) x 2^15"
  assert half_float.to_bits(value: -65_504.0) == Ok(0xFBFF)
    as "binary16: its negative, with the sign bit"
  assert half_float.to_bits(value: 65_504.5) == Error(Nil)
    as "beyond the largest half: the client would pack infinity (0x1401c9800), which no path speed is, so it has no bits"
}
