//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0636 (client_control_granted), server to client: gives the client
//// control of a unit's movement, after message 0x19B has set the controlled
//// unit; the client answers with message 0x635 carrying the value. Its fields
//// are listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x636` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0636

/// The body of message 0x0636, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type ClientControlGranted {
  ClientControlGranted(echo_value: Int, reset_movement: Int, unit_id: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ClientControlGranted) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("echo_value", message.echo_value, 32)
  |> bit_stream.write_unsigned("reset_movement", message.reset_movement, 1)
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ClientControlGranted, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(echo_value, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(reset_movement, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    1,
  ))
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ClientControlGranted(echo_value:, reset_movement:, unit_id:))
}
