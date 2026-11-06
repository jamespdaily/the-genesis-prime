//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x07F9 (spell_failed), server to client: a cast fails with a
//// result: the client finds the cast (an unknown id is dropped) and ends it as
//// a finish does, with that result, which destroys every target node the cast
//// holds, so its effects and the buffs they make end, and leaves the cast
//// filed; the server sends it with a persistence result (282, 283) when a
//// lasting cast's condition stops holding, then the 0x7fe that takes the cast
//// out of the client's table. Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `opcode.0x7f9` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/cast_result.{type CastResult}
import gleam/result

/// The message's number.
pub const message_id = 0x07F9

/// The body of message 0x07F9, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type SpellFailed {
  SpellFailed(
    cast_id: Int,
    result: CastResult,
    unit_id: Int,
    /// Safe by `opcode.0x7f9`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_4: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: SpellFailed) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("cast_id", message.cast_id, 32)
  |> bit_stream.write_unsigned(
    "result",
    cast_result.to_value(message.result),
    9,
  )
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_unsigned("field_4", message.field_4, 1)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(SpellFailed, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(cast_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(result, reader) <- result.try(bit_stream.read_unsigned(reader, 9))
  let result = cast_result.from_value(result)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_4, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(SpellFailed(cast_id:, result:, unit_id:, field_4:))
}
