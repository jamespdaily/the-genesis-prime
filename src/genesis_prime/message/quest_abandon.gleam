//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x035A (quest_abandon), client to server: the client abandons a
//// quest, only when it allows it (Accepted, Achieved, Botched or Mentioned;
//// not Quest2.flags 0x4000 unless Botched; not Achieved with flags 0x8000):
//// only the quest id; the client changes no state and the server's 0x35c
//// answer sets it. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0x35a` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x035A

/// The body of message 0x035A, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type QuestAbandon {
  QuestAbandon(quest_id: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: QuestAbandon) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("quest_id", message.quest_id, 15)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(QuestAbandon, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(quest_id, reader) <- result.try(bit_stream.read_unsigned(reader, 15))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(QuestAbandon(quest_id:))
}
