//// The random values a rule draws, all from one seed. A rule takes no random
//// value from anywhere else, so a recording that holds the seed replays every
//// value. The seed comes from the operating system's strong random source
//// when a connection is accepted (`step.Accepted`); each block is
//// HMAC-SHA256(seed, counter), the counter rising by one per block, so no
//// two draws repeat and none tells anything of the seed.

import gleam/bit_array
import gleam/bool
import gleam/crypto

/// A source of random bytes: the seed and the next block's counter.
pub opaque type Random {
  Random(seed: BitArray, counter: Int)
}

/// A source whose first block is the seed's block 0.
pub fn new(seed seed: BitArray) -> Random {
  Random(seed:, counter: 0)
}

/// The next `count` bytes and the source after them. A draw takes whole
/// blocks of 32 bytes and drops what it does not use, so the bytes of two
/// draws never overlap.
pub fn bytes(random random: Random, count count: Int) -> #(Random, BitArray) {
  use <- bool.guard(when: count <= 0, return: #(random, <<>>))
  let blocks = { count + block_size - 1 } / block_size
  let drawn = draw(random:, remaining: blocks, built: <<>>)
  let assert Ok(wanted) = bit_array.slice(drawn, 0, count)
    as "the blocks drawn hold at least `count` bytes"
  #(Random(..random, counter: random.counter + blocks), wanted)
}

/// HMAC-SHA256's output is 32 bytes.
const block_size = 32

fn draw(
  random random: Random,
  remaining remaining: Int,
  built built: BitArray,
) -> BitArray {
  case remaining {
    0 -> built
    _ ->
      draw(
        random: Random(..random, counter: random.counter + 1),
        remaining: remaining - 1,
        built: <<
          built:bits,
          {
            crypto.hmac(
              <<random.counter:size(64)-big>>,
              crypto.Sha256,
              random.seed,
            )
          }:bits,
        >>,
      )
  }
}
