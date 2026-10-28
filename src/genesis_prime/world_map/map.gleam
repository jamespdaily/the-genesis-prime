//// One map: a world of the client's World table and one instance of it, with
//// the players in it. It gives each player that joins a unit id, and forgets
//// the player when the player's connection ends.
////
//// This is the rule of a map's service shell (genesis_prime/service/shell),
//// started without a name by the map supervisor when Maps is first asked for
//// it (genesis_prime/world_map/maps). Its players live only in the process: a
//// restart loses them, and each player's connection, which watches its map,
//// ends (genesis_prime/game/connection).
////
//// Join, from the map's side:
////
//// ```
//// connection c1                 map                                 shell
////   Join(c1, character) ─▶ Asked ─▶ unit id u = next unit id; next + 1
////                                   player = (c1, u, character, watch w1)
////                                   Watch(w1, Connection(c1))      ─▶ monitors c1
////   ◀─ Joined(u)          ◀─ Reply(caller, Joined(u))
//// ```
////
//// - **The incarnation** is in every `Joined`, so the joiner watches the run
////   of the map that holds its player, not a later one started after this
////   one ended.
//// - **Unit ids** start at 1 and are never given twice in the map's life,
////   whoever leaves: the client refuses a 0x262 whose unit id it has already
////   seen (opcode.0x262). The 32-bit field's limit is not handled: a map
////   that gives four billion ids crashes, and its players' connections end.
//// - **A second Join from a connection in the map** answers the unit id it
////   already has, changes nothing and logs an error: the connection's rule
////   joins once.
//// - **A player's connection ends.** Its watch comes back as `WatchEnded(w)`;
////   the player whose watch is `w` is removed. A watch that names no player is
////   a bug: logged as an error, and nothing changes.
//// - **A caller that ended before its answer** is dropped by the shell; the
////   player stays until its connection's watch ends, which the joining
////   connection's end then gives.
//// - **The server stopping.** `Stopping` stops the rule at once; its players
////   are not saved, since no position is read yet.
//// - **Started** does nothing: a map starts empty.

import genesis_prime/step.{
  type CallerId, type ConnectionId, type Input, type Rule, type Step,
  type WatchId, Answered, AnsweredLate, Asked, Connection, Effects, Log,
  LogError, LogLine, Reply, Socket, Started, Stop, Stopping, TimerFired, Watch,
  WatchEnded, WatchId, Woken,
}
import genesis_prime/world_map/map_id.{type MapId}
import gleam/dict.{type Dict}
import gleam/int
import gleam/option.{Some}

/// The rule's name in a recording's header.
pub const rule_name = "genesis_prime/world_map/map"

/// What a map is started with: which map it is, and the incarnation Maps
/// gave this run of it, unique in the node's life.
pub type Settings {
  Settings(map: MapId, incarnation: Int)
}

/// What a connection asks a map.
pub type Message {
  /// Put the character in the map as the connection's player.
  Join(connection: ConnectionId, character_id: Int)
}

/// A map's answers.
pub type Outgoing {
  /// The player is in this run of the map with this unit id; the joiner
  /// watches `Map(map, incarnation)`.
  Joined(unit_id: Int, incarnation: Int)
}

/// A map's players and what it gives next: the players by their connection,
/// the connection each open watch was opened for, the next unit id and the
/// next watch id, neither of which goes back.
pub opaque type State {
  State(
    settings: Settings,
    players: Dict(ConnectionId, Player),
    watches: Dict(WatchId, ConnectionId),
    next_unit_id: Int,
    next_watch: Int,
  )
}

/// One player in the map.
type Player {
  Player(unit_id: Int, character_id: Int, watch: WatchId)
}

/// The map's rule, as its service shell runs it.
pub fn rule(
  map map: MapId,
  incarnation incarnation: Int,
) -> Rule(Settings, State, Message, Nil, Outgoing, Nil) {
  step.Rule(
    name: rule_name,
    settings: Settings(map:, incarnation:),
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
  input input: Input(Message, Nil),
) -> #(State, Step(Outgoing, Nil)) {
  case input.event {
    Started -> #(state, Effects([]))
    Stopping(..) -> #(state, Effects([Stop]))
    Asked(caller:, message: Join(connection:, character_id:)) ->
      joined(state:, caller:, connection:, character_id:)
    WatchEnded(watch:) -> ended(state:, watch:)
    Socket(..) | Woken(..) | TimerFired(..) | Answered(..) | AnsweredLate(..) ->
      panic as "a map takes Started, Asked, WatchEnded and Stopping only; its shell gives no Socket, Woken, TimerFired, Answered or AnsweredLate"
  }
}

/// A connection's join: its player is made with the next unit id, and the
/// connection is watched; a connection already in the map is answered with
/// the unit id it has.
fn joined(
  state state: State,
  caller caller: CallerId,
  connection connection: ConnectionId,
  character_id character_id: Int,
) -> #(State, Step(Outgoing, Nil)) {
  let incarnation = state.settings.incarnation
  case dict.get(state.players, connection) {
    Ok(player) -> #(
      state,
      Effects([
        log_error(
          state:,
          text: "connection "
            <> connection_text(connection)
            <> " joined the map a second time, as character "
            <> int.to_string(character_id)
            <> "; it is already unit "
            <> int.to_string(player.unit_id)
            <> " of character "
            <> int.to_string(player.character_id),
        ),
        Reply(caller, Joined(unit_id: player.unit_id, incarnation:)),
      ]),
    )
    Error(Nil) -> {
      let unit_id = state.next_unit_id
      let watch = WatchId(state.next_watch)
      #(
        State(
          ..state,
          players: dict.insert(
            state.players,
            connection,
            Player(unit_id:, character_id:, watch:),
          ),
          watches: dict.insert(state.watches, watch, connection),
          next_unit_id: unit_id + 1,
          next_watch: state.next_watch + 1,
        ),
        Effects([
          Watch(watch:, target: Connection(connection)),
          Reply(caller, Joined(unit_id:, incarnation:)),
        ]),
      )
    }
  }
}

/// The end of a player's connection: its player is removed. A watch that names
/// no player is a bug: an error log line, and nothing changes.
fn ended(
  state state: State,
  watch watch: WatchId,
) -> #(State, Step(Outgoing, Nil)) {
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
        log_error(state:, text: "a watch ended that names no player of the map"),
      ]),
    )
  }
}

fn log_error(state state: State, text text: String) -> step.Effect(Outgoing) {
  Log(LogLine(
    level: LogError,
    text:,
    about: step.About(..step.no_one, map: Some(state.settings.map)),
  ))
}

fn connection_text(connection: ConnectionId) -> String {
  let step.ConnectionId(number) = connection
  int.to_string(number)
}
