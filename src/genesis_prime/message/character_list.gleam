//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0117 (character_list), server to client: the account's character
//// list the client shows in character select, with the creation choices the
//// server enables and disables. Its fields are listed in `schema.toml` with
//// the client's evidence, and the fact file's `opcode.0x117` names the
//// message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/character_list_entry.{type CharacterListEntry}
import gleam/result

/// The message's number.
pub const message_id = 0x0117

/// The body of message 0x0117, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type CharacterList {
  CharacterList(
    server_time: Int,
    characters: List(CharacterListEntry),
    enabled_creation_ids: List(Int),
    disabled_creation_ids: List(Int),
    realm_id: Int,
    pending_removal_realm_id: Int,
    pending_removal_character_id: Int,
    pending_removal_time: Int,
    reservations: Int,
    max_characters: Int,
    field_11: Int,
    faction_restriction: Int,
    free_level_50_available: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: CharacterList) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("server_time", message.server_time, 64)
  |> bit_stream.write_array(
    "characters",
    message.characters,
    32,
    character_list_entry.write,
  )
  |> bit_stream.write_unsigned_array(
    "enabled_creation_ids",
    message.enabled_creation_ids,
    32,
    32,
  )
  |> bit_stream.write_unsigned_array(
    "disabled_creation_ids",
    message.disabled_creation_ids,
    32,
    32,
  )
  |> bit_stream.write_unsigned("realm_id", message.realm_id, 14)
  |> bit_stream.write_unsigned(
    "pending_removal_realm_id",
    message.pending_removal_realm_id,
    14,
  )
  |> bit_stream.write_unsigned(
    "pending_removal_character_id",
    message.pending_removal_character_id,
    64,
  )
  |> bit_stream.write_unsigned(
    "pending_removal_time",
    message.pending_removal_time,
    32,
  )
  |> bit_stream.write_unsigned("reservations", message.reservations, 32)
  |> bit_stream.write_unsigned("max_characters", message.max_characters, 32)
  |> bit_stream.write_unsigned("field_11", message.field_11, 32)
  |> bit_stream.write_unsigned(
    "faction_restriction",
    message.faction_restriction,
    14,
  )
  |> bit_stream.write_unsigned(
    "free_level_50_available",
    message.free_level_50_available,
    1,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(CharacterList, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(server_time, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(characters, reader) <- result.try(bit_stream.read_array(
    reader,
    32,
    character_list_entry.read,
  ))
  use #(enabled_creation_ids, reader) <- result.try(
    bit_stream.read_unsigned_array(reader, 32, 32),
  )
  use #(disabled_creation_ids, reader) <- result.try(
    bit_stream.read_unsigned_array(reader, 32, 32),
  )
  use #(realm_id, reader) <- result.try(bit_stream.read_unsigned(reader, 14))
  use #(pending_removal_realm_id, reader) <- result.try(
    bit_stream.read_unsigned(reader, 14),
  )
  use #(pending_removal_character_id, reader) <- result.try(
    bit_stream.read_unsigned(reader, 64),
  )
  use #(pending_removal_time, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(reservations, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(max_characters, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(field_11, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(faction_restriction, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    14,
  ))
  use #(free_level_50_available, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    1,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(CharacterList(
    server_time:,
    characters:,
    enabled_creation_ids:,
    disabled_creation_ids:,
    realm_id:,
    pending_removal_realm_id:,
    pending_removal_character_id:,
    pending_removal_time:,
    reservations:,
    max_characters:,
    field_11:,
    faction_restriction:,
    free_level_50_available:,
  ))
}
