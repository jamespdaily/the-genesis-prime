//// Reads the frames a server wrote, as a test client does: bytes arrive in
//// reads of any size, so a frame may span reads and one read may hold several
//// (ReadConnectionMessages 0x1403321a0, ReadMessageFrame 0x140331990).

import genesis_prime/connection/frame.{type Frame, type FrameError}
import gleam/list
import gleam/option.{None, Some}

/// Reads until `count` frames have arrived, whole and in order, however the
/// reads cut them. `have` is what was read before; `next` reads more, and its
/// error ends the wait and is the error given.
pub fn read(
  have have: BitArray,
  count count: Int,
  next next: fn() -> Result(BitArray, error),
) -> Result(List(Frame), error) {
  read_until(have:, done: fn(found) { list.length(found) >= count }, next:)
}

/// Reads until `done` says the frames found so far, whole and in order, are
/// the ones wanted; `next` reads more, and its error ends the wait and is the error given.
pub fn read_until(
  have have: BitArray,
  done done: fn(List(Frame)) -> Bool,
  next next: fn() -> Result(BitArray, error),
) -> Result(List(Frame), error) {
  collect(have:, found: [], done:, next:)
}

fn collect(
  have have: BitArray,
  found found: List(Frame),
  done done: fn(List(Frame)) -> Bool,
  next next: fn() -> Result(BitArray, error),
) -> Result(List(Frame), error) {
  let assert Ok(#(frames, leftover)) = decode(received: have)
    as "the server wrote bytes that are frames"
  let found = list.append(found, frames)
  case done(found) {
    True -> Ok(found)
    False ->
      case next() {
        Ok(bytes) ->
          collect(have: <<leftover:bits, bytes:bits>>, found:, done:, next:)
        Error(error) -> Error(error)
      }
  }
}

/// Splits the received bytes into their whole frames and the bytes left
/// over: the start of a frame whose end has not arrived. A length below the
/// header or over the size limit is an error as soon as its 4 bytes have
/// arrived, so a huge claimed length is never waited for.
pub fn decode(
  received received: BitArray,
) -> Result(#(List(Frame), BitArray), FrameError) {
  case split(received:) {
    #(frames, Ok(rest)) -> Ok(#(frames, rest))
    #(_, Error(error)) -> Error(error)
  }
}

/// Like `decode`, but a bad frame does not hide the whole frames before it:
/// the frames that arrived whole in order, and then either the bytes left over
/// or the error that stopped the cut.
pub fn split(
  received received: BitArray,
) -> #(List(Frame), Result(BitArray, FrameError)) {
  cut(received, [])
}

fn cut(
  received: BitArray,
  found: List(Frame),
) -> #(List(Frame), Result(BitArray, FrameError)) {
  case frame.take(received:) {
    Ok(Some(#(whole, rest))) -> cut(rest, [whole, ..found])
    Ok(None) -> #(list.reverse(found), Ok(received))
    Error(error) -> #(list.reverse(found), Error(error))
  }
}
