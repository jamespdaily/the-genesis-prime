//// Entering the world: what the server sends, and in which order, from the
//// moment a player chose a character until the client shows the player in the
//// world. A rule: state and input in, new state and effects out.
////
//// The order is the one the client's own end of loading needs
//// (CheckWorldLoaded 0x1403E8000). The map gives the character's unit an id.
//// The server then sends 0xAD (the world and the position the client loads),
//// 0x262 (the player's unit), 0x19B (that unit is the player; the client
//// reports an error and never finishes loading when the unit does not exist
//// yet), 0x636 (the client takes control of that unit and answers with 0x635;
//// it is ignored before 0x19B) and 0xF1 (the movement send interval, whose
//// handler sets a flag the end of loading waits for). The client sends 0xF2 when the terrain near the player
//// is ready; only then does the server send 0x61, which the client reads the
//// player's position for and which must come after 0x19B.

import genesis_prime/character/character.{type Character}
import genesis_prime/character/server_message.{
  type ServerMessage, ControlGranted, MovementIntervalSet, PlayRefused,
  PlayerEntered, PlayerUnitSet, UnitCreated, WorldEntered,
}
import genesis_prime/map/unit.{type Newcomer, type PlayerUnit}
import genesis_prime/message/client_control_granted.{ClientControlGranted}
import genesis_prime/message/enter_world.{EnterWorld}
import genesis_prime/message/float32
import genesis_prime/message/movement_send_interval.{MovementSendInterval}
import genesis_prime/message/play_character_refused.{PlayCharacterRefused}
import genesis_prime/message/player_entered_world.{PlayerEnteredWorld}
import genesis_prime/message/unit_create_player.{
  type UnitCreatePlayer, UnitCreatePlayer,
}
import genesis_prime/message/unit_is_player.{UnitIsPlayer}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/message/unit_stat.{UnitStat}
import gleam/int

/// The movement send interval the server sets, in milliseconds: the client's
/// own default, 125 (the bytes at 0x140C3A004), so a client that is given none
/// moves at the same rate.
const movement_send_interval_milliseconds = 125

/// The health a new player's unit is created with, in stat 0 and in property
/// 7 of message 0x262. It is CreatureLevel row 1's BaseHealth (135.97), a
/// creature's value, used because no client table holds a player's health: a
/// graded guess that wants a retail record.
pub const player_health_stand_in = 136

/// The id of the stat in message 0x262 that holds a unit's health: the client
/// reads health from stat 0 (0x140458140, 0x140457bc5).
const health_stat_id = 0

/// The id of the property in message 0x262 that holds a unit's maximum health:
/// property 7 is BaseHealth, which GetMaxHealth reads (0x1404584b0,
/// vector.opcode.0x262.health).
const base_health_property_id = 7

/// The value message 0x636 carries and the client echoes in 0x635. The client
/// uses it for nothing else, so any value serves (opcode.0x636).
pub const control_echo_value = 0

/// The value of message 0x162 when a character cannot enter because its world
/// is not one the client can load: PreGameLib.CodeEnumCharacterSelectResults'
/// Failed.
const play_failed = 2

/// The value of message 0x162 when the map refuses a character that is on it
/// already: PreGameLib.CodeEnumCharacterSelectResults' FailedCharacterInWorld.
const play_failed_character_in_world = 4

/// The facts the rule reads beyond its state: `realm_id` is the realm the
/// connection is on, which the player's unit carries, and `world_exists` tells
/// whether a World row has the id, because the client fails to load a world
/// with none.
pub type Context {
  Context(realm_id: Int, world_exists: fn(Int) -> Bool)
}

/// Where the entry has got to.
pub type State {
  /// The player has not chosen a character.
  Waiting
  /// The map was asked to join the character's unit.
  AwaitingMap(character: Character)
  /// The client has the world messages and loads the terrain; the server waits
  /// for 0xF2.
  AwaitingTerrain(unit: PlayerUnit)
  /// As `AwaitingTerrain`, and the client's 0x635 has come.
  AwaitingTerrainEchoed(unit: PlayerUnit)
  /// The client has the player in the world.
  Entered
  /// As `Entered`, and the client's 0x635 has come.
  EnteredEchoed
}

