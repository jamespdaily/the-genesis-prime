//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0364 (quest_track), client to server: the client tracks (bit 1)
//// or stops tracking (bit 0) a quest in its tracker; the client has set its
//// own flag and waits for no answer. Its fields are listed in `schema.toml`
//// with the client's evidence, and the fact file's `opcode.0x364` names the
//// message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0364

/// The body of message 0x0364, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type QuestTrack {
  QuestTrack(quest_id: Int, tracked: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: QuestTrack) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("quest_id", message.quest_id, 15)
  |> bit_stream.write_unsigned("tracked", message.tracked, 1)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(QuestTrack, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(quest_id, reader) <- result.try(bit_stream.read_unsigned(reader, 15))
  use #(tracked, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(QuestTrack(quest_id:, tracked:))
}
