//// Entering the world: the client's request to play a character, from the
//// store's read of it, through its map's join, to the messages that put the
//// player in the world. Like character select it is a feature of the game
//// connection's rule (genesis_prime/game/connection): it makes its own asks
//// and takes their answers, and the rule turns its effects into writes, asks
//// and its watch on the map.
////
//// ```
//// 0x07DD play, character id  ─▶ play_requested ─▶ Ask store LoadCharacter(account, id)
//// Loaded(character)          ─▶ loaded         ─▶ Ask map MapId(world, 0): Join(connection, id)
////                                                 (or Refused: the rule hands back to select)
//// Joined(unit id, run)       ─▶ joined         ─▶ Send 0xAD, 0x262, 0x19B, 0x636, 0xF1, 0x61,
////                                                 WatchMap(map, run)
//// ```
////
//// - **The order** is the client's: 0xAD first; 0x262 before 0x19B; 0x19B
////   before 0x636 and 0x61 (0x1403b5ad0, 0x14057a630, 0x1403c74d0). 0xF1
////   sets the flag loading's last stage waits on (0x1403b67e0).
//// - **0xAD** carries the saved world and position, and 0.0 in its last two
////   floats, which neither entry path reads (opcode.0xad.last_floats).
//// - **0x636** carries the player's unit id, the value 0 and the reset bit
////   1 (vector.opcode.0x636.body); the client echoes the value in 0x635.
//// - **0xF1:** Normal difficulty 0, prime level 0, flags 0, for an open world
////   (opcode.0xf1.fields), and the send interval 125 ms, the client's own
////   until 0xF1 arrives (opcode.0xf1); a value below 25 is raised to 25.
//// - **0x19B:** the player's unit id; its second value is never read, 0
////   (opcode.0x19b.second_value).
//// - **Refused.** A character the account does not have, or one with no
////   saved place (world 0, made before create wrote the start place), is not
////   entered: a warning, and the rule hands back to character select, which
////   sends 0x0162 Failed and the list again, as before world entry
////   (opcode.0x162.after_create).
//// - **An answer that is none of the ask out** (the map's while the store is
////   asked, or the reverse) is `Error(Nil)`, as character select gives, and the
////   rule treats it as a bug.
//// - **Instance 0** for every world: open worlds share one instance
////   (genesis_prime/world_map/map_id), so an instanced world has no instance
////   to ask for.

import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/appearance
import genesis_prime/message/client_control_granted.{ClientControlGranted}
import genesis_prime/message/enter_world.{EnterWorld}
import genesis_prime/message/float32
import genesis_prime/message/movement_send_interval.{MovementSendInterval}
import genesis_prime/message/play_character.{type PlayCharacter}
import genesis_prime/message/player_entered_world.{PlayerEnteredWorld}
import genesis_prime/message/unit_create_player
import genesis_prime/message/unit_is_player.{UnitIsPlayer}
import genesis_prime/step.{type ConnectionId}
import genesis_prime/store.{
  type AccountId, type Character, type CharacterId, CharacterId,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/map
import genesis_prime/world_map/map_id.{type MapId, MapId}
import genesis_prime/world_map/player_unit
import gleam/int

/// What world entry asks or sends; the game connection's rule turns each into
/// its own effect.
pub type Effect {
  /// Ask the store; its answer comes back to `loaded`.
  AskStore(request: store.WorldRequest)
  /// Ask the map; its answer comes back to `joined`.
  AskMap(map: MapId, message: map.Message)
  /// Send this message to the client, in the game wrapper under the
  /// connection's cipher.
  Send(frame: Frame)
  /// Watch the run of the map that took the player: its end comes back to the
  /// connection's rule.
  WatchMap(map: MapId, incarnation: Int)
}

/// Where world entry is.
pub opaque type State {
  /// The store is asked for the character.
  Loading(character_id: CharacterId)
  /// The map is asked to take the character.
  Joining(character: Character, map: MapId)
}

/// What the store's read of the character leads to.
pub type Loaded {
  /// The map is asked to take the player.
  Join(state: State, effects: List(Effect))
  /// The character is not entered; character select refuses the play.
  Refused(character_id: Int, warning: String)
}

/// A player in the world: its character, its map, the run of the map that took
/// it, which the rule watches as `Map(map, incarnation)`, and its unit id.
pub type Entered {
  Entered(character_id: CharacterId, map: MapId, incarnation: Int, unit_id: Int)
}

/// The process whose answer world entry waits for, for the log line of an ask
/// that gets none.
pub type Awaiting {
  AwaitingStore
  AwaitingMap
}

/// The movement send interval 0xF1 carries, in milliseconds: 125, the
/// client's own until 0xF1 arrives (opcode.0xf1, 0x140c3a004). The client
/// raises a value below 25 to 25.
const movement_send_interval_ms = 125

/// The instance every world is entered at: open worlds share one.
const open_world_instance = 0

/// The client's 0x07DD, read for this account: the store is asked for the
/// character.
pub fn play_requested(
  account_id account_id: AccountId,
  request request: PlayCharacter,
) -> #(State, List(Effect)) {
  #(Loading(character_id: CharacterId(request.character_id)), [
    AskStore(request: store.LoadCharacter(
      account_id:,
      character_id: CharacterId(request.character_id),
    )),
  ])
}

