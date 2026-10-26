//// The messages the server sends while a player selects a character and enters
//// the world, as the typed values of the message codec, and the message number
//// and body bytes of each.

import genesis_prime/message/bit_stream.{type EncodeError}
import genesis_prime/message/character_list.{type CharacterList}
import genesis_prime/message/create_character_result.{type CreateCharacterResult}
import genesis_prime/message/delete_character_result.{type DeleteCharacterResult}
import genesis_prime/message/enter_world.{type EnterWorld}
import genesis_prime/message/movement_send_interval.{type MovementSendInterval}
import genesis_prime/message/play_character_refused.{type PlayCharacterRefused}
import genesis_prime/message/player_entered_world.{type PlayerEnteredWorld}
import genesis_prime/message/rename_character_result.{type RenameCharacterResult}
import genesis_prime/message/unit_create_player.{type UnitCreatePlayer}
import genesis_prime/message/unit_is_player.{type UnitIsPlayer}
import gleam/result

/// One message the server sends in character select or while the player
/// enters the world.
pub type ServerMessage {
  /// Message 0x117.
  CharacterListed(CharacterList)
  /// Message 0xDC.
  CreateResult(CreateCharacterResult)
  /// Message 0x14B.
  RenameResult(RenameCharacterResult)
  /// Message 0xE6.
  DeleteResult(DeleteCharacterResult)
  /// Message 0x162.
  PlayRefused(PlayCharacterRefused)
  /// Message 0xAD.
  WorldEntered(EnterWorld)
  /// Message 0x262.
  UnitCreated(UnitCreatePlayer)
  /// Message 0x19B.
  PlayerUnitSet(UnitIsPlayer)
  /// Message 0xF1.
  MovementIntervalSet(MovementSendInterval)
  /// Message 0x61.
  PlayerEntered(PlayerEnteredWorld)
}

/// The message's number and the bytes of its body, or the first field that
/// cannot be written.
pub fn encode(
  message message: ServerMessage,
) -> Result(#(Int, BitArray), EncodeError) {
  case message {
    CharacterListed(body) ->
      numbered(character_list.message_id, character_list.encode(body))
    CreateResult(body) ->
      numbered(
        create_character_result.message_id,
        create_character_result.encode(body),
      )
    RenameResult(body) ->
      numbered(
        rename_character_result.message_id,
        rename_character_result.encode(body),
      )
    DeleteResult(body) ->
      numbered(
        delete_character_result.message_id,
        delete_character_result.encode(body),
      )
    PlayRefused(body) ->
      numbered(
        play_character_refused.message_id,
        play_character_refused.encode(body),
      )
    WorldEntered(body) ->
      numbered(enter_world.message_id, enter_world.encode(body))
    UnitCreated(body) ->
      numbered(unit_create_player.message_id, unit_create_player.encode(body))
    PlayerUnitSet(body) ->
      numbered(unit_is_player.message_id, unit_is_player.encode(body))
    MovementIntervalSet(body) ->
      numbered(
        movement_send_interval.message_id,
        movement_send_interval.encode(body),
      )
    PlayerEntered(body) ->
      numbered(
        player_entered_world.message_id,
        player_entered_world.encode(body),
      )
  }
}

fn numbered(
  number: Int,
  body: Result(BitArray, EncodeError),
) -> Result(#(Int, BitArray), EncodeError) {
  result.map(body, fn(bytes) { #(number, bytes) })
}
