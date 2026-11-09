//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one reward property: its id (a
//// RewardProperty id), its data, its value and the modifiers of the value; the
//// server sends none. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0x92c` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/reward_property_integer.{type RewardPropertyInteger}
import genesis_prime/message/reward_property_modifier.{
  type RewardPropertyModifier,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type RewardPropertyEntry {
  RewardPropertyEntry(
    property_id: Int,
    data: Int,
    value: RewardPropertyInteger,
    modifiers: List(RewardPropertyModifier),
  )
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: RewardPropertyEntry,
) -> Writer {
  writer
  |> bit_stream.write_unsigned("property_id", record.property_id, 6)
  |> bit_stream.write_unsigned("data", record.data, 32)
  |> reward_property_integer.write(record.value)
  |> bit_stream.write_array(
    "modifiers",
    record.modifiers,
    8,
    reward_property_modifier.write,
  )
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(RewardPropertyEntry, Reader), DecodeError) {
  use #(property_id, reader) <- result.try(bit_stream.read_unsigned(reader, 6))
  use #(data, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(value, reader) <- result.try(reward_property_integer.read(reader))
  use #(modifiers, reader) <- result.try(bit_stream.read_array(
    reader,
    8,
    reward_property_modifier.read,
  ))
  Ok(#(RewardPropertyEntry(property_id:, data:, value:, modifiers:), reader))
}
