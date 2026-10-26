//// A seeded random source for property tests: a fixed sequence for a fixed
//// seed, so a failing case can be replayed. It is the generator of
//// `genesis_prime/seeded_random`, which the dev start uses too.

import genesis_prime/seeded_random

/// The next 64-bit value and the advanced state.
pub fn next(state: Int) -> #(Int, Int) {
  seeded_random.next(state)
}

/// A value from 0 up to and including `most`, and the advanced state.
pub fn up_to(state state: Int, most most: Int) -> #(Int, Int) {
  seeded_random.up_to(state:, most:)
}

/// `count` random bytes and the advanced state.
pub fn bytes(state state: Int, count count: Int) -> #(BitArray, Int) {
  seeded_random.bytes(state:, count:)
}
