//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0935 (unit_float_stat_changed), server to client: a unit's stat
//// changed, as a float: the only message after a unit's creation that sets its
//// resource slots, stat n + 2 setting slot n for stats 2 to 9; the client
//// applies it with an integer of 0, so stats read as integers (10, 20, 22) are
//// never sent this way. Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `opcode.0x935` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0935

/// The body of message 0x0935, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type UnitFloatStatChanged {
  UnitFloatStatChanged(unit_id: Int, stat_id: Int, value: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: UnitFloatStatChanged) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_unsigned("stat_id", message.stat_id, 5)
  |> bit_stream.write_float32_bits("value", message.value)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(UnitFloatStatChanged, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(stat_id, reader) <- result.try(bit_stream.read_unsigned(reader, 5))
  use #(value, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(UnitFloatStatChanged(unit_id:, stat_id:, value:))
}