/// What can happen to the entry.
pub type Input {
  /// The player chose this character (message 0x7DD).
  Begin(Character)
  /// The map gave the character's unit.
  Joined(PlayerUnit)
  /// The map would not take the character.
  MapRefused
  /// The client sent message 0xF2: the terrain near the player is loaded.
  TerrainLoaded
  /// The client sent message 0x635, echoing the value of message 0x636.
  ControlEchoed(value: Int)
}

/// A message or an answer that a correct client and map never produce.
pub type Breach {
  /// A begin while a character is already entering.
  BeganTwice
  /// An answer from the map nobody asked for.
  AnswerNobodyAskedFor
  /// Message 0xF2 before the server sent the world messages, or a second one.
  TerrainLoadedOutOfOrder
  /// Message 0x635 before the server sent message 0x636.
  ControlEchoedOutOfOrder
  /// Message 0x635 with a value other than the one message 0x636 carried.
  ControlEchoedWrongValue(value: Int)
  /// A second message 0x635: the server sent one message 0x636.
  ControlEchoedTwice
}

/// What the connection's handler must do, in order.
pub type Effect {
  /// Ask the world's map to join the character; its answer comes back as
  /// `Joined` or `MapRefused`.
  JoinMap(world_id: Int, newcomer: Newcomer)
  /// Send the player a message.
  Send(ServerMessage)
  /// The character cannot enter: the player was sent message 0x162 and may
  /// choose again.
  Failed
  /// Log the breach and close the connection.
  Close(Breach)
}

/// An entry that has not begun.
pub fn new() -> State {
  Waiting
}

/// The state and the effects after an input.
pub fn decide(
  state state: State,
  input input: Input,
  context context: Context,
) -> #(State, List(Effect)) {
  case input {
    Begin(character) -> begin(state:, character:, context:)
    Joined(unit) -> joined(state:, unit:, context:)
    MapRefused -> map_refused(state)
    TerrainLoaded -> terrain_loaded(state)
    ControlEchoed(value) -> control_echoed(state:, value:)
  }
}

fn begin(
  state state: State,
  character character: Character,
  context context: Context,
) -> #(State, List(Effect)) {
  case state {
    Waiting ->
      case context.world_exists(character.place.world_id) {
        True -> #(AwaitingMap(character), [
          JoinMap(
            world_id: character.place.world_id,
            newcomer: character.newcomer(character),
          ),
        ])
        False -> #(Waiting, refused(play_failed))
      }
    AwaitingMap(_) | AwaitingTerrain(_) | Entered -> #(state, [
      Close(BeganTwice),
    ])
    AwaitingTerrainEchoed(_) | EnteredEchoed ->
      todo as "a begin after the echo is a breach"
  }
}

/// What the player is sent when the character cannot enter: message 0x162 with
/// the result, on which the client returns to idle character select, and the
/// end of the entry.
fn refused(result: Int) -> List(Effect) {
  [Send(PlayRefused(PlayCharacterRefused(field_1: result))), Failed]
}

/// The messages the client needs once the character has a unit, in the order
/// its end of loading needs (CheckWorldLoaded 0x1403E8000).
fn joined(
  state state: State,
  unit unit: PlayerUnit,
  context context: Context,
) -> #(State, List(Effect)) {
  case state {
    AwaitingMap(character) -> #(AwaitingTerrain(unit), [
      Send(
        WorldEntered(EnterWorld(
          world_id: character.place.world_id,
          position_x: float32.to_bits(unit.position.x),
          position_y: float32.to_bits(unit.position.y),
          position_z: float32.to_bits(unit.position.z),
          field_5: 0,
          field_6: 0,
        )),
      ),
      Send(UnitCreated(unit_create(unit:, realm_id: context.realm_id))),
      Send(PlayerUnitSet(UnitIsPlayer(unit_id: unit.id, field_2: 0))),
      // opcode.0x636: the client ignores it before 0x19B, so it follows it.
      Send(
        ControlGranted(ClientControlGranted(
          echo_value: control_echo_value,
          reset_movement: 1,
          unit_id: unit.id,
        )),
      ),
      Send(
        MovementIntervalSet(MovementSendInterval(
          field_1: 0,
          field_2: 0,
          field_3: 0,
          interval_milliseconds: movement_send_interval_milliseconds,
        )),
      ),
    ])
    Waiting | AwaitingTerrain(_) | Entered -> #(state, [
      Close(AnswerNobodyAskedFor),
    ])
    AwaitingTerrainEchoed(_) | EnteredEchoed ->
      todo as "a unit from the map after the echo is a breach"
  }
}

