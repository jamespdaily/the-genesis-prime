//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0938 (unit_stat_changed), server to client: a unit's stat
//// changed, as an integer: stat 20 is the shield, 21 the Interrupt Armor
//// (clamped by the client to 0 and the unit's maximum), 22 the absorption and
//// 10 the level, and stat 0 (health) is not taken here; the server writes it
//// only for stats 20 and 21, since for stats 2 to 9 it sets the resource slot
//// to 0 (0x935 sets those). Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `opcode.0x938` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/stat_kind.{type StatKind}
import gleam/result

/// The message's number.
pub const message_id = 0x0938

/// The body of message 0x0938, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type UnitStatChanged {
  UnitStatChanged(unit_id: Int, stat: StatKind, value: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: UnitStatChanged) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_unsigned("stat", stat_kind.to_value(message.stat), 5)
  |> bit_stream.write_unsigned("value", message.value, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(UnitStatChanged, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(stat, reader) <- result.try(bit_stream.read_unsigned(reader, 5))
  let stat = stat_kind.from_value(stat)
  use #(value, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(UnitStatChanged(unit_id:, stat:, value:))
}
