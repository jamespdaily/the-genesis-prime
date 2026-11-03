//// The one table from a client message id to the feature of the game
//// connection's rule (genesis_prime/game/connection) that takes it, and the
//// stage of the connection it is taken in. A new message of the player in the
//// world is one row here and the feature's own code and tests.
////
//// ```
//// whole frame in the client's wrapper 0x0244 ─▶ route(stage, OnItsOwn, id)
////                                                 ─▶ Hello, CharacterSelect(message), WorldEntry or WorldMessage
//// the frame inside 0x038C                    ─▶ route(stage, InsideWorldMessage, id)
////                                                 ─▶ Movement(message) or Camp(message)
//// a message with no row, or one not taken at the stage ─▶ Error(Nil): the rule logs it as unhandled
//// ```
////
//// - **A row names the feature's own kind of message**, so each feature's
////   dispatch is a case in the feature, over its own type
////   (genesis_prime/game/character_select, genesis_prime/game/movement,
////   genesis_prime/game/camp), and the connection holds none.
//// - **The stages** are where the connection is when a message is taken: before
////   the hello reply, in character select, or with the player in the world. In
////   any other state, with an ask out or a claim waiting, no frame is taken.
//// - **0x058F** is taken once, before the hello reply; a second one ends the
////   connection, which is the rule's shared part, not a feature's.
//// - **0x038C** carries one whole frame, which is every message the client sends
////   in the world (opcode.0x38c); the player's movement and camp messages are
////   taken from inside it with the player in the world, and any other is
////   unhandled.

import genesis_prime/game/camp
import genesis_prime/game/character_select
import genesis_prime/game/movement
import genesis_prime/message/camp_finished
import genesis_prime/message/camp_request
import genesis_prime/message/character_select_start
import genesis_prime/message/create_character_carrier
import genesis_prime/message/delete_character
import genesis_prime/message/fall_value
import genesis_prime/message/fell_below_floor
import genesis_prime/message/game_hello_reply
import genesis_prime/message/move_speed_setting
import genesis_prime/message/movement_send_interval_answer
import genesis_prime/message/play_character
import genesis_prime/message/player_movement
import genesis_prime/message/rename_character
import genesis_prime/message/terrain_loaded
import genesis_prime/message/world_message
import genesis_prime/message/zone_value_changed
import gleam/list
import gleam/result

/// The feature that takes a message, with the feature's own kind of it.
pub type Feature {
  /// The client's reply to the hello, 0x058F: the connection's own, shared
  /// part (the re-key and the hand-off).
  Hello
  CharacterSelect(message: character_select.Message)
  /// The client's request to play a character, 0x07DD
  /// (genesis_prime/game/world_entry).
  WorldEntry
  /// 0x038C, which carries every message the client sends in the world.
  WorldMessage
  Movement(message: movement.Message)
  Camp(message: camp.Message)
}

/// Where the connection is when it takes a message.
pub type Stage {
  /// The hello is sent and the reply 0x058F awaited.
  BeforeHelloReply
  /// The client is in character select.
  AtCharacterSelect
  /// The player is in the world.
  AtWorld
}

/// Where a message arrives: on its own, in the client's wrapper, or inside
/// 0x038C.
pub type Arrival {
  OnItsOwn
  InsideWorldMessage
}

/// One row: a message id, how it arrives, the feature that takes it and the
/// stages it is taken in.
type Row {
  Row(
    message_id: Int,
    arrival: Arrival,
    feature: Feature,
    taken_in: List(Stage),
  )
}

/// The table. A stage not listed for a row logs the message as unhandled, but
/// for 0x058F and a message before the hello reply (the rule ends the
/// connection for both).
const table = [
  Row(
    game_hello_reply.message_id,
    OnItsOwn,
    Hello,
    [BeforeHelloReply, AtCharacterSelect, AtWorld],
  ),
  Row(
    character_select_start.message_id,
    OnItsOwn,
    CharacterSelect(character_select.Started),
    [AtCharacterSelect],
  ),
  Row(
    create_character_carrier.message_id,
    OnItsOwn,
    CharacterSelect(character_select.CreateAsked),
    [AtCharacterSelect],
  ),
  Row(play_character.message_id, OnItsOwn, WorldEntry, [AtCharacterSelect]),
  Row(
    delete_character.message_id,
    OnItsOwn,
    CharacterSelect(character_select.DeleteAsked),
    [AtCharacterSelect],
  ),
  Row(
    rename_character.message_id,
    OnItsOwn,
    CharacterSelect(character_select.RenameAsked),
    [AtCharacterSelect],
  ),
  Row(
    world_message.message_id,
    OnItsOwn,
    WorldMessage,
    [AtCharacterSelect, AtWorld],
  ),
  Row(
    player_movement.message_id,
    InsideWorldMessage,
    Movement(movement.PlayerMoved),
    [AtWorld],
  ),
  Row(
    zone_value_changed.message_id,
    InsideWorldMessage,
    Movement(movement.ZoneChanged),
    [AtWorld],
  ),
  Row(
    movement_send_interval_answer.message_id,
    InsideWorldMessage,
    Movement(movement.IntervalAnswered),
    [AtWorld],
  ),
  Row(
    move_speed_setting.message_id,
    InsideWorldMessage,
    Movement(movement.SpeedChosen),
    [AtWorld],
  ),
  Row(
    terrain_loaded.message_id,
    InsideWorldMessage,
    Movement(movement.TerrainReady),
    [AtWorld],
  ),
  Row(
    fall_value.message_id,
    InsideWorldMessage,
    Movement(movement.Fell),
    [AtWorld],
  ),
  Row(
    fell_below_floor.message_id,
    InsideWorldMessage,
    Movement(movement.FellBelowFloor),
    [AtWorld],
  ),
  Row(
    camp_request.message_id,
    InsideWorldMessage,
    Camp(camp.CampAsked),
    [AtWorld],
  ),
  Row(
    camp_finished.message_id,
    InsideWorldMessage,
    Camp(camp.CampOver),
    [AtWorld],
  ),
]

/// The feature that takes the message with this id, arriving this way, at this
/// stage; `Error(Nil)` for a message with no row or one not taken at the
/// stage.
pub fn route(
  stage stage: Stage,
  arrival arrival: Arrival,
  message_id message_id: Int,
) -> Result(Feature, Nil) {
  list.find(table, fn(row) {
    row.message_id == message_id
    && row.arrival == arrival
    && list.contains(row.taken_in, stage)
  })
  |> result.map(fn(row) { row.feature })
}

/// The ids of the messages that arrive this way, in the table's order, whatever
/// stage takes them.
pub fn message_ids(arrival arrival: Arrival) -> List(Int) {
  list.filter_map(table, fn(row) {
    case row.arrival == arrival {
      True -> Ok(row.message_id)
      False -> Error(Nil)
    }
  })
}
