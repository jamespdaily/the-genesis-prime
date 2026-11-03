//// One map: a world of the client's World table and one instance of it, with
//// the players in it. It builds the unit of each player that joins, with the
//// next unit id and the body of the character's look, keeps it, and forgets
//// the player and its unit when the player's connection ends. It owns who sees
//// whom: two players see each other when they are within
//// `genesis_prime/world_map/sight.range`, and the map tells each player's
//// connection when another player's unit comes into sight, moves and goes.
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
//// Leave, from the map's side, for a player whose connection goes on after its
//// camp (genesis_prime/game/camp):
////
//// ```
//// connection c1                      map                                      shell
////   Leave(c1)                  ─▶ Asked ─▶ player of c1 removed with its unit
////                                          its watch w1 forgotten
////                                          Unwatch(w1)                         ─▶ drops the watch on c1
////   ◀─ Left                    ◀─ OwnEffect(Reply(caller, Left))
//// ```
////
//// Join, as the other players see it, and a move:
////
//// ```
//// connection B                       map                                      connection A (in sight of B)
////   Join(B, character, place)  ─▶ Asked ─▶ unit u_b; B's `sees` = players within the range
////   ◀─ Joined(0x262's record of u_b)                                         (the shell takes it first)
////                                  Send(B, Seen(each player's unit in sight))
////                                  Send(A, Seen(u_b))                      ─▶ writes 0x262
////   Moved(B, place, commands)  ─▶ Told ─▶ u_b at place; the pairs re-decided on the final place:
////     (a tell: no answer)                 Send(A, MovedUnit(u_b, time, commands without kind 0))
////                                                                          ─▶ writes 0x638
////                                         a pair that comes into sight: Seen both ways
////                                         a pair that leaves sight: Unseen both ways
////   Leave(B), or B's watch ends ─▶ Send(each player who saw B, Unseen(u_b)) ─▶ writes 0x355
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
//// - **A Leave** removes the connection's player with its unit and its watch,
////   and is answered `Left`, so the player's connection, which lives on in
////   character select, is not watched by a map it has left; a later Join from
////   it is a new player with a new unit id. A Leave from a connection that is
////   not in the map (its player already gone, or never there) changes nothing,
////   logs an error, and is answered `Left`: the connection's rule leaves once,
////   so the line shows a bug, and the answer lets the connection go on.
//// - **A player's connection ends.** Its watch comes back as `WatchEnded(w)`;
////   the player whose watch is `w` is removed, and its unit with it. A watch
////   that names no player is a bug: logged as an error, and nothing changes.
//// - **A caller that ended before its answer** is dropped by the shell; the
////   player stays until its connection's watch ends, which the joining
////   connection's end then gives.
//// - **The server stopping.** `Stopping` stops the rule at once. The map saves
////   nothing: the connection owns its player's place and saves it
////   (genesis_prime/game/connection); a unit in the map holds the place it
////   joined at, not a position that moves.
//// - **Sight** is `genesis_prime/world_map/sight`: one threshold, 1024 units,
////   decided on the evidence that the client removes no unit by distance
////   (unit.range). A pair is in sight or not after each join, move, leave and
////   end; the map keeps each player's `sees` and sends a `Seen` for a pair that
////   comes into sight, a `MovedUnit` for each move of a player to each player
////   who sees it, and an `Unseen` for a pair that leaves sight.
//// - **A move changes the pairs by the final place.** A `Moved` is decided on
////   the place it ends at: at most one `Seen` or `Unseen` for a pair per `Moved`,
////   and the mover is never sent its own `MovedUnit`.
//// - **Kind 0 is dropped.** A relayed command list holds the mover's commands in
////   order with their bits, without kind 0, the mover's own client clock
////   (movement_command.kind_0). A list of more than 31 commands is sent as
////   several `MovedUnit`, each of at most 31, since 0x638's count is 5 bits
////   (opcode.0x638).
//// - **Server time** is the map's one clock, in milliseconds since the map
////   started, taken from the monotonic time of the input being handled
////   (`server_time`); a unit's `Seen` and each `MovedUnit` of the same map read
////   the same clock, so it never goes back. The 32-bit field wraps after 49
////   days of one map's life: that is not handled.
//// - **Unit ids** are never 0: a 0x262 with unit id 0 makes the client's
////   controlled unit (0x1403d9760), so the map starts at 1.
//// - **A `Moved` from a connection not in the map** changes nothing and is
////   logged as an error: the connection's rule tells only while joined. A
////   tell in the form of an ask, or an ask in the form of a tell, is a bug and
////   crashes the map.
//// - **A viewer's connection that dies mid-relay** drops the send; its watch
////   ends, and the map removes it and sends its `Unseen` to the others.
//// - **Started** sets the map's clock: a map starts empty.
////
//// What happens at each failure point of seeing, each a test:
////
//// | Point | What happens |
//// |---|---|
//// | the map dies | every connection in it ends (genesis_prime/game/connection), so no one is left seeing a unit with no owner |
//// | a viewer's connection dies mid-relay | the send to it is dropped; its watch ends, and the map removes it and sends its `Unseen` to the others |
//// | `Moved` reaches the map after that connection's `Leave` | ignored, with an error line |
//// | the same pair crosses sight twice in one `Moved` batch | the map decides on the final place: at most one `Seen` or `Unseen` per pair per `Moved` |

