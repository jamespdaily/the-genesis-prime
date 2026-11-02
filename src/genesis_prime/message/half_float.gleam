//// A half-precision float (IEEE 754 binary16) as the 16 bits the client packs
//// the vectors of movement commands 8 and 11 in (PackHalfVector 0x1401c9800).
//// The generated message modules keep each one as its bits, so every bit
//// pattern round-trips, and a rule that needs the number reads it with
//// `from_bits`.

import gleam/bool
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

/// The value of 16 bits: a sign bit, 5 bits of exponent and 10 bits of
/// fraction. A number below 0 or above 0xFFFF is not 16 bits, so it has no
/// value and is refused. An exponent of all ones is infinity or not a number,
/// which the runtime's 16-bit float segment cannot read, so they are told apart
/// here; any other pattern is read by that segment.
pub fn from_bits(bits bits: Int) -> Result(HalfFloat, Nil) {
  use <- bool.guard(when: bits < 0 || bits > 0xFFFF, return: Error(Nil))
  let exponent = int.bitwise_and(int.bitwise_shift_right(bits, 10), 0x1F)
  Ok(case exponent, int.bitwise_and(bits, 0x3FF) {
    31, 0 -> Infinite(negative: int.bitwise_and(bits, 0x8000) != 0)
    31, _ -> NotANumber
    _, _ -> {
      let assert <<value:float-size(16)>> = <<bits:size(16)>>
        as "a pattern whose exponent is not all ones is a finite half float"
      Finite(value)
    }
  })
}
