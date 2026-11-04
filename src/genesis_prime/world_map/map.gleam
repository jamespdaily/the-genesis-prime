//// One map: a world of the client's World table and one instance of it, with
//// the players and the creatures in it. It builds the unit of each player that
//// joins, with the next unit id and the body of the character's look, keeps it,
//// and forgets the player and its unit when the player's connection ends. It has
//// a creature started at each spawn of its world, with the next unit id, and
//// watches it. It owns who sees whom: a player and another player, or a player
//// and a creature, see each other when they are within
//// `genesis_prime/world_map/sight.range`; two creatures never do. It decides
//// sight and tells it; it sends the client no unit and carries no move. Each
//// player's connection sends everything about its own unit to the connections of
//// the players who see it (genesis_prime/game/connection), and each creature's
//// process everything about its own unit (genesis_prime/world_map/creature), so
//// the work of a move is spread over the movers' processes, and the map's is one
//// sight check per other player and creature.
////
//// This is the rule of a map's service shell (genesis_prime/service/shell),
//// started without a name by the map supervisor when Maps is first asked for
//// it (genesis_prime/world_map/registry). Its players and their units live only
//// in the process: a restart loses them, and each player's connection, which
//// watches its map, ends (genesis_prime/game/connection).
////
//// Join, from the map's side, and what the players in sight are told:
////
//// ```
//// connection c1                      map                                      shell
////   Join(c1, character, place) ─▶ Asked ─▶ unit id u = next unit id; next + 1
////                                          unit = the character at place as unit u,
////                                                 with the body visuals of its look
////                                          player = (c1, unit, watch w1, sees)
////                                          Watch(w1, Connection(c1))           ─▶ monitors c1
////   ◀─ Joined(0x262's record of unit, run, the map's clock origin)
////                                ◀─ OwnEffect(Reply(caller, Joined(..)))
////                                          for each player c2 in sight, in the same step:
////   ◀─ Watched(by: c2)                                                        ─▶ send to c1
////                                          Watched(by: c1) to c2               ─▶ send to c2
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
////                                          to each player c2 who saw c1:
////                                          Unwatched(by: c1)                   ─▶ sends to c2
////   ◀─ Left                    ◀─ OwnEffect(Reply(caller, Left))
//// ```
////
//// A move, a tell with no answer, which decides sight only:
////
//// ```
//// connection B                       map                                      connection A
////   Moved(B, place)            ─▶ Told ─▶ B's unit at place; each pair decided on that place:
////                                         in sight before and after: nothing
////                                         into sight, in one step:
////                                           Watched(by: A) ─▶ B      Watched(by: B) ─▶ A
////                                         out of sight, in one step:
////                                           Unwatched(by: A) ─▶ B    Unwatched(by: B) ─▶ A
//// A connection's end (its watch's DOWN)   ─▶ to each player c2 who saw it: Unwatched(by: it)
////                                           to every player in the map: Gone(its unit)
//// ```
////
//// The map's start, from the map's side, and what happens to a creature that
//// does not run or ends:
////
//// ```
//// supervisor                map                                         shell
////   starts the map ─▶ Started ─▶ for each spawn of the map's world:
////                                 unit id u = next unit id; watch w = next watch
////                                 StartCreature(w, spawn, u, appear_after 0)  ─▶ the creature supervisor starts it
////                                                                                the shell watches Creature(map, run, u) as w
////                                                                             (a start that fails ─▶ CreatureNotStarted(w, reason))
//// CreatureNotStarted(w) ─▶ error line; the spawn stays empty for the run
//// a player joins or moves into 1024 units of a creature:
////                                 Watched(by: c) ─▶ Creature(.., u)           ─▶ the creature sends c its 0x262
//// a player leaves, ends or moves out of sight:
////                                 Unwatched(by: c) ─▶ Creature(.., u)         ─▶ the creature sends c its 0x355 if c saw it
//// WatchEnded(w) of a creature ─▶ Gone(u) to every player in the map            (the creature that ended sent nothing)
////                                 unit id u' = next unit id; watch w' = next watch
////                                 StartCreature(w', spawn, u', appear_after creature_restart_ms)
////                                 Watched(by: c) ─▶ Creature(.., u') for each player c who saw u
//// ```
////
//// What a connection does with them is its own (genesis_prime/game/connection):
//// told `Watched(by: v)`, it sends v its 0x262 at its current place, then its
//// 0x638s as it moves; told `Unwatched(by: v)`, its 0x355; on its camp, its 0x355
//// to every viewer before its `Leave`. A viewer's connection writes only what
//// its client can take, from the units it has shown and the ones the map reported
//// `Gone`.
////
//// - **The unit** is a game-level value (genesis_prime/world_map/player_unit)
////   the map keeps for as long as the player is in it, standing where the
////   player's last `Moved` put it; the answer's 0x262 record is built from it
////   with the map's realm. The `place` of a Join is the bounded place the client
////   is told.
//// - **The incarnation** is in every `Joined`, so the joiner watches the run
////   of the map that holds its player, not a later one started after this
////   one ended.
//// - **Unit ids** start at 1 and are never given twice in the map's life, to a
////   player or a creature, whoever leaves or ends: the client refuses a 0x262
////   whose unit id it has already seen (opcode.0x262), and a 0x262 with unit id 0
////   makes the client's controlled unit (0x1403d9760). They stay below 2^20,
////   since a cast id is built from its caster's unit id in the rest of the 32
////   bits (`0x140561c30`): a map that has given them all crashes, and its
////   players' connections end.
//// - **A second Join from a connection in the map** answers the record built
////   from the unit the map keeps, not from the new Join, sends the joiner a
////   `Watched` for each player it sees again, changes nothing else and logs an
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
////   removes it, and every player in the map is also sent `Gone(unit)`: the
////   connection that ended cannot send its 0x355, so this is the one case the
////   map speaks of a unit, and only after its owner has ended. A watch that
////   names no player is a bug: logged as an error, and nothing changes.
//// - **A caller that ended before its answer** is dropped by the shell; the
////   player stays until its connection's watch ends, which the joining
////   connection's end then gives.
//// - **The server stopping.** `Stopping` stops the rule at once. The map saves
////   nothing: the connection owns its player's place and saves it
////   (genesis_prime/game/connection).
//// - **Sight** is `genesis_prime/world_map/sight`: one threshold, 1024 units. A
////   pair is in sight or not after each join, move, leave and end; the map keeps
////   each player's `sees`, and the relation is symmetric. A pair that comes into
////   sight is sent `Watched` both ways, a pair that leaves it `Unwatched` both
////   ways, in one step, so a connection's viewers are exactly the players whose
////   `Watched` it was sent and not `Unwatched`.
//// - **A move is decided on the place it ends at.** At most one `Watched` or
////   `Unwatched` per pair per `Moved`. The map sends no move: its `Moved` holds
////   the place and nothing else.
//// - **Server time** is the map's one clock, in milliseconds since the map
////   started, taken from the monotonic time of the input being handled
////   (`server_time`) mod 2^32 (the client's fields hold 32 bits, opcode.0x638).
////   `Joined` carries its origin, the monotonic time the map started at, so a
////   connection stamps its unit's 0x262 and 0x638s from the same clock
////   (`server_time`). One owner stamps both in the order it takes its inputs, so
////   for a viewer the times of one unit only go forward. The clock only goes
////   forward until the map is 49.7 days old, when it counts from 0 again: the client takes a sample only
////   when its signed 32-bit difference from the last is at least half the send
////   interval, so the wrap is a step forward in that difference; its fit across
////   the wrap is not read.
//// - **A `Moved` from a connection not in the map** changes nothing and is
////   logged as an error: the connection's rule tells only while joined. A
////   tell in the form of an ask, or an ask in the form of a tell, is a bug and
////   crashes the map.
//// - **Started** sets the map's clock and has a creature started at each spawn
////   of the map's world, in the order of the spawns, each under the next unit id
////   and the next watch id and standing from the start: a map starts with no
////   player.
//// - **A creature** is a process of its own (genesis_prime/world_map/creature):
////   the map keeps its spawn, its watch and the players who see it, and sends it
////   `Watched` and `Unwatched` as it sends a player's connection, so the creature
////   sends the 0x262 and the 0x355 of its own unit itself. A creature never
////   moves, so a move of a player is the only change of sight with it.
//// - **A creature that does not start** (`CreatureNotStarted`) is an error line
////   with the reason; its spawn stays empty for the rest of the run, with no
////   later creature and no one told.
//// - **A creature that ends** (its watch's `WatchEnded`, whatever the reason)
////   is removed, and every player in the map is sent `Gone` of its unit, as for a
////   player's end: the creature that ended sent nothing. Its spawn is started
////   again as a new unit under the next unit id, which shows itself after
////   `creature_restart_ms`, with the players who saw the creature that ended
////   already in its sight, so a creature that crashes in a loop returns at most
////   once in that time.
////
//// Order, in short: every 0x262, 0x638 and 0x355 about a live unit comes from its
//// owner's process, a player's connection or a creature, so for one viewer they
//// are one sender's messages and
//// arrive in the order sent (the BEAM orders signals of one sender to one
//// receiver); the map's `Watched` and `Unwatched` to one owner are one sender's,
//// so the owner's view of its viewers changes in order. The one case two senders
//// speak of a unit is `Gone` after an owner's end, which a viewer filters
//// (genesis_prime/game/connection).
////
//// What happens at each failure point of seeing:
////
//// | Point | What happens |
//// |---|---|
//// | the map dies | every connection in it ends (genesis_prime/game/connection), so no one is left seeing a unit with no owner |
//// | a viewer's connection is gone | an owner's send to it is dropped (the registry finds no process); its watch ends, and the map sends each player who saw it `Unwatched`, so the owner stops sending to it |
//// | an owner's connection ends (a crash, a close, a takeover) | it sends nothing; the map sends each viewer `Unwatched` and every player in the map `Gone`, and a player writes the 0x355 if its client shows the unit (one that stopped seeing the owner just before may never have been sent it, since an end saves the place first) |
//// | an owner's 0x262 lands after the map's `Gone` of it | the viewer drops it: the unit is no ghost |
//// | an owner's 0x638 reaches a viewer before the owner's 0x262 of it, or after its 0x355 | not possible from one sender; one that lands after `Gone` is dropped, since the viewer shows no such unit |
//// | a 0x262, 0x638 or 0x355 for a unit of another run of the map, or another map | dropped by the viewer's connection |
//// | `Moved` reaches the map after that connection's `Leave` | ignored, with an error line |
//// | a connection's `Watched` or `Unwatched` reaches it with no player in the world | dropped: a player that enters again starts with no viewers and is sent a `Watched` for each player in sight by its new join |
//// | the same pair crosses sight twice in one `Moved` batch | the map decides on the final place: at most one `Watched` or `Unwatched` per pair per `Moved` |
//// | a creature does not start | an error line with the supervisor's reason; the spawn stays empty for the run |
//// | a creature crashes while shown | every player is sent `Gone`; the spawn returns after the respawn time as a new unit in sight of the same players |
//// | a creature crashes before it shows itself | the same: the players hold no unit of it, and ignore the `Gone` |
//// | the map run ends | each creature's watch on the run ends and it stops; the players' connections end with the run |
//// | the creature supervisor or the creature registry restarts | every creature and every map ends (genesis_prime/server) |

