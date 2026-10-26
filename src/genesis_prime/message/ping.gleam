//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0000 (ping), client to server: the network layer's ping, which
//// travels bare on every connection and which the server answers at once with
//// a pong carrying the same number. Its fields are listed in `schema.toml`
//// with the client's evidence, and the fact file's `opcode.0x0` names the
//// message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0000

/// The body of message 0x0000, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type Ping {
  Ping(sequence_number: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: Ping) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned_below(
    "sequence_number",
    message.sequence_number,
    8,
    20,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(Ping, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(sequence_number, reader) <- result.try(bit_stream.read_unsigned_below(
    reader,
    "sequence_number",
    8,
    20,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(Ping(sequence_number:))
}
