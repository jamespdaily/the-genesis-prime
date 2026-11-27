//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x03DB (game_server_handoff), server to client: the auth server's
//// hand-off to a game server, with its address, the session key and the
//// realm's name. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0x3db` names the message.

import genesis_prime/message/bit_stream.{
  type DecodeError, type EncodeError, type Endpoint,
}
import gleam/result

/// The message's number.
pub const message_id = 0x03DB

/// The body of message 0x03DB, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type GameServerHandoff {
  GameServerHandoff(
    game_server: Endpoint,
    session_key: BitArray,
    account_id: Int,
    realm_name: String,
    realm_flags: Int,
    realm_pvp_type: Int,
    realm_note_text_id: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: GameServerHandoff) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_endpoint("game_server", message.game_server)
  |> bit_stream.write_guid("session_key", message.session_key)
  |> bit_stream.write_unsigned("account_id", message.account_id, 32)
  |> bit_stream.write_wide_text("realm_name", message.realm_name)
  |> bit_stream.write_unsigned("realm_flags", message.realm_flags, 32)
  |> bit_stream.write_unsigned("realm_pvp_type", message.realm_pvp_type, 2)
  |> bit_stream.write_unsigned(
    "realm_note_text_id",
    message.realm_note_text_id,
    21,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(GameServerHandoff, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(game_server, reader) <- result.try(bit_stream.read_endpoint(reader))
  use #(session_key, reader) <- result.try(bit_stream.read_guid(reader))
  use #(account_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(realm_name, reader) <- result.try(bit_stream.read_wide_text(reader))
  use #(realm_flags, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(realm_pvp_type, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    2,
  ))
  use #(realm_note_text_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    21,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(GameServerHandoff(
    game_server:,
    session_key:,
    account_id:,
    realm_name:,
    realm_flags:,
    realm_pvp_type:,
    realm_note_text_id:,
  ))
}
