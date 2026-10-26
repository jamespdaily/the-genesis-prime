//// Reads the frames a server wrote, as a test client does: bytes arrive in
//// reads of any size, so a frame may span reads and one read may hold several
//// (ReadConnectionMessages 0x1403321a0, ReadMessageFrame 0x140331990).

import genesis_prime/connection/frame.{type Frame}
import gleam/list

/// Reads until `count` frames have arrived. `have` is what was read before;
/// `next` reads more, and its error ends the wait.
pub fn read(
  have have: BitArray,
  count count: Int,
  next next: fn() -> Result(BitArray, Nil),
) -> Result(List(Frame), Nil) {
  let assert Ok(#(frames, leftover)) = frame.decode(have)
    as "the server wrote bytes that are frames"
  case list.length(frames) >= count {
    True -> Ok(frames)
    False ->
      case next() {
        Ok(bytes) -> read(have: <<leftover:bits, bytes:bits>>, count:, next:)
        Error(Nil) -> Error(Nil)
      }
  }
}