/// Message 0x262 for a player's unit: its id, the character's id, name, race,
/// class, gender, path and faction (the unit's faction and base faction are
/// both the character's stored one, a Faction2 id: opcode.0x262), the
/// connection's realm, the position the map gave (one position command), the
/// stand-in health (stat 0 and property 7) and nothing else: no item
/// visuals, and every value the client's code does not give a meaning is 0.
pub fn unit_create(
  unit unit: PlayerUnit,
  realm_id realm_id: Int,
) -> UnitCreatePlayer {
  let health = int.to_float(player_health_stand_in)
  UnitCreatePlayer(
    unit_id: unit.id,
    character_id: unit.character_id,
    realm_id:,
    name: unit.name,
    race_id: unit.race_id,
    class_id: unit.class_id,
    gender: unit.gender,
    field_9: 0,
    field_10: [],
    field_11: "",
    field_12: 0,
    field_13: [],
    field_14: [],
    path: unit.path,
    field_16: 0,
    field_17: 0,
    field_18: 0,
    stats: [UnitStat(stat_id: health_stat_id, value: player_health_stand_in)],
    server_time_estimate_start: 0,
    movement_commands: [
      UnitPositionCommand(
        x: float32.to_bits(unit.position.x),
        y: float32.to_bits(unit.position.y),
        z: float32.to_bits(unit.position.z),
        blends: 0,
      ),
    ],
    properties: [
      UnitProperty(
        property_id: base_health_property_id,
        field_2: float32.to_bits(health),
        value: float32.to_bits(health),
      ),
    ],
    item_visuals: [],
    field_25: 0,
    faction_id: unit.faction_id,
    base_faction_id: unit.faction_id,
    field_28: 0,
    field_29: 0,
    field_31: 0,
    field_33: 0,
    field_34: 0,
    field_36: 0,
    field_37: 0,
    field_38: 0,
    field_39: 0,
    field_40: 0,
  )
}

fn map_refused(state: State) -> #(State, List(Effect)) {
  case state {
    AwaitingMap(_) -> #(Waiting, refused(play_failed_character_in_world))
    Waiting | AwaitingTerrain(_) | Entered -> #(state, [
      Close(AnswerNobodyAskedFor),
    ])
    AwaitingTerrainEchoed(_) | EnteredEchoed ->
      todo as "a refusal from the map after the echo is a breach"
  }
}

fn terrain_loaded(state: State) -> #(State, List(Effect)) {
  case state {
    AwaitingTerrain(_) -> #(Entered, [
      Send(PlayerEntered(PlayerEnteredWorld)),
    ])
    Waiting | AwaitingMap(_) | Entered -> #(state, [
      Close(TerrainLoadedOutOfOrder),
    ])
    AwaitingTerrainEchoed(_) | EnteredEchoed ->
      todo as "0xF2 carries the echo into Entered"
  }
}

/// The echo of message 0x636: accepted with no reply when it carries the value
/// the server sent, a breach before the server sent it or with another value.
fn control_echoed(
  state state: State,
  value value: Int,
) -> #(State, List(Effect)) {
  case state {
    AwaitingTerrain(_) | Entered ->
      case value == control_echo_value {
        True -> #(state, [])
        False -> #(state, [Close(ControlEchoedWrongValue(value))])
      }
    Waiting | AwaitingMap(_) -> #(state, [Close(ControlEchoedOutOfOrder)])
    AwaitingTerrainEchoed(_) | EnteredEchoed ->
      todo as "a second echo is a breach"
  }
}

/// The sentence the log line of a breach holds.
pub fn describe_breach(breach breach: Breach) -> String {
  case breach {
    BeganTwice ->
      "the player chose a character while one was entering the world"
    AnswerNobodyAskedFor -> "the map answered a request nobody made"
    TerrainLoadedOutOfOrder ->
      "the client sent message 0xF2 before the server had sent the world messages, or twice"
    ControlEchoedOutOfOrder ->
      "the client sent message 0x635 before the server had sent message 0x636"
    ControlEchoedWrongValue(value:) ->
      "the client sent message 0x635 with the value "
      <> int.to_string(value)
      <> ", which message 0x636 did not carry"
    ControlEchoedTwice -> todo as "the sentence of a second echo"
  }
}