import genesis_prime/game/appearance
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/unit_create_player.{type UnitCreatePlayer}
import genesis_prime/step.{
  type CallerId, type ConnectionId, type Effect, type ServiceEffect,
  type ServiceInput, type ServiceRule, type ServiceStep, type WatchId, Asked,
  Connection, CreatureNotStarted, CreatureStart, Effects, Log, LogError, LogLine,
  OwnEffect, OwnEvent, Reply, Send, ServiceTimerFired, StartCreature, Started,
  Stop, Stopping, Told, Unwatch, Watch, WatchEnded, WatchId,
}
import genesis_prime/store.{type Character, CharacterId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/map_id.{type MapId}
import genesis_prime/world_map/player_unit.{type PlayerUnit}
import genesis_prime/world_map/sight
import genesis_prime/world_map/spawn.{type Spawn}
import gleam/bool
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

/// The most unit ids a map gives: 2^20 (the cast id of a unit is built from its
/// id, in 2^20 values below the client's 32 bits, `0x140561c30`). Ids 1 up to
/// but not including this one are given.
const unit_id_limit = 1_048_576

/// What a map is started with: which map it is, the incarnation Maps gave this
/// run of it, unique in the node's life, the realm its players' units are
/// created in, the client's game tables, which give a unit's body, the spawns of
/// its world, which it has a creature started at, and how long a spawn whose
/// creature ended stays empty before its next creature shows itself.
pub type Settings {
  Settings(
    map: MapId,
    incarnation: Int,
    realm_id: Int,
    tables: table_store.Tables,
    spawns: List(Spawn),
    creature_restart_ms: Int,
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
  /// The connection's player now stands at `place`. A tell: the map answers no
  /// one, so a connection's rule goes on at once (8 moves a second per player).
  /// The map decides sight from it and sends no move: the connection sends its
  /// own player's moves to the players who see it. Taken only from a connection
  /// that is in the map.
  Moved(connection: ConnectionId, place: Place)
}

/// What a map answers and sends.
pub type Outgoing {
  /// The player is in this run of the map as this unit, which the map keeps;
  /// the joiner watches `Map(map, incarnation)`. `unit` is the player's own
  /// 0x262, which its connection sends the players who see it, at its place and
  /// stamped from the map's clock; `clock_origin_ms` is the monotonic time the
  /// map started at, from which the connection stamps (`server_time`).
  Joined(unit: UnitCreatePlayer, incarnation: Int, clock_origin_ms: Int)
  /// The connection's player is not in the map any more, whether it was there
  /// or not.
  Left
  /// A send, never an answer: the player of connection `by` sees the unit of the
  /// process it is sent to, a player's connection or a creature, so that process
  /// sends `by` its 0x262 at its place and then, for a player's, its moves.
  Watched(by: ConnectionId)
  /// A send: the player of connection `by` no longer sees the unit of the
  /// process it is sent to, by distance, by leaving the map or by its connection
  /// ending, so that process sends `by` its 0x355 and no more moves.
  Unwatched(by: ConnectionId)
  /// A send: the unit `unit_id` has no owner any more, since its connection or
  /// its creature ended, which sends nothing as it ends. It goes to every player
  /// in the map, also one that stopped seeing the unit a moment before. The
  /// connection of a player removes the unit from its client if it shows it, and
  /// shows it no more.
  Gone(unit_id: Int)
}

/// A map's players, its creatures, their units and what it gives next: the
/// players by their connection, the connection each open watch was opened for,
/// the creatures by their unit id, the unit each creature watch was opened for,
/// the next unit id and the next watch id, neither of which goes back, and the
/// monotonic time the map started at, which its clock counts from (`Joined`
/// carries it).
pub opaque type State {
  State(
    settings: Settings,
    players: Dict(ConnectionId, Player),
    watches: Dict(WatchId, ConnectionId),
    creatures: Dict(Int, Standing),
    creature_watches: Dict(WatchId, Int),
    next_unit_id: Int,
    next_watch: Int,
    started_ms: Int,
  )
}

/// A creature standing in the map: its spawn, the watch on its process, and the
/// players who see it. A creature never moves, so it holds no place of its own.
type Standing {
  Standing(spawn: Spawn, watch: WatchId, sees: Set(ConnectionId))
}

/// One player in the map: its unit, the watch on its connection, and the
/// players it sees, who see it: the relation is symmetric, so a pair is in one
/// player's `sees` exactly when it is in the other's.
type Player {
  Player(unit: PlayerUnit, watch: WatchId, sees: Set(ConnectionId))
}

/// Why a player is removed: it left, and its connection said so itself, or its
/// connection ended, and said nothing.
type Removal {
  Camped
  Ended
}

/// The map's rule, as its service shell runs it.
pub fn rule(
  map map: MapId,
  incarnation incarnation: Int,
  realm_id realm_id: Int,
  tables tables: table_store.Tables,
  spawns spawns: List(Spawn),
  creature_restart_ms creature_restart_ms: Int,
) -> ServiceRule(Settings, State, Message, Outgoing) {
  step.Rule(
    name: rule_name,
    settings: Settings(
      map:,
      incarnation:,
      realm_id:,
      tables:,
      spawns:,
      creature_restart_ms:,
    ),
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
    creatures: dict.new(),
    creature_watches: dict.new(),
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
    OwnEvent(Started) ->
      started(State(..state, started_ms: input.now.monotonic_ms))
    Stopping(..) -> #(state, Effects([Stop]))
    OwnEvent(CreatureNotStarted(watch:, reason:)) ->
      creature_not_started(state:, watch:, reason:)
    OwnEvent(ServiceTimerFired(..)) -> panic as "a map starts no timer"
    OwnEvent(Asked(caller:, message: Join(connection:, character:, place:))) ->
      joined(state:, caller:, connection:, character:, place:)
    OwnEvent(Asked(caller:, message: Leave(connection:))) ->
      left(state:, caller:, connection:)
    OwnEvent(Told(message: Moved(connection:, place:))) ->
      moved(state:, connection:, place:)
    OwnEvent(Asked(message: Moved(..), ..))
    | OwnEvent(Told(message: Join(..)))
    | OwnEvent(Told(message: Leave(..))) ->
      panic as "a map is asked Join and Leave and told Moved only"
    WatchEnded(watch:) ->
      case dict.get(state.creature_watches, watch) {
        Ok(unit_id) -> creature_ended(state:, unit_id:)
        Error(Nil) -> ended(state:, watch:)
      }
  }
}

/// A map's start: its clock is set, and each spawn of its world has a creature
/// started at it, in the order of the spawns, with the next unit id and the next
/// watch id, which the shell opens on the creature once it runs. The creatures
/// are standing from the start: they have no players in sight yet.
fn started(state: State) -> #(State, ServiceStep(Outgoing)) {
  let #(state, starts) =
    list.fold(state.settings.spawns, #(state, []), fn(held, spawn) {
      let #(state, starts) = held
      let #(state, start) = start_standing(state:, spawn:, appear_after_ms: 0)
      #(state, [start, ..starts])
    })
  #(state, Effects(list.reverse(starts)))
}

