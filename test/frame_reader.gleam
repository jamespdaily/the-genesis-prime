//// Reads the frames a server wrote, as a test client does: bytes arrive in
//// reads of any size, so a frame may span reads and one read may hold several
//// (ReadConnectionMessages 0x1403321a0, ReadMessageFrame 0x140331990).

import genesis_prime/connection/frame.{type Frame}
import gleam/list

/// Reads until `count` frames have arrived, whole and in order, however the
/// reads cut them. `have` is what was read before; `next` reads more, and its
/// error ends the wait.
pub fn read(
  have have: BitArray,
  count count: Int,
  next next: fn() -> Result(BitArray, Nil),
) -> Result(List(Frame), Nil) {
  read_until(have:, done: fn(found) { list.length(found) >= count }, next:)
}

/// Reads until `done` says the frames found so far, whole and in order, are
/// the ones wanted; `next` reads more, and its error ends the wait.
pub fn read_until(
  have have: BitArray,
  done done: fn(List(Frame)) -> Bool,
  next next: fn() -> Result(BitArray, Nil),
) -> Result(List(Frame), Nil) {
  collect(have:, found: [], done:, next:)
}

fn collect(
  have have: BitArray,
  found found: List(Frame),
  done done: fn(List(Frame)) -> Bool,
  next next: fn() -> Result(BitArray, Nil),
) -> Result(List(Frame), Nil) {
  let assert Ok(#(frames, leftover)) = frame.decode(have)
    as "the server wrote bytes that are frames"
  let found = list.append(found, frames)
  case done(found) {
    True -> Ok(found)
    False ->
      case next() {
        Ok(bytes) ->
          collect(have: <<leftover:bits, bytes:bits>>, found:, done:, next:)
        Error(Nil) -> Error(Nil)
      }
  }
}
