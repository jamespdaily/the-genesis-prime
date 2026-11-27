//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0880 (unit_cc_state_ended), server to client: a unit's
//// crowd-control state ends: the unit, the state, the cast id (0 any cast),
//// the effect instance id (0 any) and one bit that keeps an entry whose effect
//// has dataBits02 flag 4; the only message that ends a held state while the
//// unit lives (`cc_state.end`). Its fields are listed in `schema.toml` with
//// the client's evidence, and the fact file's `opcode.0x880` names the
//// message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import gleam/result

/// The message's number.
pub const message_id = 0x0880

/// The body of message 0x0880, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type UnitCcStateEnded {
  UnitCcStateEnded(
    unit_id: Int,
    state: CrowdControlState,
    cast_id: Int,
    instance_id: Int,
    keeps_flag_4_entries: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: UnitCcStateEnded) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_unsigned(
    "state",
    crowd_control_state.to_value(message.state),
    5,
  )
  |> bit_stream.write_unsigned("cast_id", message.cast_id, 32)
  |> bit_stream.write_unsigned("instance_id", message.instance_id, 32)
  |> bit_stream.write_unsigned(
    "keeps_flag_4_entries",
    message.keeps_flag_4_entries,
    1,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(UnitCcStateEnded, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(state, reader) <- result.try(bit_stream.read_unsigned(reader, 5))
  let state = crowd_control_state.from_value(state)
  use #(cast_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(instance_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(keeps_flag_4_entries, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    1,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(UnitCcStateEnded(
    unit_id:,
    state:,
    cast_id:,
    instance_id:,
    keeps_flag_4_entries:,
  ))
}