/// The map with a creature standing at the spawn under the next unit id, and the
/// effect that starts it: it shows itself to the players who see it after
/// `appear_after_ms`.
fn start_standing(
  state state: State,
  spawn spawn: Spawn,
  appear_after_ms appear_after_ms: Int,
) -> #(State, Effect(ServiceEffect(Outgoing))) {
  let #(state, unit_id) = take_unit_id(state)
  let watch = WatchId(state.next_watch)
  #(
    State(
      ..state,
      creatures: dict.insert(
        state.creatures,
        unit_id,
        Standing(spawn:, watch:, sees: set.new()),
      ),
      creature_watches: dict.insert(state.creature_watches, watch, unit_id),
      next_watch: state.next_watch + 1,
    ),
    OwnEffect(StartCreature(
      watch:,
      creature: CreatureStart(
        map: state.settings.map,
        incarnation: state.settings.incarnation,
        unit_id:,
        spawn: spawn.id,
        appear_after_ms:,
        clock_origin_ms: state.started_ms,
      ),
    )),
  )
}

/// The next unit id, and the map that has given it. A map that has given
/// `unit_id_limit` ids crashes, and its players' connections end.
fn take_unit_id(state: State) -> #(State, Int) {
  let unit_id = state.next_unit_id
  case unit_id < unit_id_limit {
    True -> #(State(..state, next_unit_id: unit_id + 1), unit_id)
    False -> panic as "a map has given every unit id below 2^20"
  }
}

