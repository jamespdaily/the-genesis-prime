//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x07A5 (replay_level_up), client to server: the client asks for the
//// fanfare of a level: its level-up fanfare sends its unit's level 2000 ms
//// after the level rises, and the Level Up Unlocks window's Replay button
//// sends the level the player picked, never above the unit's own; the client
//// draws and plays nothing for it itself, the answer is a cast of the Level Up
//// spell. Its fields are listed in `schema.toml` with the client's evidence,
//// and the fact file's `opcode.0x7a5` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x07A5

/// The body of message 0x07A5, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ReplayLevelUp {
  ReplayLevelUp(level: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ReplayLevelUp) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("level", message.level, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ReplayLevelUp, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(level, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ReplayLevelUp(level:))
}
