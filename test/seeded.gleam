//// A seeded random source for property tests: splitmix64, a fixed sequence for
//// a fixed seed, so a failing case can be replayed. The state is a plain `Int`
//// that each draw returns advanced.

import gleam/int

const mask = 0xFFFF_FFFF_FFFF_FFFF

/// The next 64-bit value and the advanced state.
pub fn next(state: Int) -> #(Int, Int) {
  let state = int.bitwise_and(state + 0x9E3779B97F4A7C15, mask)
  let mixed = mix(value: state, shift: 30, multiplier: 0xBF58476D1CE4E5B9)
  let mixed = mix(value: mixed, shift: 27, multiplier: 0x94D049BB133111EB)
  #(int.bitwise_exclusive_or(mixed, int.bitwise_shift_right(mixed, 31)), state)
}

fn mix(value value: Int, shift shift: Int, multiplier multiplier: Int) -> Int {
  int.bitwise_and(
    int.bitwise_exclusive_or(value, int.bitwise_shift_right(value, shift))
      * multiplier,
    mask,
  )
}

/// A value from 0 up to and including `most`, and the advanced state.
pub fn up_to(state state: Int, most most: Int) -> #(Int, Int) {
  let #(value, state) = next(state)
  #(value % { most + 1 }, state)
}

/// `count` random bytes and the advanced state.
pub fn bytes(state state: Int, count count: Int) -> #(BitArray, Int) {
  fill(state:, remaining: count, built: <<>>)
}

fn fill(
  state state: Int,
  remaining remaining: Int,
  built built: BitArray,
) -> #(BitArray, Int) {
  case remaining >= 8 {
    True -> {
      let #(word, state) = next(state)
      fill(state:, remaining: remaining - 8, built: <<
        built:bits,
        word:size(64),
      >>)
    }
    False -> {
      let #(word, state) = next(state)
      let bits = remaining * 8
      #(<<built:bits, word:size(bits)>>, state)
    }
  }
}
