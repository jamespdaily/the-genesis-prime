//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00D5 (movement_send_interval_answer), client to server: the
//// client's answer to 0xF1, with three values the world handler keeps, whose
//// meaning the client's code does not show. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's `opcode.0xd5`
//// names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x00D5

/// The body of message 0x00D5, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type MovementSendIntervalAnswer {
  MovementSendIntervalAnswer(field_1: Int, field_2: Int, field_3: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(
  message: MovementSendIntervalAnswer,
) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("field_1", message.field_1, 4)
  |> bit_stream.write_unsigned("field_2", message.field_2, 1)
  |> bit_stream.write_unsigned("field_3", message.field_3, 14)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(
  body: BitArray,
) -> Result(MovementSendIntervalAnswer, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(field_1, reader) <- result.try(bit_stream.read_unsigned(reader, 4))
  use #(field_2, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(field_3, reader) <- result.try(bit_stream.read_unsigned(reader, 14))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(MovementSendIntervalAnswer(field_1:, field_2:, field_3:))
}