/// A creature that did not start: an error line, and its spawn stays empty for
/// the rest of the run, with no later creature and no one told.
fn creature_not_started(
  state _state: State,
  watch _watch: WatchId,
  reason _reason: String,
) -> #(State, ServiceStep(Outgoing)) {
  panic as "a creature that did not start leaves its spawn empty"
}

/// A creature that ended: every player in the map is sent `Gone` of its unit,
/// and its spawn is started again as a new unit that shows itself after
/// `creature_restart_ms`, with the players who saw the creature that ended
/// already in its sight.
fn creature_ended(
  state _state: State,
  unit_id _unit_id: Int,
) -> #(State, ServiceStep(Outgoing)) {
  panic as "a creature that ended is gone, and its spawn returns as a new unit"
}

/// The map's server time at monotonic time `monotonic_ms`, for a map started at
/// `origin_ms` on the same clock: milliseconds on the map's own clock, which
/// started at 0 when the map started (the monotonic time of `Started`), taken mod
/// 2^32 because the client's fields hold 32 bits (opcode.0x638). A player's
/// connection stamps its unit's 0x262 and 0x638s with it from the origin
/// `Joined` carries, in the order it takes its inputs, so they share one clock
/// and for a viewer only go forward. It only goes forward until the map is 49.7
/// days old, when it
/// counts from 0 again: the client takes a time sample only when its signed
/// 32-bit difference from the last is at least half the send interval, and
/// ignores one that is not (FitServerTime 0x14079ab90); its fit across the wrap
/// is not read.
pub fn server_time(
  origin_ms origin_ms: Int,
  monotonic_ms monotonic_ms: Int,
) -> Int {
  { monotonic_ms - origin_ms } % server_time_modulus
}

