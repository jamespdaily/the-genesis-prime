//// A seeded random source for the dev start and the tests: splitmix64, a fixed
//// sequence for a fixed seed, so a recorded session can be played again and a
//// failing case can be replayed. It lives in `dev/` and is used from `dev/` and
//// `test/` only; the code rules refuse it in `src/`, so the server that is
//// released draws from the operating system.
////
//// The generator is a plain function of an `Int` state that each draw returns
//// advanced. The server draws from many processes (each STS connection and the
//// two hand-offs), so the state has one owner, the source process: a draw is a
//// message to it, and its answers come in the order the draws arrived.
////
//// The source process is a child of its starter's supervisor. A restart builds
//// it again from its seed, so its sequence starts over; it holds nothing else.

import genesis_prime/login/random_source.{type RandomSource}
import gleam/erlang/process.{type Name, type Subject}
import gleam/int
import gleam/otp/supervision

const mask = 0xFFFF_FFFF_FFFF_FFFF

/// The largest seed: one that fits the 64 bits of the generator's state and of
/// a recording's header.
pub const largest_seed = 0xFFFF_FFFF_FFFF_FFFF

/// The messages the source process receives.
pub type Message {
  Draw(count: Int, reply: Subject(BitArray))
}

/// The source process as a child of a supervisor, registered under `name`,
/// drawing the sequence of `seed`.
pub fn supervised(
  name _name: Name(Message),
  seed _seed: Int,
) -> supervision.ChildSpecification(Subject(Message)) {
  panic as "shape only: not built"
}

/// The source of the process registered under `name`, for the settings of the
/// login: each draw asks the process, so every draw of the server comes from
/// the one sequence.
pub fn source(name _name: Name(Message)) -> RandomSource {
  panic as "shape only: not built"
}

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
