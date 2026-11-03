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
//// Join, from the map's side, and what the players in sight are sent:
////
//// ```
//// connection c1                      map                                      shell
////   Join(c1, character, place) ─▶ Asked ─▶ unit id u = next unit id; next + 1
////                                          unit = the character at place as unit u,
////                                                 with the body visuals of its look
////                                          player = (c1, unit, watch w1, sees)
////                                          Watch(w1, Connection(c1))           ─▶ monitors c1
////   ◀─ Joined(0x262's record of unit, run) ◀─ OwnEffect(Reply(caller, Joined(..)))
////   ◀─ Seen(each player in sight)                                             ─▶ sends to c1
////                                          Seen(unit) to each player in sight ─▶ sends to each
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
////                                          Unseen(u) to each player who saw c1 ─▶ sends to each
////   ◀─ Left                    ◀─ OwnEffect(Reply(caller, Left))
//// ```
////
//// A move, a tell with no answer:
////
//// ```
//// connection B                       map                                      connection A (in sight of B)
////   Moved(B, place, commands)  ─▶ Told ─▶ B's unit at place; each pair decided on that final place:
////                                         in sight before and after: MovedUnit(B, time, commands)
////                                                                            to A ─▶ writes 0x638
////                                         into sight: Seen both ways          ─▶ writes 0x262
////                                         out of sight: Unseen both ways      ─▶ writes 0x355
//// ```
////
//// - **The unit** is a game-level value (genesis_prime/world_map/player_unit)
////   the map keeps for as long as the player is in it, standing where the
////   player's last `Moved` put it; the answer's 0x262 record is built from it
////   with the map's realm whenever one is sent. The `place` of a Join is the
////   bounded place the client is told.
//// - **The incarnation** is in every `Joined`, so the joiner watches the run
////   of the map that holds its player, not a later one started after this
////   one ended.
//// - **Unit ids** start at 1 and are never given twice in the map's life,
////   whoever leaves: the client refuses a 0x262 whose unit id it has already
////   seen (opcode.0x262), and a 0x262 with unit id 0 makes the client's
////   controlled unit (0x1403d9760). The 32-bit field's limit is not handled: a
////   map that gives four billion ids crashes, and its players' connections end.
//// - **A second Join from a connection in the map** answers the record built
////   from the unit the map keeps, not from the new Join, sends the joiner a
////   `Seen` of each player it sees again, changes nothing else and logs an
////   error: the connection's rule joins once.
//// - **A Leave** removes the connection's player with its unit and its watch,
////   and is answered `Left`, so the player's connection, which lives on in
////   character select, is not watched by a map it has left; a later Join from
////   it is a new player with a new unit id. A Leave from a connection that is
////   not in the map (its player already gone, or never there) changes nothing,
////   logs an error, and is answered `Left`: the connection's rule leaves once,
////   so the line shows a bug, and the answer lets the connection go on.
//// - **A player's connection ends.** Its watch comes back as `WatchEnded(w)`;
////   the player whose watch is `w` is removed, and its unit with it, as a Leave
////   removes it. A watch that names no player is a bug: logged as an error, and
////   nothing changes.
//// - **A caller that ended before its answer** is dropped by the shell; the
////   player stays until its connection's watch ends, which the joining
////   connection's end then gives.
//// - **The server stopping.** `Stopping` stops the rule at once. The map saves
////   nothing: the connection owns its player's place and saves it
////   (genesis_prime/game/connection).
//// - **Sight** is `genesis_prime/world_map/sight`: one threshold, 1024 units. A
////   pair is in sight or not after each join, move, leave and end; the map keeps
////   each player's `sees`, and the relation is symmetric. A pair that comes into
////   sight is sent `Seen` both ways, a pair that leaves it `Unseen` both ways,
////   and a pair that stays in it a `MovedUnit` of each move of either to the
////   other. A pair already in sight never gets a second `Seen`.
//// - **A move is decided on the place it ends at.** At most one `Seen` or
////   `Unseen` per pair per `Moved`, and the mover is never sent its own
////   `MovedUnit`.
//// - **What a `MovedUnit` carries.** The mover's relayed commands in the order
////   sent with their bits (genesis_prime/message/relayed_movement: kinds 1, 2,
////   8, 11, 14, 24 and 27, never kind 0, the mover's own client clock,
////   movement_command.kind_0). A list of more than 31 is sent as several
////   `MovedUnit` in order, each of at most 31, since 0x638's count is 5 bits
////   (opcode.0x638); a list with nothing in it sends none.
//// - **Server time** is the map's one clock, in milliseconds since the map
////   started, taken from the monotonic time of the input being handled
////   (`server_time`); a unit's `Seen` and each `MovedUnit` read the same clock,
////   so it never goes back before the 32-bit field wraps. The clock is taken
////   mod 2^32 (`server_time`), so a map 49.7 days old counts from 0 again.
//// - **A `Moved` from a connection not in the map** changes nothing and is
////   logged as an error: the connection's rule tells only while joined. A
////   tell in the form of an ask, or an ask in the form of a tell, is a bug and
////   crashes the map.
//// - **Started** sets the map's clock: a map starts empty.
////
//// What happens at each failure point of seeing:
////
//// | Point | What happens |
//// |---|---|
//// | the map dies | every connection in it ends (genesis_prime/game/connection), so no one is left seeing a unit with no owner |
//// | a viewer's connection dies mid-relay | the send to it is dropped; its watch ends, and the map removes it and sends its `Unseen` to the others |
//// | `Moved` reaches the map after that connection's `Leave` | ignored, with an error line |
//// | a tell whose map run the connection's shell cannot find | the tell is dropped with a log line; the connection's watch on the map ends it when the map is gone |
//// | the same pair crosses sight twice in one `Moved` batch | the map decides on the final place: at most one `Seen` or `Unseen` per pair per `Moved` |