/// A connection's move: its unit is placed at `place`, and each pair it makes
/// or breaks with a player, by the place it ends at, is told: `Watched` both ways
/// for a pair that comes into sight, `Unwatched` both ways for one that leaves
/// it, each in one step. The map sends no unit and no move. A connection not in
/// the map is an error line and changes nothing.
fn moved(
  state state: State,
  connection connection: ConnectionId,
  place place: Place,
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
      let #(mover_sees, others, effects) =
        dict.fold(
          state.players,
          #(mover.sees, state.players, []),
          fn(held, other_connection, player) {
            use <- bool.guard(
              when: other_connection == connection,
              return: held,
            )
            let #(mover_sees, players, effects) = held
            let was = set.contains(mover.sees, other_connection)
            let is = sight.sees(place, player_unit.place(player.unit))
            case was, is {
              False, True -> #(
                set.insert(mover_sees, other_connection),
                dict.insert(
                  players,
                  other_connection,
                  Player(..player, sees: set.insert(player.sees, connection)),
                ),
                list.append(
                  effects,
                  comes_into_sight(
                    newcomer: connection,
                    other: other_connection,
                  ),
                ),
              )
              True, False -> #(
                set.delete(mover_sees, other_connection),
                dict.insert(
                  players,
                  other_connection,
                  Player(..player, sees: set.delete(player.sees, connection)),
                ),
                list.append(
                  effects,
                  goes_out_of_sight(first: connection, second: other_connection),
                ),
              )
              True, True | False, False -> held
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
/// each player who saw it is sent `Unwatched` (the connection sent their clients
/// its 0x355 itself), and `Left` is answered. A connection that is not in the
/// map is an error line and the same answer.
fn left(
  state state: State,
  caller caller: CallerId,
  connection connection: ConnectionId,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.players, connection) {
    Ok(player) -> {
      let #(state, told) = without(state:, connection:, player:, why: Camped)
      #(
        state,
        Effects(
          list.flatten([
            [Unwatch(watch: player.watch)],
            told,
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
/// the connection is watched. The joiner is then sent a `Watched` for each player
/// in sight, and each of them a `Watched` of the joiner. A connection already in
/// the map is answered with the record built from the unit the map keeps for
/// it, and sent a `Watched` for each player it sees.
fn joined(
  state state: State,
  caller caller: CallerId,
  connection connection: ConnectionId,
  character character: Character,
  place place: Place,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.players, connection) {
    Ok(player) ->
      joined_again(state:, caller:, connection:, character:, player:)
    Error(Nil) -> joined_new(state:, caller:, connection:, character:, place:)
  }
}

/// A second join of a connection in the map: an error line, the answer built
/// from the unit the map keeps, and for each player it sees a `Watched` for the
/// joiner and one for that player, which sends the joiner its 0x262 again.
fn joined_again(
  state state: State,
  caller caller: CallerId,
  connection connection: ConnectionId,
  character character: Character,
  player player: Player,
) -> #(State, ServiceStep(Outgoing)) {
  let CharacterId(second_character_id) = character.character_id
  let watched_again =
    others_of(state:, connection:)
    |> list.filter(fn(other) { set.contains(player.sees, other.0) })
    |> list.flat_map(fn(other) {
      [
        watched(to: connection, by: other.0),
        watched(to: other.0, by: connection),
      ]
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
        watched_again,
      ]),
    ),
  )
}

/// The first join of a connection: the unit is built, kept and answered, the
/// connection watched, and each pair with a player in sight made: `Watched`
/// both ways.
fn joined_new(
  state state: State,
  caller caller: CallerId,
  connection connection: ConnectionId,
  character character: Character,
  place place: Place,
) -> #(State, ServiceStep(Outgoing)) {
  let #(state, unit_id) = take_unit_id(state)
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
      comes_into_sight(newcomer: connection, other: other.0)
    })
  #(
    State(
      ..state,
      players: dict.insert(players, connection, Player(unit:, watch:, sees:)),
      watches: dict.insert(state.watches, watch, connection),
      next_watch: state.next_watch + 1,
    ),
    Effects([
      Watch(watch:, target: Connection(connection)),
      OwnEffect(Reply(caller, answer(state:, unit:))),
      ..pairs
    ]),
  )
}

