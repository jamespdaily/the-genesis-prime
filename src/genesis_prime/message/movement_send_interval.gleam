//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00F1 (movement_send_interval), server to client: sets the
//// interval at which the client sends the player's movement commands. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `opcode.0xf1` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x00F1

/// The body of message 0x00F1, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type MovementSendInterval {
  MovementSendInterval(
    field_1: Int,
    field_2: Int,
    field_3: Int,
    interval_milliseconds: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: MovementSendInterval) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("field_1", message.field_1, 2)
  |> bit_stream.write_unsigned("field_2", message.field_2, 32)
  |> bit_stream.write_unsigned("field_3", message.field_3, 8)
  |> bit_stream.write_unsigned(
    "interval_milliseconds",
    message.interval_milliseconds,
    32,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(MovementSendInterval, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(field_1, reader) <- result.try(bit_stream.read_unsigned(reader, 2))
  use #(field_2, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_3, reader) <- result.try(bit_stream.read_unsigned(reader, 8))
  use #(interval_milliseconds, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(MovementSendInterval(field_1:, field_2:, field_3:, interval_milliseconds:))
}
