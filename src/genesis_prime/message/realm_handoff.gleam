//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x07A1 (realm_handoff), server to client: the game server's
//// hand-off to another realm's server, with its address, the session key and
//// the realm's name. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0x7a1` names the message.

import genesis_prime/message/bit_stream.{
  type DecodeError, type EncodeError, type Endpoint,
}
import gleam/result

/// The message's number.
pub const message_id = 0x07A1

/// The body of message 0x07A1, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type RealmHandoff {
  RealmHandoff(
    unread_1: Int,
    session_key: BitArray,
    realm_server: Endpoint,
    unread_4: Int,
    realm_name: String,
    /// Open: What does the client use the kept 32-bit value for (game 0x1684)?
    /// It may be the realm's flags, as in game_server_handoff; the handler
    /// keeps it and no reader was traced (opcode.0x7a1).
    field_6: Int,
    /// Open: What does the client use the kept 2-bit value for (game 0x1688)?
    /// It may be the realm's PvP type, as in game_server_handoff; the handler
    /// keeps it and no reader was traced (opcode.0x7a1).
    field_7: Int,
    /// Open: What does the client use the kept 21-bit value for (game 0x168c)?
    /// It may be the realm's note text id, as in game_server_handoff; the
    /// handler keeps it and no reader was traced (opcode.0x7a1).
    field_8: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: RealmHandoff) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unread_1", message.unread_1, 32)
  |> bit_stream.write_guid("session_key", message.session_key)
  |> bit_stream.write_endpoint("realm_server", message.realm_server)
  |> bit_stream.write_unsigned("unread_4", message.unread_4, 1)
  |> bit_stream.write_wide_text("realm_name", message.realm_name)
  |> bit_stream.write_unsigned("field_6", message.field_6, 32)
  |> bit_stream.write_unsigned("field_7", message.field_7, 2)
  |> bit_stream.write_unsigned("field_8", message.field_8, 21)
  |> bit_stream.finish
}

/// The message as the bytes of its body, for values that fit their fields; a
/// value that does not ends the process, naming the message and the field.
pub fn must_encode(message: RealmHandoff) -> BitArray {
  bit_stream.must(encode(message), "")
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(RealmHandoff, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unread_1, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(session_key, reader) <- result.try(bit_stream.read_guid(reader))
  use #(realm_server, reader) <- result.try(bit_stream.read_endpoint(reader))
  use #(unread_4, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(realm_name, reader) <- result.try(bit_stream.read_wide_text(reader))
  use #(field_6, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_7, reader) <- result.try(bit_stream.read_unsigned(reader, 2))
  use #(field_8, reader) <- result.try(bit_stream.read_unsigned(reader, 21))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(RealmHandoff(
    unread_1:,
    session_key:,
    realm_server:,
    unread_4:,
    realm_name:,
    field_6:,
    field_7:,
    field_8:,
  ))
}
