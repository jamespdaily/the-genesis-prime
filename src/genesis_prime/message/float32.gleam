//// A float as the 32 bits the client's messages carry (ReadFloat 0x14006c1c0).
//// The generated message modules keep a float as its bits, so every bit
//// pattern round-trips; this module turns a server's float into those bits.

/// The bits of the 32-bit float nearest to `value`, rounded to nearest even as
/// a conversion to single precision is. A value beyond the largest finite
/// 32-bit float is the largest finite 32-bit float with the value's sign, so
/// the client never reads an infinity.
pub fn to_bits(value value: Float) -> Int {
  todo as "the bits of the nearest 32-bit float"
}
