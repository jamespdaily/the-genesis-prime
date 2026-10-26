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
  todo as "the number and the body of a server message"
}