import genesis_prime/game/appearance
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/movement_command.{type MovementCommand}
import genesis_prime/message/unit_create_player.{type UnitCreatePlayer}
import genesis_prime/step.{
  type CallerId, type ConnectionId, type Effect, type Now, type ServiceEffect,
  type ServiceInput, type ServiceRule, type ServiceStep, type WatchId, Asked,
  Connection, Effects, Log, LogError, LogLine, OwnEffect, OwnEvent, Reply,
  Started, Stop, Stopping, Told, Unwatch, Watch, WatchEnded, WatchId,
}
import genesis_prime/store.{type Character, CharacterId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/map_id.{type MapId}
import genesis_prime/world_map/player_unit.{type PlayerUnit}
import gleam/dict.{type Dict}
import gleam/int
import gleam/option.{Some}
import gleam/set.{type Set}

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
  /// Take the connection's player out of the map, with its unit and the
  /// watch on the connection; answered `Left`.
  Leave(connection: ConnectionId)
  /// The connection's player now stands at `place` and sent `commands`, in
  /// the order sent, with their bits. A tell: the map answers no one, so a
  /// connection's rule goes on at once (8 moves a second per player). Taken
  /// only from a connection that is in the map.
  Moved(connection: ConnectionId, place: Place, commands: List(MovementCommand))
}

/// A map's answers.
pub type Outgoing {
  /// The player is in this run of the map as this unit, which the map keeps;
  /// the joiner watches `Map(map, incarnation)`.
  Joined(unit: UnitCreatePlayer, incarnation: Int)
  /// The connection's player is not in the map any more, whether it was there
  /// or not.
  Left
  /// A send, never an answer: another player's unit has come into sight of the
  /// connection's player. The connection writes it as 0x262, once its player
  /// is in the world. It names the unit by its own id (never 0), built as that
  /// player's own 0x262 is, with the map's server time.
  Seen(unit: UnitCreatePlayer)
  /// A send: the unit `unit_id` moved. `commands` are the mover's, in order,
  /// without kind 0 and at most 31; `server_time_ms` is the map's clock. The
  /// connection writes it as 0x638 with the reset bit 0 and the kept bit 0.
  MovedUnit(unit_id: Int, server_time_ms: Int, commands: List(MovementCommand))
  /// A send: the unit `unit_id` has left the connection's player's sight, by
  /// distance, by leaving the map or by its connection ending. The connection
  /// writes it as 0x355.
  Unseen(unit_id: Int)
}

/// A map's players, their units and what it gives next: the players by their
/// connection, the connection each open watch was opened for, the next unit id
/// and the next watch id, neither of which goes back, and the monotonic time
/// the map started at, which its clock counts from.
pub opaque type State {
  State(
    settings: Settings,
    players: Dict(ConnectionId, Player),
    watches: Dict(WatchId, ConnectionId),
    next_unit_id: Int,
    next_watch: Int,
    started_ms: Int,
  )
}

/// One player in the map: its unit, the watch on its connection, and the
/// players it sees, who see it: the relation is symmetric, so a pair is in one
/// player's `sees` exactly when it is in the other's.
type Player {
  Player(unit: PlayerUnit, watch: WatchId, sees: Set(ConnectionId))
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
    started_ms: 0,
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
    OwnEvent(Started) -> #(
      State(..state, started_ms: input.now.monotonic_ms),
      Effects([]),
    )
    Stopping(..) -> #(state, Effects([Stop]))
    OwnEvent(Asked(caller:, message: Join(connection:, character:, place:))) ->
      joined(state:, caller:, connection:, character:, place:)
    OwnEvent(Asked(caller:, message: Leave(connection:))) ->
      left(state:, caller:, connection:)
    OwnEvent(Told(message: Moved(connection:, place:, commands:))) ->
      moved(state:, now: input.now, connection:, place:, commands:)
    OwnEvent(Asked(message: Moved(..), ..))
    | OwnEvent(Told(message: Join(..)))
    | OwnEvent(Told(message: Leave(..))) ->
      panic as "a map is asked Join and Leave and told Moved only"
    WatchEnded(watch:) -> ended(state:, watch:)
  }
}

