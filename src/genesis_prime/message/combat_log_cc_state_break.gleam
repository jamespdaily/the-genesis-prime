//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a combat log entry of type 2: the unit
//// whose crowd-control state broke and the state. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x247.cc_state` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type CombatLogCcStateBreak {
  CombatLogCcStateBreak(unit_id: Int, state: CrowdControlState)
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: CombatLogCcStateBreak,
) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 2, 6)
  |> bit_stream.write_unsigned("unit_id", record.unit_id, 32)
  |> bit_stream.write_unsigned(
    "state",
    crowd_control_state.to_value(record.state),
    5,
  )
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(CombatLogCcStateBreak, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 6, 2))
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(state, reader) <- result.try(bit_stream.read_unsigned(reader, 5))
  let state = crowd_control_state.from_value(state)
  Ok(#(CombatLogCcStateBreak(unit_id:, state:), reader))
}
