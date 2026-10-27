//// The random values a rule draws, all from one connection's seed
//// (`genesis_prime/random`). Expected values come from the module's own
//// definition: block n is HMAC-SHA256(key: seed, data: n as a 64-bit
//// big-endian counter), each draw takes whole 32-byte blocks and drops the
//// bytes it does not use (RFC 2104 for HMAC; `gleam/crypto` computes it in
//// `login_rule_support.block`).

import genesis_prime/random
import gleam/bit_array
import login_rule_support as support
import owned_test

/// The first `count` bytes of a block of the seed's random stream.
fn start_of_block(
  seed seed: BitArray,
  counter counter: Int,
  count count: Int,
) -> BitArray {
  let assert Ok(start) =
    bit_array.slice(support.block(seed:, counter:), 0, count)
    as "a block is 32 bytes"
  start
}

pub fn the_first_draw_is_block_0_of_the_seed_test() -> Nil {
  use <- owned_test.run(5000)
  let seed = support.seed(first: 1)
  let #(_, drawn) = random.bytes(random: random.new(seed:), count: 32)
  assert drawn == support.block(seed:, counter: 0)
    as "block 0 = HMAC-SHA256(key: seed, data: 0 as 64 bits big-endian)"
}

pub fn a_draw_takes_whole_blocks_and_the_next_draw_starts_at_the_next_block_test() -> Nil {
  use <- owned_test.run(5000)
  let seed = support.seed(first: 1)
  let #(source, sixteen) = random.bytes(random: random.new(seed:), count: 16)
  let #(source, forty) = random.bytes(random: source, count: 40)
  let #(_, one) = random.bytes(random: source, count: 1)
  assert sixteen == start_of_block(seed:, counter: 0, count: 16)
    as "16 bytes are the first 16 of block 0; the other 16 are dropped"
  assert forty
    == bit_array.concat([
      support.block(seed:, counter: 1),
      start_of_block(seed:, counter: 2, count: 8),
    ])
    as "40 bytes are block 1 and the first 8 of block 2"
  assert one == start_of_block(seed:, counter: 3, count: 1)
    as "40 bytes take blocks 1 and 2, so the next draw starts at block 3"
}

pub fn the_same_seed_gives_the_same_values_and_two_seeds_give_different_ones_test() -> Nil {
  use <- owned_test.run(5000)
  let draw = fn(seed) { random.bytes(random: random.new(seed:), count: 32).1 }
  assert draw(support.seed(first: 1)) == draw(support.seed(first: 1))
    as "a recording that holds the seed replays every value"
  assert draw(support.seed(first: 1)) != draw(support.seed(first: 9))
    as "a different seed gives different bytes"
}