import genesis_prime/game/appearance
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/relayed_movement.{type RelayedMovement}
import genesis_prime/message/unit_create_player.{type UnitCreatePlayer}
import genesis_prime/step.{
  type CallerId, type ConnectionId, type Effect, type Now, type ServiceEffect,
  type ServiceInput, type ServiceRule, type ServiceStep, type WatchId, Asked,
  Connection, ConnectionId, Effects, Log, LogError, LogLine, OwnEffect, OwnEvent,
  Reply, Send, Started, Stop, Stopping, Told, Unwatch, Watch, WatchEnded,
  WatchId,
}
import genesis_prime/store.{type Character, CharacterId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/map_id.{type MapId}
import genesis_prime/world_map/player_unit.{type PlayerUnit}
import genesis_prime/world_map/sight
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/set.{type Set}

/// The rule's name: its module path.
const rule_name = "genesis_prime/world_map/map"

/// The clock's 32 bits: the server time of 0x638 and the estimate start of
/// 0x262 are 32 bits wide (opcode.0x638).
const server_time_modulus = 4_294_967_296

/// The most commands one 0x638 holds: its count is 5 bits (opcode.0x638).
const most_commands_in_a_message = 31

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

/// What a connection asks or tells a map.
pub type Message {
  /// Put the character in the map as the connection's player, placed at
  /// `place`, the bounded place the client is told. An ask, answered `Joined`.
  Join(connection: ConnectionId, character: Character, place: Place)
  /// Take the connection's player out of the map, with its unit and the
  /// watch on the connection. An ask, answered `Left`.
  Leave(connection: ConnectionId)
  /// The connection's player now stands at `place` and sent `commands`, the
  /// ones that are relayed, in the order sent with their bits. A tell: the map
  /// answers no one, so a connection's rule goes on at once (8 moves a second
  /// per player). Taken only from a connection that is in the map.
  Moved(connection: ConnectionId, place: Place, commands: List(RelayedMovement))
}

/// What a map answers and sends.
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
  /// player's own 0x262 is, at the unit's current place and with the map's
  /// server time.
  Seen(unit: UnitCreatePlayer)
  /// A send: the unit `unit_id` moved. `commands` are the mover's relayed
  /// ones, in order and at most 31; `server_time_ms` is the map's clock. The
  /// connection writes it as 0x638 with the reset bit 0 and the kept bit 0.
  MovedUnit(unit_id: Int, server_time_ms: Int, commands: List(RelayedMovement))
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
      joined(state:, now: input.now, caller:, connection:, character:, place:)
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
/// `Started`), taken mod 2^32 because the client's fields hold 32 bits
/// (opcode.0x638). A unit's `Seen` and each `MovedUnit` read it, so it only
/// goes forward until the map is 49.7 days old, when it counts from 0 again:
/// the client takes a time sample only when its signed 32-bit difference from
/// the last is at least half the send interval, and ignores one that is not
/// (FitServerTime 0x14079ab90); its fit across the wrap is not read.
fn server_time(state state: State, now now: Now) -> Int {
  { now.monotonic_ms - state.started_ms } % server_time_modulus
}

/// A connection's move: its unit is placed at `place`, and each pair it makes
/// or breaks with a player, by the place it ends at, is told as `Seen` or
/// `Unseen` both ways; each player who sees it and still sees it is sent one
/// `MovedUnit` per 31 commands of `commands`, and none when there are none; the
/// mover is sent none. A connection not in the map is an error line and
/// changes nothing.
fn moved(
  state state: State,
  now now: Now,
  connection connection: ConnectionId,
  place place: Place,
  commands commands: List(RelayedMovement),
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.players, connection) {
    Error(Nil) -> #(
      state,
      Effects([
        log_error(
          state:,
          about: step.About(..step.no_one, connection: Some(connection)),
          text: "the connection moved in the map, but it is not in it",
        ),
      ]),
    )
    Ok(mover) -> {
      let unit = player_unit.moved(mover.unit, place)
      let time = server_time(state:, now:)
      let unit_id = player_unit.unit_id(unit)
      let relays =
        list.sized_chunk(commands, most_commands_in_a_message)
        |> list.map(fn(chunk) {
          MovedUnit(unit_id:, server_time_ms: time, commands: chunk)
        })
      let #(mover_sees, others, effects) =
        list.fold(
          others_of(state:, connection:),
          #(mover.sees, state.players, []),
          fn(held, other) {
            let #(mover_sees, players, effects) = held
            let #(other_connection, player) = other
            let was = set.contains(mover.sees, other_connection)
            let is = sight.sees(place, player_unit.place(player.unit))
            case was, is {
              True, True -> #(
                mover_sees,
                players,
                list.append(
                  effects,
                  list.map(relays, send(to: other_connection, message: _)),
                ),
              )
              False, True -> #(
                set.insert(mover_sees, other_connection),
                dict.insert(
                  players,
                  other_connection,
                  Player(..player, sees: set.insert(player.sees, connection)),
                ),
                list.append(effects, [
                  seen_by(state:, time:, viewer: other_connection, of: unit),
                  seen_by(state:, time:, viewer: connection, of: player.unit),
                ]),
              )
              True, False -> #(
                set.delete(mover_sees, other_connection),
                dict.insert(
                  players,
                  other_connection,
                  Player(..player, sees: set.delete(player.sees, connection)),
                ),
                list.append(effects, [
                  send(to: other_connection, message: Unseen(unit_id:)),
                  send(
                    to: connection,
                    message: Unseen(unit_id: player_unit.unit_id(player.unit)),
                  ),
                ]),
              )
              False, False -> held
            }
          },
        )
      #(
        State(
          ..state,
          players: dict.insert(
            others,
            connection,
            Player(..mover, unit:, sees: mover_sees),
          ),
        ),
        Effects(effects),
      )
    }
  }
}

