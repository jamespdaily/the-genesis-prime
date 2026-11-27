//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x058F (game_hello_reply), client to server: the first message on a
//// game connection, sent when the server's hello arrives, with the session
//// key. Its fields are listed in `schema.toml` with the client's evidence, and
//// the fact file's `opcode.0x58f` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x058F

/// The body of message 0x058F, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type GameHelloReply {
  GameHelloReply(
    account_id: Int,
    session_key: BitArray,
    zero: Int,
    account_name: String,
    three: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: GameHelloReply) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("account_id", message.account_id, 32)
  |> bit_stream.write_guid("session_key", message.session_key)
  |> bit_stream.write_unsigned("zero", message.zero, 64)
  |> bit_stream.write_wide_text("account_name", message.account_name)
  |> bit_stream.write_unsigned("three", message.three, 32)
  |> bit_stream.finish
}

/// The message as the bytes of its body, for values that fit their fields; a
/// value that does not ends the process, naming the message and the field.
pub fn must_encode(message: GameHelloReply) -> BitArray {
  bit_stream.must(encode(message), "")
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(GameHelloReply, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(account_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(session_key, reader) <- result.try(bit_stream.read_guid(reader))
  use #(zero, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(account_name, reader) <- result.try(bit_stream.read_wide_text(reader))
  use #(three, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(GameHelloReply(account_id:, session_key:, zero:, account_name:, three:))
}
