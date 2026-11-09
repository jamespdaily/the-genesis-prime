//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x056A (item_action_failed), server to client: an item action
//// failed: a guid the client does not read and a GenericError code, which the
//// client raises to its UI when it is not 0; the client always clears its move
//// wait. Its fields are listed in `schema.toml` with the client's evidence,
//// and the fact file's `opcode.0x56a` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x056A

/// The body of message 0x056A, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ItemActionFailed {
  ItemActionFailed(
    /// Safe by `opcode.0x56a`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    item_guid: Int,
    code: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ItemActionFailed) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("item_guid", message.item_guid, 64)
  |> bit_stream.write_unsigned("code", message.code, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ItemActionFailed, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(item_guid, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(code, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ItemActionFailed(item_guid:, code:))
}