/// Whose answer is awaited.
pub fn awaiting(state state: State) -> Awaiting {
  case state {
    Loading(..) -> AwaitingStore
    Joining(..) -> AwaitingMap
  }
}

/// The store's answer to `play_requested`'s ask: the map is asked to take the
/// character at its saved world, or the play is refused, for a character the
/// account does not have or one with no saved place. With no read asked for,
/// it is none this module asked for and gives an `Error`.
pub fn loaded(
  state state: State,
  answer answer: store.WorldAnswer,
  connection connection: ConnectionId,
) -> Result(Loaded, Nil) {
  case state {
    Loading(character_id: CharacterId(character_id)) ->
      Ok(case answer {
        store.NotTheAccounts ->
          Refused(
            character_id:,
            warning: "a play of character "
              <> int.to_string(character_id)
              <> ", which the account does not have",
          )
        store.CharacterLoaded(character:) ->
          case character.world_id {
            0 ->
              Refused(
                character_id:,
                warning: "a play of character "
                  <> int.to_string(character_id)
                  <> ", which has no saved place",
              )
            world_id -> {
              let map = MapId(world_id:, instance: open_world_instance)
              Join(state: Joining(character:, map:), effects: [
                AskMap(map:, message: map.Join(connection:, character_id:)),
              ])
            }
          }
      })
    Joining(..) -> Error(Nil)
  }
}

/// The map's answer to `loaded`'s ask: the messages that put the player in
/// the world, in the client's order, then the watch on the run of the map that
/// took it. With no join asked for, it is none this
/// module asked for and gives an `Error`.
pub fn joined(
  state state: State,
  answer answer: map.Outgoing,
  realm_id realm_id: Int,
  tables tables: table_store.Tables,
) -> Result(#(Entered, List(Effect)), Nil) {
  case state {
    Joining(character:, map:) -> {
      let map.Joined(unit_id:, incarnation:) = answer
      Ok(
        #(
          Entered(
            character_id: character.character_id,
            map:,
            incarnation:,
            unit_id:,
          ),
          [
            enter_world(character:),
            player_created(character:, unit_id:, realm_id:, tables:),
            unit_is_player(unit_id:),
            control_granted(unit_id:),
            movement_interval(),
            entered_world(),
            WatchMap(map:, incarnation:),
          ],
        ),
      )
    }
    Loading(..) -> Error(Nil)
  }
}

/// 0xAD with the saved world and position, and 0.0 in the last two floats.
fn enter_world(character character: Character) -> Effect {
  let assert Ok(body) =
    enter_world.encode(EnterWorld(
      world_id: character.world_id,
      position_x: float32.to_bits(character.position_x),
      position_y: float32.to_bits(character.position_y),
      position_z: float32.to_bits(character.position_z),
      field_5: float32.to_bits(0.0),
      field_6: float32.to_bits(0.0),
    ))
    as "a saved world of the table's 15 bits and a position's floats fit the message"
  Send(Frame(message_id: enter_world.message_id, body:))
}

/// 0x262 for the player, with the body visuals of the character list.
fn player_created(
  character character: Character,
  unit_id unit_id: Int,
  realm_id realm_id: Int,
  tables tables: table_store.Tables,
) -> Effect {
  let visuals =
    appearance.body_visuals(
      index: appearance.index(tables:),
      race_id: character.race_id,
      sex: character.gender,
      faction_id: character.faction_id,
      look: character.look,
    )
  let assert Ok(body) =
    unit_create_player.encode(player_unit.create(
      character:,
      unit_id:,
      realm_id:,
      visuals:,
    ))
    as "a stored character's values fit the message's fields: the table's checks hold each"
  Send(Frame(message_id: unit_create_player.message_id, body:))
}

/// 0x19B with the player's unit id and 0, which the client never reads
/// (opcode.0x19b.second_value).
fn unit_is_player(unit_id unit_id: Int) -> Effect {
  let assert Ok(body) =
    unit_is_player.encode(UnitIsPlayer(unit_id:, field_2: 0))
    as "a unit id of 32 bits fits the message"
  Send(Frame(message_id: unit_is_player.message_id, body:))
}

/// 0x636 with the value 0, the reset bit 1 and the player's unit id
/// (vector.opcode.0x636.body).
fn control_granted(unit_id unit_id: Int) -> Effect {
  let assert Ok(body) =
    client_control_granted.encode(ClientControlGranted(
      echo_value: 0,
      reset_movement: 1,
      unit_id:,
    ))
    as "a unit id of 32 bits fits the message"
  Send(Frame(message_id: client_control_granted.message_id, body:))
}

/// 0xF1 with difficulty 0, prime level 0, flags 0 and the client's own
/// movement send interval (opcode.0xf1.fields).
fn movement_interval() -> Effect {
  let assert Ok(body) =
    movement_send_interval.encode(MovementSendInterval(
      world_difficulty: 0,
      world_prime_level: 0,
      world_flags: 0,
      interval_milliseconds: movement_send_interval_ms,
    ))
    as "the message's fields fit their values"
  Send(Frame(message_id: movement_send_interval.message_id, body:))
}

/// 0x61, whose body is empty.
fn entered_world() -> Effect {
  let assert Ok(body) = player_entered_world.encode(PlayerEnteredWorld)
    as "an empty body encodes"
  Send(Frame(message_id: player_entered_world.message_id, body:))
}
