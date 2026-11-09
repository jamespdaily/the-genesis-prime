//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0179 (server_tutorial), server to client: the Tutorial row the
//// client queues to show, which it drops when it has shown or queued that row
//// already. Its fields are listed in `schema.toml` with the client's evidence,
//// and the fact file's `opcode.0x179` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0179

/// The body of message 0x0179, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ServerTutorial {
  ServerTutorial(tutorial_id: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ServerTutorial) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("tutorial_id", message.tutorial_id, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ServerTutorial, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(tutorial_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ServerTutorial(tutorial_id:))
}
