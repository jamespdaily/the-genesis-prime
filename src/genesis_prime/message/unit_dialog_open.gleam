//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0357 (unit_dialog_open), server to client: opens a unit's dialog,
//// the answer to the client's request to talk to the unit. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x357` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0357

/// The body of message 0x0357, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type UnitDialogOpen {
  UnitDialogOpen(
    unit_id: Int,
    /// Safe by `0x140554510`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    unread_2: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: UnitDialogOpen) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_unsigned("unread_2", message.unread_2, 1)
  |> bit_stream.finish
}

/// The message as the bytes of its body, for values that fit their fields; a
/// value that does not ends the process, naming the message and the field.
pub fn must_encode(message: UnitDialogOpen) -> BitArray {
  bit_stream.must(encode(message), "")
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(UnitDialogOpen, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(unread_2, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(UnitDialogOpen(unit_id:, unread_2:))
}
