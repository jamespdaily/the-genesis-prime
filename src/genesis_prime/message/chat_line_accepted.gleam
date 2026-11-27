//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x01C2 (chat_line_accepted), server to client: the answer that
//// shows the speaker its own line: the slot's id, the name to show (the
//// speaker's, or the target's for a whisper), its realm name and the speaker's
//// unit id; the server writes no item record (the item count is 0), so a
//// line's item links are shown as the client's own type 9 links. Its fields
//// are listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x1c2` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x01C2

/// The body of message 0x01C2, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ChatLineAccepted {
  ChatLineAccepted(
    chat_message_id: Int,
    gm: Int,
    name: String,
    realm_name: String,
    unit_id: Int,
    premium_tier: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ChatLineAccepted) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("chat_message_id", message.chat_message_id, 16)
  |> bit_stream.write_unsigned("gm", message.gm, 1)
  |> bit_stream.write_constant("item_count", 0, 5)
  |> bit_stream.write_wide_text("name", message.name)
  |> bit_stream.write_wide_text("realm_name", message.realm_name)
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_unsigned("premium_tier", message.premium_tier, 8)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ChatLineAccepted, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(chat_message_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    16,
  ))
  use #(gm, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use reader <- result.try(bit_stream.read_constant(reader, "item_count", 5, 0))
  use #(name, reader) <- result.try(bit_stream.read_wide_text(reader))
  use #(realm_name, reader) <- result.try(bit_stream.read_wide_text(reader))
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(premium_tier, reader) <- result.try(bit_stream.read_unsigned(reader, 8))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ChatLineAccepted(
    chat_message_id:,
    gm:,
    name:,
    realm_name:,
    unit_id:,
    premium_tier:,
  ))
}
