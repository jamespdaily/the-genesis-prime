//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x036A (disconnect_notice), server to client: tells the client it
//// is being disconnected, with the reason it shows as a text. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x36a` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x036A

/// The body of message 0x036A, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type DisconnectNotice {
  DisconnectNotice(reason: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: DisconnectNotice) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("reason", message.reason, 5)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(DisconnectNotice, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(reason, reader) <- result.try(bit_stream.read_unsigned(reader, 5))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(DisconnectNotice(reason:))
}
