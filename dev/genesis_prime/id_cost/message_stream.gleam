//// The simulated client messages every variant of the id-cost benchmark reads,
//// and the unit numbers they carry.

import gleam/int
import gleam/list

/// How many units the benchmark keeps in its dictionary.
pub const unit_count = 10_000

/// How many other ids a reply lists besides the unit's own.
pub const nearby_count = 49

/// The indexes from 0 up to, not including, `count`.
pub fn indexes(count: Int) -> List(Int) {
  int.range(0, count, [], fn(indexes, index) { [index, ..indexes] })
  |> list.reverse
}

/// The number of the unit at an index, spread over 32 bits so the numbers
/// look like a server's and not like a counting sequence.
pub fn unit_number(index: Int) -> Int {
  { 1 + index * 2_654_435 } % 4_294_967_296
}

/// A stream of `count` messages, each 10 bytes: a unit number (32 bits), a
/// signed move on each axis (16 bits each) and an amount (16 bits), all
/// little-endian. The same stream is read by every variant, so only the id type
/// differs between runs.
pub fn build(count: Int) -> BitArray {
  build_from(remaining: count, seed: 12_345, stream: <<>>)
}

fn build_from(
  remaining remaining: Int,
  seed seed: Int,
  stream stream: BitArray,
) -> BitArray {
  case remaining {
    0 -> stream
    _ -> {
      let seed = { seed * 1_103_515_245 + 12_345 } % 2_147_483_648
      let unit = unit_number({ seed / 65_536 } % unit_count)
      let move_x = int.bitwise_and(seed / 7, 0xFF) - 128
      let move_y = int.bitwise_and(seed / 31, 0xFF) - 128
      let amount = int.bitwise_and(seed / 13, 0x3FF)
      build_from(remaining: remaining - 1, seed:, stream: <<
        stream:bits,
        unit:32-little,
        move_x:16-little,
        move_y:16-little,
        amount:16-little,
      >>)
    }
  }
}
