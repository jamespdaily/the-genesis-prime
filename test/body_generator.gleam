//// Random message bodies for property tests of the frame and the ciphers.

import gleam/bit_array
import gleam/int
import gleam/list
import qcheck.{type Generator}

/// A body of 0 to `most` bytes, every byte of any value. Most are short; some
/// are as long as `most` allows, made of one random chunk repeated, so a
/// frame or cipher near its size limit is drawn without a tree of shrinks for
/// each of its bytes.
pub fn body(most most: Int) -> Generator(BitArray) {
  qcheck.from_weighted_generators(#(9, short(most)), [#(1, long(most))])
}

fn short(most: Int) -> Generator(BitArray) {
  qcheck.generic_byte_aligned_bit_array(
    values_from: qcheck.bounded_int(from: 0, to: 255),
    byte_size_from: qcheck.bounded_int(from: 0, to: int.min(most, 300)),
  )
}

fn long(most: Int) -> Generator(BitArray) {
  use length <- qcheck.bind(
    qcheck.from_weighted_generators(
      #(3, qcheck.bounded_int(from: 0, to: most)),
      [#(1, qcheck.constant(most))],
    ),
  )
  use chunk <- qcheck.map(qcheck.generic_byte_aligned_bit_array(
    values_from: qcheck.bounded_int(from: 0, to: 255),
    byte_size_from: qcheck.bounded_int(from: 1, to: 64),
  ))
  let repeated =
    bit_array.concat(list.repeat(chunk, length / bit_array.byte_size(chunk) + 1))
  let assert Ok(body) = bit_array.slice(repeated, 0, length)
    as "the repeated chunk is at least as long as the body"
  body
}
