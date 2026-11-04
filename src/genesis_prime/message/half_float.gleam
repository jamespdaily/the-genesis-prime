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

/// The number the client's converter makes of 16 bits (0x1401c9770): any
/// exponent but 0 is read as a finite number, exponent 31 included, so 0x7C00
/// is 65536.0 and 0x7FFF is 131008.0, and the sign bit makes it negative. It
/// differs from `from_bits` for exponent 31, which that function reads as
/// infinity or not a number, and a rule that must refuse what the client's
/// compare refuses uses this one. Bits outside 16 have no value.
pub fn client_value(bits bits: Int) -> Result(Float, Nil) {
  use <- bool.guard(when: bits < 0 || bits > 0xFFFF, return: Error(Nil))
  let exponent = int.bitwise_and(int.bitwise_shift_right(bits, 10), 0x1F)
  let fraction = int.bitwise_and(bits, 0x3FF)
  let magnitude = case exponent {
    0 -> int.to_float(fraction) *. power_of_two(-24)
    _ -> int.to_float(1024 + fraction) *. power_of_two(exponent - 25)
  }
  Ok(case int.bitwise_and(bits, 0x8000) {
    0 -> magnitude
    _ -> float.negate(magnitude)
  })
}

fn power_of_two(exponent: Int) -> Float {
  let assert Ok(value) = float.power(2.0, int.to_float(exponent))
    as "2 to an integer power is a number"
  value
}

/// The 16 bits of a number as the runtime's 16-bit float segment writes it,
/// rounded to the nearest half float: the speed of a path the server writes
/// (`movement_command.kind_4`). A number beyond the half float's range has no
/// bits.
pub fn to_bits(value value: Float) -> Result(Int, Nil) {
  case float.absolute_value(value) <=. 65_504.0 {
    True -> {
      let assert <<bits:size(16)>> = <<value:float-size(16)>>
        as "a number within 65504 fits a half float"
      Ok(bits)
    }
    False -> Error(Nil)
  }
}