/// The send that tells the connection `to` that the player of connection `by`
/// sees its player.
fn watched(
  to to: ConnectionId,
  by by: ConnectionId,
) -> Effect(ServiceEffect(Outgoing)) {
  send(to:, message: Watched(by:))
}

/// The send that tells the connection `to` that the player of connection `by`
/// no longer sees its player.
fn unwatched(
  to to: ConnectionId,
  by by: ConnectionId,
) -> Effect(ServiceEffect(Outgoing)) {
  send(to:, message: Unwatched(by:))
}

/// The sends of a pair that comes into sight, in one step: each of the two is
/// told the other sees it. A joiner and a mover are the newcomer.
fn comes_into_sight(
  newcomer newcomer: ConnectionId,
  other other: ConnectionId,
) -> List(Effect(ServiceEffect(Outgoing))) {
  [watched(to: other, by: newcomer), watched(to: newcomer, by: other)]
}

/// The sends of a pair that leaves sight, in one step: each of the two is told
/// the other no longer sees it.
fn goes_out_of_sight(
  first first: ConnectionId,
  second second: ConnectionId,
) -> List(Effect(ServiceEffect(Outgoing))) {
  [unwatched(to: second, by: first), unwatched(to: first, by: second)]
}

/// The answer to a join: the unit as message 0x262's record in the map's
/// realm, the map's incarnation and the origin of its clock.
fn answer(state state: State, unit unit: PlayerUnit) -> Outgoing {
  Joined(
    unit: player_unit.create(unit:, realm_id: state.settings.realm_id),
    incarnation: state.settings.incarnation,
    clock_origin_ms: state.started_ms,
  )
}

