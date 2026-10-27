//// The random values a rule draws, all from one connection's seed
//// (`genesis_prime/random`). Expected values come from the module's own
//// definition: block n is HMAC-SHA256(key: seed, data: n as a 64-bit
//// big-endian counter), each draw takes whole 32-byte blocks and drops the
//// bytes it does not use (RFC 2104 for HMAC; `gleam/crypto` computes it here).

import genesis_prime/random
import gleam/bit_array
import gleam/crypto
import owned_test

fn block(seed seed: BitArray, counter counter: Int) -> BitArray {
  crypto.hmac(<<counter:size(64)-big>>, crypto.Sha256, seed)
}

fn seed_of(byte: Int) -> BitArray {
  <<
    byte,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22,
    23,
    24,
    25,
    26,
    27,
    28,
    29,
    30,
    31,
    32,
  >>
}

pub fn the_first_draw_is_block_0_of_the_seed_test() -> Nil {
  use <- owned_test.run(5000)
  let seed = seed_of(1)
  let #(_, drawn) = random.bytes(random: random.new(seed:), count: 32)
  assert drawn == block(seed:, counter: 0)
    as "block 0 = HMAC-SHA256(key: seed, data: 0 as 64 bits big-endian)"
}

pub fn a_draw_takes_whole_blocks_and_the_next_draw_starts_at_the_next_block_test() -> Nil {
  use <- owned_test.run(5000)
  let seed = seed_of(1)
  let #(source, sixteen) = random.bytes(random: random.new(seed:), count: 16)
  let #(source, forty) = random.bytes(random: source, count: 40)
  let #(_, one) = random.bytes(random: source, count: 1)
  let assert Ok(first_sixteen) =
    bit_array.slice(block(seed:, counter: 0), 0, 16)
    as "a block is 32 bytes"
  assert sixteen == first_sixteen
    as "16 bytes are the first 16 of block 0; the other 16 are dropped"
  assert forty
    == bit_array.concat([
      block(seed:, counter: 1),
      case bit_array.slice(block(seed:, counter: 2), 0, 8) {
        Ok(eight) -> eight
        Error(Nil) -> <<>>
      },
    ])
    as "40 bytes are block 1 and the first 8 of block 2"
  assert one
    == case bit_array.slice(block(seed:, counter: 4), 0, 1) {
      Ok(first) -> first
      Error(Nil) -> <<>>
    }
    as "the draw after 40 bytes (2 blocks) starts at block 4, none of block 3's dropped bytes reused"
}

pub fn the_same_seed_gives_the_same_values_and_two_seeds_give_different_ones_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, first) =
    random.bytes(random: random.new(seed: seed_of(1)), count: 32)
  let #(_, again) =
    random.bytes(random: random.new(seed: seed_of(1)), count: 32)
  let #(_, other) =
    random.bytes(random: random.new(seed: seed_of(9)), count: 32)
  assert first == again as "a recording that holds the seed replays every value"
  assert first != other as "a different seed gives different bytes"
}
