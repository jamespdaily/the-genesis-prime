//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A union inside a message body: the value of one stat of a new unit: the
//// form in 2 bits picks how it is written, 0 a 32-bit integer and 1 a 32-bit
//// float; the server writes no form 2 (two integers), and form 3 refuses the
//// message. Its variants are listed in `schema.toml` with the client's
//// evidence, and the fact file's `0x140096230` names the union.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/unit_stat_float.{type UnitStatFloat}
import genesis_prime/message/unit_stat_integer.{type UnitStatInteger}
import gleam/pair
import gleam/result

/// One item of the union: its first 2 bits are its kind, which picks the
/// variant, and the variant's record reads them again as its first field. A
/// kind no variant has is refused.
pub type UnitStatValue {
  /// Kind 0, read by `unit_stat_integer`. The fact file's `0x140096230` names
  /// the kind.
  Integer(UnitStatInteger)
  /// Kind 1, read by `unit_stat_float`. The fact file's `0x140080c60` names the
  /// kind.
  Float(UnitStatFloat)
}

/// Writes the variant's record to the stream.
pub fn write(writer writer: Writer, record record: UnitStatValue) -> Writer {
  case record {
    Integer(variant) -> unit_stat_integer.write(writer, variant)
    Float(variant) -> unit_stat_float.write(writer, variant)
  }
}

/// Reads the item from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(UnitStatValue, Reader), DecodeError) {
  use kind <- result.try(bit_stream.peek_unsigned(reader, 2))
  case kind {
    0 ->
      reader
      |> unit_stat_integer.read
      |> result.map(pair.map_first(_, Integer))
    1 -> reader |> unit_stat_float.read |> result.map(pair.map_first(_, Float))
    _ ->
      Error(bit_stream.UnexpectedValue(field: "unit_stat_value", value: kind))
  }
}