/// The map's server time at the time of an input: milliseconds on the map's
/// own clock, which started at 0 when the map started (the monotonic time of
/// `Started`). A unit's `Seen` and each `MovedUnit` read it, so it never goes
/// back.
pub fn server_time(state state: State, now now: Now) -> Int {
  now.monotonic_ms - state.started_ms
}

/// A connection's move: its unit is placed at `place`, and each pair it makes
/// or breaks with a player, by the place it ends at, is told as `Seen` or
/// `Unseen` both ways; each player who sees it and still sees it is sent one
/// `MovedUnit` per 31 commands of `commands` without kind 0; the mover is sent
/// none. A connection not in the map is an error line and changes nothing.
fn moved(
  state state: State,
  now now: Now,
  connection connection: ConnectionId,
  place place: Place,
  commands commands: List(MovementCommand),
) -> #(State, ServiceStep(Outgoing)) {
  todo as "place the unit; decide each pair on the final place; send Seen, MovedUnit and Unseen in order"
}

/// A connection's leave: its player is removed with its unit and its watch,
/// and `Left` is answered. A connection that is not in the map is an error
/// line and the same answer.
fn left(
  state state: State,
  caller caller: CallerId,
  connection connection: ConnectionId,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.players, connection) {
    Ok(player) -> #(
      without(state:, connection:, watch: player.watch),
      Effects([
        Unwatch(watch: player.watch),
        OwnEffect(Reply(caller, Left)),
      ]),
    )
    Error(Nil) -> #(
      state,
      Effects([
        log_error(
          state:,
          about: step.About(..step.no_one, connection: Some(connection)),
          text: "the connection left the map, but it is not in it",
        ),
        OwnEffect(Reply(caller, Left)),
      ]),
    )
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
    Ok(player) -> {
      let CharacterId(second_character_id) = character.character_id
      #(
        state,
        Effects([
          log_error(
            state:,
            about: step.About(
              ..step.no_one,
              connection: Some(connection),
              character_id: Some(second_character_id),
            ),
            text: "the connection joined the map a second time, as character "
              <> int.to_string(second_character_id)
              <> "; it is already unit "
              <> int.to_string(player_unit.unit_id(player.unit))
              <> " of character "
              <> int.to_string(player_unit.character_id(player.unit)),
          ),
          OwnEffect(Reply(caller, answer(state:, unit: player.unit))),
        ]),
      )
    }
    Error(Nil) -> {
      let unit_id = state.next_unit_id
      let watch = WatchId(state.next_watch)
      let unit =
        player_unit.new(
          character:,
          place:,
          unit_id:,
          visuals: appearance.character_body_visuals(
            index: appearance.index(tables: state.settings.tables),
            character:,
          ),
        )
      #(
        State(
          ..state,
          players: dict.insert(
            state.players,
            connection,
            Player(unit:, watch:, sees: set.new()),
          ),
          watches: dict.insert(state.watches, watch, connection),
          next_unit_id: unit_id + 1,
          next_watch: state.next_watch + 1,
        ),
        Effects([
          Watch(watch:, target: Connection(connection)),
          OwnEffect(Reply(caller, answer(state:, unit:))),
        ]),
      )
    }
  }
}

/// The answer to a join: the unit as message 0x262's record in the map's
/// realm, and the map's incarnation.
fn answer(state state: State, unit unit: PlayerUnit) -> Outgoing {
  Joined(
    unit: player_unit.create(unit:, realm_id: state.settings.realm_id),
    incarnation: state.settings.incarnation,
  )
}

/// The end of a player's connection: its player is removed. A watch that names
/// no player is a bug: an error log line, and nothing changes.
fn ended(
  state state: State,
  watch watch: WatchId,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.watches, watch) {
    Ok(connection) -> #(without(state:, connection:, watch:), Effects([]))
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

/// The map with the connection's player and the watch on it removed.
fn without(
  state state: State,
  connection connection: ConnectionId,
  watch watch: WatchId,
) -> State {
  State(
    ..state,
    players: dict.delete(state.players, connection),
    watches: dict.delete(state.watches, watch),
  )
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
