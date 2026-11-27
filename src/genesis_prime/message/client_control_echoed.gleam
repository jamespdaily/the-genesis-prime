//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0635 (client_control_echoed), client to server: the client's
//// answer to message 0x636, carrying back the value 0x636 brought. Its fields
//// are listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x635` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0635

/// The body of message 0x0635, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ClientControlEchoed {
  ClientControlEchoed(echo_value: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ClientControlEchoed) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("echo_value", message.echo_value, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ClientControlEchoed, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(echo_value, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ClientControlEchoed(echo_value:))
}
