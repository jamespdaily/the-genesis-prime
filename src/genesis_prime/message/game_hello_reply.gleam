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
    field_1: Int,
    session_key: BitArray,
    field_3: Int,
    account_name: String,
    field_5: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: GameHelloReply) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("field_1", message.field_1, 32)
  |> bit_stream.write_guid("session_key", message.session_key)
  |> bit_stream.write_unsigned("field_3", message.field_3, 64)
  |> bit_stream.write_wide_text("account_name", message.account_name)
  |> bit_stream.write_unsigned("field_5", message.field_5, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(GameHelloReply, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(field_1, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(session_key, reader) <- result.try(bit_stream.read_guid(reader))
  use #(field_3, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(account_name, reader) <- result.try(bit_stream.read_wide_text(reader))
  use #(field_5, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(GameHelloReply(field_1:, session_key:, field_3:, account_name:, field_5:))
}
