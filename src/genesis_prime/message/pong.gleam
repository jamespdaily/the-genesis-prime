//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0001 (pong), either direction: the network layer's pong, the
//// answer to a ping with the ping's number, which travels bare; the client
//// ignores a number of 20 or more. Its fields are listed in `schema.toml` with
//// the client's evidence, and the fact file's `opcode.0x1` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0001

/// The body of message 0x0001, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type Pong {
  Pong(sequence_number: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: Pong) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("sequence_number", message.sequence_number, 8)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(Pong, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(sequence_number, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    8,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(Pong(sequence_number:))
}
