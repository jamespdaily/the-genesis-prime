//// A float as the 32 bits the client's messages carry (ReadFloat 0x14006C1C0).
//// The generated message modules keep a float as its bits, so every bit
//// pattern round-trips; this module turns a server's float into those bits, and
//// the bits a client sent into the float they hold when it is finite.

import gleam/bool
import gleam/float

/// The largest finite 32-bit float, 3.4028234663852886e38 (0x7F7FFFFF), as a
/// float of the VM's own width.
const largest_single = 3.4028234663852886e38

/// The bits of the 32-bit float nearest to `value`, rounded to nearest even as
/// a conversion to single precision is. A value beyond the largest finite
/// 32-bit float is the largest finite 32-bit float with the value's sign, so
/// the client never reads an infinity.
pub fn to_bits(value value: Float) -> Int {
  let finite =
    float.clamp(value, min: float.negate(largest_single), max: largest_single)
  let assert <<bits:size(32)>> = <<finite:float-size(32)>>
    as "a float written in 32 bits is 32 bits"
  bits
}

/// The float the 32-bit float nearest to `value` holds, as the VM's own float:
/// what a value is after the client holds it in 32 bits. It rounds as
/// `to_bits` does, so it is always finite.
pub fn rounded(value value: Float) -> Float {
  let assert <<narrow:float-size(32)>> = <<to_bits(value:):size(32)>>
    as "the bits of a finite 32-bit float are a finite 32-bit float"
  narrow
}

/// The 32 bits a message carries a float in: 0 to 0xFFFFFFFF, so a value wider
/// than 32 bits is never held. Any pattern is held, a float that is infinite or
/// not a number among them, so a rule that takes a client's float can refuse it.
pub opaque type Bits {
  Bits(number: Int)
}

/// The 32 bits with this number, `Error(Nil)` for a number below 0 or above
/// 0xFFFFFFFF, which is not 32 bits.
pub fn bits(number number: Int) -> Result(Bits, Nil) {
  use <- bool.guard(when: number < 0 || number > 0xFFFFFFFF, return: Error(Nil))
  Ok(Bits(number:))
}

/// The float the 32 bits hold, `Error(Nil)` for infinity and for a number that
/// is not one, which the runtime's float cannot hold.
pub fn value(bits bits: Bits) -> Result(Float, Nil) {
  case <<bits.number:size(32)>> {
    <<finite:float-size(32)>> -> Ok(finite)
    _ -> Error(Nil)
  }
}
