//// One map: a world of the client's World table and one instance of it, with
//// the players in it. It builds the unit of each player that joins, with the
//// next unit id and the body of the character's look, keeps it, and forgets
//// the player and its unit when the player's connection ends.
////
//// This is the rule of a map's service shell (genesis_prime/service/shell),
//// started without a name by the map supervisor when Maps is first asked for
//// it (genesis_prime/world_map/registry). Its players and their units live only
//// in the process: a restart loses them, and each player's connection, which
//// watches its map, ends (genesis_prime/game/connection).
////
//// Join, from the map's side:
////
//// ```
//// connection c1                      map                                      shell
////   Join(c1, character, place) ─▶ Asked ─▶ unit id u = next unit id; next + 1
////                                          unit = the character at place as unit u,
////                                                 with the body visuals of its look
////                                          player = (c1, unit, watch w1)
////                                          Watch(w1, Connection(c1))           ─▶ monitors c1
////   ◀─ Joined(0x262's record of unit, run) ◀─ OwnEffect(Reply(caller, Joined(..)))
//// ```
////
//// - **The unit** is a game-level value (genesis_prime/world_map/player_unit)
////   the map keeps for as long as the player is in it; the answer's 0x262
////   record is built from it with the map's realm whenever one is sent. The
////   `place` of a Join is the bounded place the client is told.
//// - **The incarnation** is in every `Joined`, so the joiner watches the run
////   of the map that holds its player, not a later one started after this
////   one ended.
//// - **Unit ids** start at 1 and are never given twice in the map's life,
////   whoever leaves: the client refuses a 0x262 whose unit id it has already
////   seen (opcode.0x262). The 32-bit field's limit is not handled: a map
////   that gives four billion ids crashes, and its players' connections end.
//// - **A second Join from a connection in the map** answers the record built
////   from the unit the map keeps, not from the new Join, changes nothing and
////   logs an error: the connection's rule joins once.
//// - **A player's connection ends.** Its watch comes back as `WatchEnded(w)`;
////   the player whose watch is `w` is removed, and its unit with it. A watch
////   that names no player is a bug: logged as an error, and nothing changes.
//// - **A caller that ended before its answer** is dropped by the shell; the
////   player stays until its connection's watch ends, which the joining
////   connection's end then gives.
//// - **The server stopping.** `Stopping` stops the rule at once; its players
////   and units are not saved, since the server reads no position.
//// - **Started** does nothing: a map starts empty.

import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/item_visual.{type ItemVisual}
import genesis_prime/message/unit_create_player.{type UnitCreatePlayer}
import genesis_prime/step.{
  type CallerId, type ConnectionId, type Effect, type ServiceEffect,
  type ServiceInput, type ServiceRule, type ServiceStep, type WatchId, Asked,
  Connection, Effects, Log, LogError, LogLine, OwnEffect, OwnEvent, Reply,
  Started, Stop, Stopping, Watch, WatchEnded, WatchId,
}
import genesis_prime/store.{type Character}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/map_id.{type MapId}
import genesis_prime/world_map/player_unit.{type PlayerUnit}
import gleam/dict.{type Dict}
import gleam/option.{Some}

/// The rule's name: its module path.
const rule_name = "genesis_prime/world_map/map"

/// What a map is started with: which map it is, the incarnation Maps gave this
/// run of it, unique in the node's life, the realm its players' units are
/// created in, and the client's game tables, which give a unit's body.
pub type Settings {
  Settings(
    map: MapId,
    incarnation: Int,
    realm_id: Int,
    tables: table_store.Tables,
  )
}

/// What a connection asks a map.
pub type Message {
  /// Put the character in the map as the connection's player, placed at
  /// `place`, the bounded place the client is told.
  Join(connection: ConnectionId, character: Character, place: Place)
}

/// A map's answers.
pub type Outgoing {
  /// The player is in this run of the map as this unit, which the map keeps;
  /// the joiner watches `Map(map, incarnation)`.
  Joined(unit: UnitCreatePlayer, incarnation: Int)
}

