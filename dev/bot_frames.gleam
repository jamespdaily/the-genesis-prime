//// What the scripted bots (`item_bot`, `quest_bot`) share: reading the frames one
//// message kind came in.

import genesis_prime/connection/frame.{type Frame}
import gleam/list

/// Every frame of the message id, decoded as the client's reader reads it, in the
/// order they came; a body the reader refuses stops the test, since the server
/// wrote it.
pub fn decoded(
  frames: List(Frame),
  message_id: Int,
  decode: fn(BitArray) -> Result(a, e),
) -> List(a) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id == message_id {
      True -> {
        let assert Ok(message) = decode(frame.body)
          as "the client's reader reads a message the server wrote"
        Ok(message)
      }
      False -> Error(Nil)
    }
  })
}