/// A connection's leave: its player is removed with its unit and its watch,
/// each player who saw it is sent `Unseen`, and `Left` is answered. A
/// connection that is not in the map is an error line and the same answer.
fn left(
  state state: State,
  caller caller: CallerId,
  connection connection: ConnectionId,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.players, connection) {
    Ok(player) -> {
      let #(state, unseen) = without(state:, connection:, player:)
      #(
        state,
        Effects(
          list.flatten([
            [Unwatch(watch: player.watch)],
            unseen,
            [OwnEffect(Reply(caller, Left))],
          ]),
        ),
      )
    }
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
/// the connection is watched. The joiner is then sent a `Seen` of each player
/// in sight, and each of them a `Seen` of the joiner. A connection already in
/// the map is answered with the record built from the unit the map keeps for
/// it, and sent a `Seen` of each player it sees.
fn joined(
  state state: State,
  now now: Now,
  caller caller: CallerId,
  connection connection: ConnectionId,
  character character: Character,
  place place: Place,
) -> #(State, ServiceStep(Outgoing)) {
  let time = server_time(state:, now:)
  case dict.get(state.players, connection) {
    Ok(player) ->
      joined_again(state:, time:, caller:, connection:, character:, player:)
    Error(Nil) ->
      joined_new(state:, time:, caller:, connection:, character:, place:)
  }
}

/// A second join of a connection in the map: an error line, the answer built
/// from the unit the map keeps, and a `Seen` for the joiner of each player it
/// sees.
fn joined_again(
  state state: State,
  time time: Int,
  caller caller: CallerId,
  connection connection: ConnectionId,
  character character: Character,
  player player: Player,
) -> #(State, ServiceStep(Outgoing)) {
  let CharacterId(second_character_id) = character.character_id
  let seen_again =
    others_of(state:, connection:)
    |> list.filter(fn(other) { set.contains(player.sees, other.0) })
    |> list.map(fn(other) {
      seen_by(state:, time:, viewer: connection, of: { other.1 }.unit)
    })
  #(
    state,
    Effects(
      list.flatten([
        [
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
        ],
        seen_again,
      ]),
    ),
  )
}