/// A map's players, their units and what it gives next: the players by their
/// connection, the connection each open watch was opened for, the next unit id
/// and the next watch id, neither of which goes back.
pub opaque type State {
  State(
    settings: Settings,
    players: Dict(ConnectionId, Player),
    watches: Dict(WatchId, ConnectionId),
    next_unit_id: Int,
    next_watch: Int,
  )
}

/// One player in the map: its unit, and the watch on its connection.
type Player {
  Player(unit: PlayerUnit, watch: WatchId)
}

/// The map's rule, as its service shell runs it.
pub fn rule(
  map map: MapId,
  incarnation incarnation: Int,
  realm_id realm_id: Int,
  tables tables: table_store.Tables,
) -> ServiceRule(Settings, State, Message, Outgoing) {
  step.Rule(
    name: rule_name,
    settings: Settings(map:, incarnation:, realm_id:, tables:),
    new:,
    step:,
  )
}

/// A map's first state: no players; unit id 1 and watch 1 are next.
pub fn new(settings: Settings) -> State {
  State(
    settings:,
    players: dict.new(),
    watches: dict.new(),
    next_unit_id: 1,
    next_watch: 1,
  )
}

/// One input in, the new state and what the shell must do out, as the
/// sequences above give. An input a service's shell never gives is a bug, and
/// crashes the process.
pub fn step(
  state state: State,
  input input: ServiceInput(Message),
) -> #(State, ServiceStep(Outgoing)) {
  case input.event {
    OwnEvent(Started) -> #(state, Effects([]))
    Stopping(..) -> #(state, Effects([Stop]))
    OwnEvent(Asked(caller:, message: Join(connection:, character:, place:))) ->
      joined(state:, caller:, connection:, character:, place:)
    WatchEnded(watch:) -> ended(state:, watch:)
  }
}

/// A connection's join: its player's unit is built with the next unit id and
/// the body of the character's look, kept, and answered as 0x262's record, and
/// the connection is watched; a connection already in the map is answered with
/// the record built from the unit the map keeps for it.
fn joined(
  state state: State,
  caller caller: CallerId,
  connection connection: ConnectionId,
  character character: Character,
  place place: Place,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.players, connection) {
    Ok(_player) -> panic as "built in the next commit"
    Error(Nil) -> {
      let unit_id = state.next_unit_id
      let watch = WatchId(state.next_watch)
      let unit =
        player_unit.new(
          character:,
          place:,
          unit_id:,
          visuals: body_visuals(state:, character:),
        )
      #(
        State(
          ..state,
          players: dict.insert(state.players, connection, Player(unit:, watch:)),
          watches: dict.insert(state.watches, watch, connection),
          next_unit_id: unit_id + 1,
          next_watch: state.next_watch + 1,
        ),
        Effects([
          Watch(watch:, target: Connection(connection)),
          OwnEffect(Reply(
            caller,
            Joined(
              unit: player_unit.create(unit:, realm_id: state.settings.realm_id),
              incarnation: state.settings.incarnation,
            ),
          )),
        ]),
      )
    }
  }
}

/// The body visuals of the character's look, from the map's game tables.
fn body_visuals(
  state _state: State,
  character _character: Character,
) -> List(ItemVisual) {
  panic as "built in the next commit"
}

/// The end of a player's connection: its player is removed. A watch that names
/// no player is a bug: an error log line, and nothing changes.
fn ended(
  state state: State,
  watch watch: WatchId,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.watches, watch) {
    Ok(connection) -> #(
      State(
        ..state,
        players: dict.delete(state.players, connection),
        watches: dict.delete(state.watches, watch),
      ),
      Effects([]),
    )
    Error(Nil) -> #(
      state,
      Effects([
        log_error(
          state:,
          about: step.no_one,
          text: "a watch ended that names no player of the map",
        ),
      ]),
    )
  }
}

/// An error line about the map, and what `about` adds.
fn log_error(
  state state: State,
  about about: step.About,
  text text: String,
) -> Effect(ServiceEffect(Outgoing)) {
  Log(LogLine(
    level: LogError,
    text:,
    about: step.About(..about, map: Some(state.settings.map)),
  ))
}
