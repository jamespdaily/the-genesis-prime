//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one modifier of a reward property's value:
//// its kind, its data and its value; the server sends none. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x92c` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/reward_property_integer.{type RewardPropertyInteger}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type RewardPropertyModifier {
  RewardPropertyModifier(
    /// Safe by `opcode.0x92c`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    kind: Int,
    /// Safe by `opcode.0x92c`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    data: Int,
    value: RewardPropertyInteger,
  )
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: RewardPropertyModifier,
) -> Writer {
  writer
  |> bit_stream.write_unsigned("kind", record.kind, 4)
  |> bit_stream.write_unsigned("data", record.data, 32)
  |> reward_property_integer.write(record.value)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(RewardPropertyModifier, Reader), DecodeError) {
  use #(kind, reader) <- result.try(bit_stream.read_unsigned(reader, 4))
  use #(data, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(value, reader) <- result.try(reward_property_integer.read(reader))
  Ok(#(RewardPropertyModifier(kind:, data:, value:), reader))
}