/// The first join of a connection: the unit is built, kept and answered, the
/// connection watched, and each pair with a player in sight made.
fn joined_new(
  state state: State,
  time time: Int,
  caller caller: CallerId,
  connection connection: ConnectionId,
  character character: Character,
  place place: Place,
) -> #(State, ServiceStep(Outgoing)) {
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
  let in_sight =
    list.filter(others_of(state:, connection:), fn(other) {
      sight.sees(place, player_unit.place({ other.1 }.unit))
    })
  let players =
    list.fold(in_sight, state.players, fn(players, other) {
      dict.insert(
        players,
        other.0,
        Player(..other.1, sees: set.insert({ other.1 }.sees, connection)),
      )
    })
  let sees = set.from_list(list.map(in_sight, fn(other) { other.0 }))
  let pairs =
    list.flat_map(in_sight, fn(other) {
      [
        seen_by(state:, time:, viewer: connection, of: { other.1 }.unit),
        seen_by(state:, time:, viewer: other.0, of: unit),
      ]
    })
  #(
    State(
      ..state,
      players: dict.insert(players, connection, Player(unit:, watch:, sees:)),
      watches: dict.insert(state.watches, watch, connection),
      next_unit_id: unit_id + 1,
      next_watch: state.next_watch + 1,
    ),
    Effects([
      Watch(watch:, target: Connection(connection)),
      OwnEffect(Reply(caller, answer(state:, unit:))),
      ..pairs
    ]),
  )
}

/// The send that makes `viewer` see the unit: `Seen` of it as it stands, at the
/// map's server time `time`.
fn seen_by(
  state state: State,
  time time: Int,
  viewer viewer: ConnectionId,
  of unit: PlayerUnit,
) -> Effect(ServiceEffect(Outgoing)) {
  send(to: viewer, message: Seen(unit: seen(state:, time:, unit:)))
}

/// The answer to a join: the unit as message 0x262's record in the map's
/// realm, and the map's incarnation.
fn answer(state state: State, unit unit: PlayerUnit) -> Outgoing {
  Joined(
    unit: player_unit.create(unit:, realm_id: state.settings.realm_id),
    incarnation: state.settings.incarnation,
  )
}

/// The unit as another player is sent it, at the map's server time `time`.
fn seen(
  state state: State,
  time time: Int,
  unit unit: PlayerUnit,
) -> UnitCreatePlayer {
  player_unit.seen(
    unit:,
    realm_id: state.settings.realm_id,
    server_time_ms: time,
  )
}

/// The end of a player's connection: its player is removed, as a leave removes
/// it, and each player who saw it is sent `Unseen`. A watch that names no
/// player is a bug: an error log line, and nothing changes.
fn ended(
  state state: State,
  watch watch: WatchId,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.watches, watch) {
    Ok(connection) ->
      case dict.get(state.players, connection) {
        Ok(player) -> {
          let #(state, unseen) = without(state:, connection:, player:)
          #(state, Effects(unseen))
        }
        Error(Nil) -> no_player_for_watch(state)
      }
    Error(Nil) -> no_player_for_watch(state)
  }
}

fn no_player_for_watch(state: State) -> #(State, ServiceStep(Outgoing)) {
  #(
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

/// The map with the connection's player and its watch removed, the player
/// out of the `sees` of each player who saw it, and the `Unseen` of its unit
/// sent to each of them, in connection order.
fn without(
  state state: State,
  connection connection: ConnectionId,
  player player: Player,
) -> #(State, List(Effect(ServiceEffect(Outgoing)))) {
  let viewers =
    list.filter(others_of(state:, connection:), fn(other) {
      set.contains(player.sees, other.0)
    })
  let players =
    list.fold(viewers, dict.delete(state.players, connection), fn(players, v) {
      dict.insert(
        players,
        v.0,
        Player(..v.1, sees: set.delete({ v.1 }.sees, connection)),
      )
    })
  #(
    State(..state, players:, watches: dict.delete(state.watches, player.watch)),
    list.map(viewers, fn(viewer) {
      send(
        to: viewer.0,
        message: Unseen(unit_id: player_unit.unit_id(player.unit)),
      )
    }),
  )
}

/// The players other than the connection's, in connection order, so a step's
/// sends come in an order a test can name.
fn others_of(
  state state: State,
  connection connection: ConnectionId,
) -> List(#(ConnectionId, Player)) {
  dict.to_list(state.players)
  |> list.filter(fn(entry) { entry.0 != connection })
  |> list.sort(fn(first, second) {
    let ConnectionId(first) = first.0
    let ConnectionId(second) = second.0
    int.compare(first, second)
  })
}

/// A send to the connection of a player in the map.
fn send(
  to connection: ConnectionId,
  message message: Outgoing,
) -> Effect(ServiceEffect(Outgoing)) {
  OwnEffect(Send(to: Connection(connection), message:))
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
