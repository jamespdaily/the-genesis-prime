//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x088C (unit_death_state), server to client: a unit died or came
//// back: the unit id and the dead bit, a 5-bit value the client reads and does
//// not use and a 32-bit value it uses only when a unit under client control
//// comes back with it non-zero; the message sets no health and opens no
//// window. Its fields are listed in `schema.toml` with the client's evidence,
//// and the fact file's `opcode.0x88c` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x088C

/// The body of message 0x088C, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type UnitDeathState {
  UnitDeathState(
    unit_id: Int,
    dead: Int,
    /// Safe by `opcode.0x88c`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    unread_3: Int,
    /// Safe by `opcode.0x88c`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    health: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: UnitDeathState) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_unsigned("dead", message.dead, 1)
  |> bit_stream.write_unsigned("unread_3", message.unread_3, 5)
  |> bit_stream.write_unsigned("health", message.health, 32)
  |> bit_stream.finish
}

/// The message as the bytes of its body, for values that fit their fields; a
/// value that does not ends the process, naming the message and the field.
pub fn must_encode(message: UnitDeathState) -> BitArray {
  bit_stream.must(encode(message), "unit_death_state")
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(UnitDeathState, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(dead, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(unread_3, reader) <- result.try(bit_stream.read_unsigned(reader, 5))
  use #(health, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(UnitDeathState(unit_id:, dead:, unread_3:, health:))
}
