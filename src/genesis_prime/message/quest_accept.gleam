//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x035B (quest_accept), client to server: the client accepts a
//// quest: the held item that starts it, or location 300 and bag index -1 (the
//// 32-bit all-ones value) when the dialog's accept response sends it, and the
//// quest id; the client sends nothing when it could not start the quest,
//// changes no state, and waits for 0x35c. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x35b` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/item_place.{type ItemPlace}
import gleam/result

/// The message's number.
pub const message_id = 0x035B

/// The body of message 0x035B, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type QuestAccept {
  QuestAccept(item: ItemPlace, quest_id: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: QuestAccept) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> item_place.write(message.item)
  |> bit_stream.write_unsigned("quest_id", message.quest_id, 15)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(QuestAccept, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(item, reader) <- result.try(item_place.read(reader))
  use #(quest_id, reader) <- result.try(bit_stream.read_unsigned(reader, 15))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(QuestAccept(item:, quest_id:))
}
