//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0801 (cancel_cast), client to server: the client cancels one of
//// its player's casts: the cast id, the reason (6 when the cast's target died)
//// and one bit, which the client's sender always sets; the other senders of
//// the message and whether the id is the server's or the client's are not
//// read. Its fields are listed in `schema.toml` with the client's evidence,
//// and the fact file's `opcode.0x801` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/cast_result.{type CastResult}
import gleam/result

/// The message's number.
pub const message_id = 0x0801

/// The body of message 0x0801, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type CancelCast {
  CancelCast(cast_id: Int, reason: CastResult, field_3: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: CancelCast) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("cast_id", message.cast_id, 32)
  |> bit_stream.write_unsigned(
    "reason",
    cast_result.to_value(message.reason),
    9,
  )
  |> bit_stream.write_unsigned("field_3", message.field_3, 1)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(CancelCast, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(cast_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(reason, reader) <- result.try(bit_stream.read_unsigned(reader, 9))
  let reason = cast_result.from_value(reason)
  use #(field_3, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(CancelCast(cast_id:, reason:, field_3:))
}
