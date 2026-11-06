//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x087F (unit_cc_state_applied), server to client: a unit holds a
//// crowd-control state: the unit, the state and the instance id of the
//// CCStateSet effect the cast's 0x7f4 listed for it; whichever of the 0x7f4
//// and this message comes second makes the state take hold, so the id must be
//// non-zero and the one the go gave (`cc_state.instance_id`). Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x87f` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import gleam/result

/// The message's number.
pub const message_id = 0x087F

/// The body of message 0x087F, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type UnitCcStateApplied {
  UnitCcStateApplied(unit_id: Int, state: CrowdControlState, instance_id: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: UnitCcStateApplied) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_unsigned(
    "state",
    crowd_control_state.to_value(message.state),
    5,
  )
  |> bit_stream.write_unsigned("instance_id", message.instance_id, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(UnitCcStateApplied, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(state, reader) <- result.try(bit_stream.read_unsigned(reader, 5))
  let state = crowd_control_state.from_value(state)
  use #(instance_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(UnitCcStateApplied(unit_id:, state:, instance_id:))
}
