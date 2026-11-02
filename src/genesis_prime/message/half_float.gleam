//// A half-precision float (IEEE 754 binary16) as the 16 bits the client packs
//// the vectors of movement commands 8 and 11 in (PackHalfVector 0x1401c9800).
//// The generated message modules keep each one as its bits, so every bit
//// pattern round-trips, and a rule that needs the number reads it with
//// `from_bits`.

import gleam/bool
import gleam/float
import gleam/int

/// What 16 bits of a half float hold. A Gleam float cannot hold an infinity or
/// a number that is not one, so those have cases of their own.
pub type HalfFloat {
  /// Zero, a subnormal or a normal value.
  Finite(Float)
  /// An exponent of all ones and a fraction of 0, with the sign of the bits:
  /// the client packs a value above the largest half, 65504, as infinity
  /// (0x1401c9800).
  Infinite(negative: Bool)
  /// An exponent of all ones and a fraction other than 0.
  NotANumber
}

/// The value of 16 bits: a sign bit, 5 bits of exponent with a bias of 15 and 10
/// bits of fraction. An exponent of 0 is zero or a subnormal worth the fraction
/// times 2^-24; an exponent of 31 is infinity or not a number; any other is
/// (1 + fraction / 1024) times 2^(exponent - 15).
pub fn from_bits(bits bits: Int) -> HalfFloat {
  let negative = int.bitwise_and(bits, 0x8000) != 0
  let exponent = int.bitwise_and(int.bitwise_shift_right(bits, 10), 0x1F)
  let fraction = int.bitwise_and(bits, 0x3FF)
  case exponent, fraction {
    31, 0 -> Infinite(negative:)
    31, _ -> NotANumber
    0, _ -> Finite(signed(scaled(fraction, -24), negative:))
    _, _ -> Finite(signed(scaled(1024 + fraction, exponent - 25), negative:))
  }
}

/// `mantissa` times 2 to the `power`, exact for the mantissas and powers of a
/// half float.
fn scaled(mantissa: Int, power: Int) -> Float {
  case power >= 0 {
    True -> int.to_float(int.bitwise_shift_left(mantissa, power))
    False ->
      int.to_float(mantissa) /. int.to_float(int.bitwise_shift_left(1, -power))
  }
}

fn signed(value: Float, negative negative: Bool) -> Float {
  use <- bool.guard(when: negative, return: float.negate(value))
  value
}