/// The end of a player's connection: its player is removed, as a leave removes
/// it, and each player who saw it is sent `Unwatched` and `Gone`, since the
/// connection that ended sent their clients nothing. A watch that names no
/// player is a bug: an error log line, and nothing changes.
fn ended(
  state state: State,
  watch watch: WatchId,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.watches, watch) {
    Ok(connection) ->
      case dict.get(state.players, connection) {
        Ok(player) -> {
          let #(state, told) = without(state:, connection:, player:, why: Ended)
          #(state, Effects(told))
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

/// The map with the connection's player and its watch removed, the player out of
/// the `sees` of each player who saw it, and each of them sent `Unwatched` of its
/// connection. When the connection ended, every player in the map is sent `Gone`
/// of its unit, those who saw it as well as those who no longer do: the
/// connection that ended sent nobody a 0x355, and a player that stopped seeing it
/// a moment before may not have taken the notice that would have had it sent
/// (an end saves the place first), so its client may still show the unit. A
/// connection that does not show the unit ignores it.
fn without(
  state state: State,
  connection connection: ConnectionId,
  player player: Player,
  why why: Removal,
) -> #(State, List(Effect(ServiceEffect(Outgoing)))) {
  let others = others_of(state:, connection:)
  let viewers =
    list.filter(others, fn(other) { set.contains(player.sees, other.0) })
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
    case why {
      Camped ->
        list.map(viewers, fn(viewer) { unwatched(to: viewer.0, by: connection) })
      Ended ->
        list.flat_map(others, fn(other) {
          let gone =
            send(
              to: other.0,
              message: Gone(unit_id: player_unit.unit_id(player.unit)),
            )
          case set.contains(player.sees, other.0) {
            True -> [unwatched(to: other.0, by: connection), gone]
            False -> [gone]
          }
        })
    },
  )
}

/// The players other than the connection's, in the order the map's table
/// gives them: a step's sends are in that order, which a test of a few players
/// can name, and no sort is made on each move.
fn others_of(
  state state: State,
  connection connection: ConnectionId,
) -> List(#(ConnectionId, Player)) {
  dict.to_list(state.players)
  |> list.filter(fn(entry) { entry.0 != connection })
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
