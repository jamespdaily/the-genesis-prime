//// A float as the 32 bits the client's messages carry (ReadFloat 0x14006C1C0).
//// The generated message modules keep a float as its bits, so every bit
//// pattern round-trips; this module turns a server's float into those bits.

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
