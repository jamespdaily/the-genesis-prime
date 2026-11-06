//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x093A (unit_properties_changed), server to client: some of a
//// unit's properties changed: the unit and the entries, each a UnitProperty2
//// id with its base and value. The client stores both words as sent and works
//// none out; it ignores an unknown unit, and an id of 197 or more fails the
//// message at that entry, after the entries before it are stored. Its fields
//// are listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x93a` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/unit_property.{type UnitProperty}
import gleam/result

/// The message's number.
pub const message_id = 0x093A

/// The body of message 0x093A, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type UnitPropertiesChanged {
  UnitPropertiesChanged(unit_id: Int, properties: List(UnitProperty))
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: UnitPropertiesChanged) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_array(
    "properties",
    message.properties,
    8,
    unit_property.write,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(UnitPropertiesChanged, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(properties, reader) <- result.try(bit_stream.read_array(
    reader,
    8,
    unit_property.read,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(UnitPropertiesChanged(unit_id:, properties:))
}
