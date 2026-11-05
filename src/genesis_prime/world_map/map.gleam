//// One map: a world of the client's World table and one instance of it, with
//// the players and the creatures in it. It builds the unit of each player that
//// joins, with the next unit id, the body of the character's look and the Novice set it wears, keeps it,
//// and forgets the player and its unit when the player's connection ends. It has
//// a creature started at a spawn of its world when a player first sees the spawn
//// and stopped after no player has seen it for the idle stop, and watches it. It
//// owns who sees whom: a player and another player, or a player
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
////   Join(c1, character, place, stay) ─▶ Asked ─▶ loadout of its class and faction, maximum health at its level
////                                          unit id u = next unit id; next + 1
////                                          unit = the character at place as unit u,
////                                                 with the body visuals of its look, its loadout
////                                                 (the worn set's visuals, the gear's values) and its health
////                                          player = (c1, stay, unit, watch w1, sees)
////                                          Watch(w1, Connection(c1))           ─▶ monitors c1
////   ◀─ Joined(0x262's record of unit, loadout, maximum health, run, the map's clock origin)
////                                ◀─ OwnEffect(Reply(caller, Joined(..)))
////   ◀─ NotJoined(reason)         when the class and faction have no Novice set or the level no Base Health row:
////                                    no unit id is given, no player kept, no watch opened
////                                          for each player c2 in sight, in the same step:
////   ◀─ Noticed(c1's stay, SeenBy(c2, c2's stay))                              ─▶ send to c1
////                                          Noticed(c2's stay, SeenBy(c1, c1's stay)) ─▶ send to c2
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
////                                          UnseenBy(c1), for c2's stay         ─▶ sends to c2
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
////                                           SeenBy(A) ─▶ B           SeenBy(B) ─▶ A
////                                         out of sight, in one step:
////                                           UnseenBy(A) ─▶ B         UnseenBy(B) ─▶ A
//// A connection's end (its watch's DOWN)   ─▶ to each player c2 who saw it: UnseenBy(it)
////                                           to every player in the map: Gone(its unit)
//// (every notice to a player's connection goes as Noticed(its stay, notice))
//// ```
////
//// The map's start, from the map's side, and the creatures a player's sight starts
//// and stops. A spawn that no player sees has no process and no state, only its unit
//// id when it has had one: it is dormant.
////
//// ```
//// supervisor                map                                         shell
////   starts the map ─▶ Started ─▶ the sweep timer TimerId(0), every sweep_ms
////                                 (no creature starts)
//// Join / Moved: the spawns the player sees now (spawn_cell.near, then exact sight)
////   a dormant spawn, seen now:   unit id u = the spawn's own, else next unit id
////                                 life w = next watch
////                                 StartCreature(w, spawn, u, life w, viewers [c]) ─▶ the creature supervisor starts it;
////                                                                       the shell watches Creature(map, run, u, w) as w;
////                                                                       the creature sends c its 0x262 as it starts
////   a live spawn, seen now:      Watched(by: c, c's stay) ─▶ Creature(.., u, w); idle ends
////   a live spawn, no longer:     Unwatched(by: c) ─▶ the creature sends c its 0x355
////                                 the last viewer gone: idle since now
////   a retiring spawn, seen now:  nothing is sent, nothing starts: c is found among the seers at its end
//// the sweep fires ─▶ for each live spawn idle for idle_stop_ms or more:
////                                 Send(Creature(.., u, w), Retire)     the spawn is retiring
////                                 StartServiceTimer(TimerId(0), sweep_ms)
//// WatchEnded(w) of a retiring creature (or one that crashed while retiring)
////                              ─▶ dormant, with u kept; no Gone: the 0x355s went when its viewers did
////                                 players who see the spawn now: StartCreature(u, life w', viewers them)
//// WatchEnded(w) of a live creature (a crash)
////                              ─▶ Gone(u) to every player in the map (the creature that ended sent nothing)
////                                 StartServiceTimer(the spawn's number, its kind's respawn time); u is given up
//// the spawn's timer fires      ─▶ players see the spawn now: a new unit id, a creature as for a dormant spawn
////                                 none: dormant
//// CreatureNotStarted(w)        ─▶ error line; the spawn stays empty for the run
//// ```
////
//// The rings: which ready players stand within a hostile creature's aggro range, so
//// the creature can fight them (genesis_prime/world_map/creature_fight). Decided on
//// each `Moved` beside the spawns in sight:
////
//// ```
//// connection c                  map                                          creature
////   Ready(c) (its first 0xF2) ─▶ c ready; for each Live spawn whose ring holds c,
////                                hostile to c's faction:
////                                  Approached(c, unit, place, seq) ─────────▶ may aggro
////   Moved(c, place, seq)      ─▶ c's seq kept; c ready: the rings it stands in now
////                                (spawn_cell.near, aggro_range, then exact 3D
////                                distance to the spawn's place), hostile spawns only
////                                  entered, Live: Approached(c, unit, place, seq) ─▶
////                                  left, Live:    Withdrew(c) ──────────────────▶
////                                  inside before and after, or outside: nothing
//// a creature starts             each ready player in its ring: Approached, after the start effects
//// ```
////
//// - **A player is not ready until its client's first 0xF2 of the stay**
////   (`opcode.0xf2`), so no creature fights a loading player.
//// - **A ring** is a circle of `aggro_range` about the spawn's place, not the
////   creature's: a creature that runs keeps its spawn's ring and its spawn's sight.
////   The aggro range lies inside sight (genesis_prime/world_map/game_number), so a
////   player in a ring sees the creature, and its creature is Live or about to start.
//// - **Hostile** is a faction level of 0 to 2 toward the player's faction, worked out
////   at load (genesis_prime/world_map/creature_life `Hostile`); a Neutral or Friendly
////   creature has no ring.
//// - **Only Live creatures are told.** A retiring, waiting or failed spawn's ring is
////   kept in `inside` and told when its creature starts.
////
//// What a connection does with them is its own (genesis_prime/game/connection):
//// told `SeenBy(v, stay)`, it sends v its 0x262 at its current place, then its
//// 0x638s as it moves; told `UnseenBy(v)`, its 0x355; on its camp, its 0x355
//// to every viewer before its `Leave`. A viewer's connection writes only what
//// its client can take, from the units it has shown and the ones the map reported
//// `Gone`.
////
//// - **The unit** is a game-level value (genesis_prime/world_map/player_unit)
////   the map keeps for as long as the player is in it, standing where the
////   player's last `Moved` put it; the answer's 0x262 record is built from it
////   with the map's realm, and the answer carries the unit's typed loadout and
////   maximum health, which the player's connection keeps for its casts. The
////   `place` of a Join is the bounded place the client is told.
//// - **The incarnation** is in every `Joined`, so the joiner watches the run
////   of the map that holds its player, not a later one started after this
////   one ended.
//// - **The stay** (genesis_prime/world_map/stay) of each player is the one its
////   Join named, kept with the player. Every notice to a player's connection names
////   that player's stay (`Noticed`), every `SeenBy` and creature's `Watched` names
////   the watcher's, and a creature starts with each first viewer's: the owner
////   names it in every news and fight tell it sends that viewer, so a message
////   meant for a player's earlier stay, which reaches it after a leave and a new
////   join, is dropped (genesis_prime/game/connection).
//// - **Unit ids** start at 1 and are never given to two units at once, whoever
////   leaves or ends: the client refuses a 0x262 whose unit id it already holds
////   (opcode.0x262), and a 0x262 with unit id 0 makes the client's controlled unit
////   (0x1403d9760). A player's id is given once. A spawn has one id for the run,
////   given when its first creature starts and reused after a clean stop, since
////   the client holds no unit of that id then (its 0x355 went with the last viewer)
////   and takes a 0x262 for an id it removed (`death.creature_respawn`,
////   `opcode.0x262`); a creature that crashed gave its id up with its `Gone`, and the
////   spawn's next creature takes a new one. So the ids given are at most the
////   players that joined, the spawns that ever had a creature and the crashes. They
////   stay below 2^20, since a cast id is built from its caster's unit id in the
////   rest of the 32 bits (`0x140561c30`): a map that has given them all crashes,
////   and its players' connections end.
//// - **A second Join from a connection in the map** answers the record built
////   from the unit the map keeps, not from the new Join, keeps the new Join's stay,
////   sends the joiner a `SeenBy` for each player it sees again, changes nothing
////   else and logs an error: the connection's rule joins once.
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
////   sight is sent `SeenBy` both ways, a pair that leaves it `UnseenBy` both
////   ways, in one step, so a connection's viewers are exactly the players whose
////   `SeenBy` it was sent and not `UnseenBy`.
//// - **A move is decided on the place it ends at.** At most one `SeenBy` or
////   `UnseenBy` per pair per `Moved`. The map sends no move: its `Moved` holds
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
//// - **Started** sets the map's clock and starts the sweep timer, `TimerId(0)`
////   (spawn numbers start at 1): a map starts with no player and no creature.
//// - **The spawns a player sees** are the spawns of the map's world within sight
////   (`sight.sees`, exact, 3D) of its place, found through the cell index
////   (`spawn_cell.near`) so a move reads only the spawns near it. The map keeps
////   them for each player (`seen`), and the players who see each live spawn
////   (`viewers`), so the two always agree.
//// - **A creature** is a process of its own (genesis_prime/world_map/creature):
////   the map keeps, for each spawn that is not dormant, whether its creature is
////   live, retiring, waiting for its restart or failed (`SpawnState`), and sends it
////   `Watched`, `Unwatched` and `Retire`, so the creature sends the 0x262 and the
////   0x355 of its own unit itself and decides nothing about its own life. Sight of
////   a creature is decided at its spawn's place, also while it runs (at most the
////   leash range plus its reach off), so a move of a player is the only change of
////   sight with it.
//// - **A creature starts** when its spawn gets its first viewer, with the spawn's
////   unit id, a new life (its watch id) and its first viewers in `CreatureStart`, so
////   it sends their 0x262s as it starts and a burst of starts is followed by no burst
////   of `Watched`; the map's `Reply` of a Join comes first, then the starts. A
////   player's watch is taken before the starts, so no life is the player's watch.
//// - **A creature stops** when no player has seen it for `idle_stop_ms`: the sweep,
////   every `sweep_ms`, sends `Retire` to each live spawn idle that long, so a stop
////   comes between `idle_stop_ms` and `idle_stop_ms + sweep_ms` after the last
////   viewer left. A player that steps back within that time finds the same
////   creature, with its corpse and its health.
//// - **A spawn seen while its creature retires** waits: the creature has been
////   told to stop, so it cannot be shown to a viewer, and nothing starts until its
////   end. Then a creature starts there under the same unit id and a new life, with
////   the players who see the spawn from where they stand then as its first viewers. The registry drops a member when
////   it learns of the member's end, which can be after the map has, so the new
////   creature's address differs by its life: two members of one group would crash
////   the map's `find` (`group_registry`).
//// - **A creature that does not start** (`CreatureNotStarted`) is an error line
////   with the reason; its spawn stays empty for the rest of the run, with no
////   later creature and no one told. The other spawns are not affected.
//// - **A creature that ends** while live (its watch's `WatchEnded`, whatever the
////   reason) is removed, and every player in the map is sent `Gone` of its unit,
////   as for a player's end: the creature that ended sent nothing. Its spawn waits
////   its creature's kind's respawn time on a timer of the spawn's number, and nothing about
////   the spawn is started or told until it fires. Then, when a player sees the
////   spawn from where it stands, a creature is started there as a new unit under
////   the next unit id, and each player in sight is told to it `Watched`; when none
////   does, the spawn is dormant. A creature that crashes in a loop is so started at
////   most once in a respawn time.
//// - **A creature that ends while retiring** is a clean stop, whatever the reason:
////   no client shows the unit.
//// - **A map that ends** ends its creatures: each watches the run.
////
//// Order, in short: every 0x262, 0x638 and 0x355 about a live unit comes from its
//// owner's process, a player's connection or a creature, so for one viewer they
//// are one sender's messages and
//// arrive in the order sent (the BEAM orders signals of one sender to one
//// receiver); the map's `SeenBy` and `UnseenBy` to one owner are one sender's,
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
//// | a 0x262, 0x638 or 0x355 for a unit of another run of the map, or another map | dropped by the viewer's connection: it was sent for another stay |
//// | `Moved` reaches the map after that connection's `Leave` | ignored, with an error line |
//// | a connection's `SeenBy` or `UnseenBy` reaches it with no player in the world, or in a later stay | dropped: a player that enters again starts with no viewers and is sent a `SeenBy` for each player in sight by its new join |
//// | the same pair crosses sight twice in one `Moved` batch | the map decides on the final place: at most one `SeenBy` or `UnseenBy` per pair per `Moved` |
//// | a creature does not start | an error line with the supervisor's reason; the spawn stays empty for the run; the burst's other spawns start |
//// | the map crashes in the middle of a burst of starts | every creature started sees the run end and stops; the players' connections end with the run |
//// | a Leave or an end is queued behind a burst of starts | taken next: `Unwatched` to each of the player's creatures, each stopped after the idle stop |
//// | a spawn is seen while its creature retires | waits; a creature starts at its end, with the same unit id and a new life, if a player still sees it |
//// | a creature crashes while retiring | taken as retired: the spawn is dormant, or a new creature starts if a player sees it |
//// | a creature crashes while live | every player is sent `Gone`; the spawn waits the respawn time, then a new unit is started there if a player sees it, and it is dormant if none does |
//// | the respawn timer fires with no one in sight | the spawn is dormant |
//// | a creature crashes as soon as it is told of a player | the same, once for each respawn time: no creature is started or told anything before the timer fires |
//// | the respawn timer fires after the map ended | not possible: the timer lives in the process |
//// | a joining character's class and faction have no Novice set, or its level has no Base Health row | the join is answered `NotJoined`, with an error line, no unit id given and no player kept: the player's connection tells its client the server failed, and the map does not crash on one character's data |
//// | the map has given every unit id | the map crashes, which ends its run and its players' connections; the next run starts from 1 |
//// | the map run ends | each creature's watch on the run ends and it stops; the players' connections end with the run |
//// | the creature supervisor or the creature registry restarts | every creature and every map ends (genesis_prime/server) |
//// | the sweep timer fires after a restart of the map | not possible: the timer lives in the process, and a restarted map starts its own |
//// | a `Moved` comes before the player's `Ready` | sight is decided; no ring is, and no creature is told |
//// | a `Ready` comes twice in one stay | the second changes nothing (the connection sends one a stay) |
//// | a player in a ring leaves, camps or its connection ends | its creatures are told `Unwatched`, which drops it from their threat lists; no `Withdrew` follows |

import genesis_prime/game/appearance
import genesis_prime/game/loadout.{type Loadout}
import genesis_prime/game/shown
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/unit_create_player.{type UnitCreatePlayer}
import genesis_prime/message/unit_create_static.{type UnitCreateStatic}
import genesis_prime/step.{
  type CallerId, type ConnectionId, type Effect, type ServiceEffect,
  type ServiceInput, type ServiceRule, type ServiceStep, type WatchId, Asked,
  Connection, ConnectionId, CreatureNotStarted, CreatureStart, Effects, Log,
  LogError, LogLine, OwnEffect, OwnEvent, Reply, Send, ServiceTimerFired,
  StartCreature, StartServiceTimer, Started, Stop, Stopping, TimerId, Told,
  Unwatch, Watch, WatchEnded, WatchId,
}
import genesis_prime/store.{type Character, CharacterId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/creature_kind.{type Kinds}
import genesis_prime/world_map/game_number.{type GameNumbers}
import genesis_prime/world_map/map_id.{type MapId}
import genesis_prime/world_map/player_unit.{type PlayerUnit}
import genesis_prime/world_map/sight
import genesis_prime/world_map/spawn.{type WorldSpawns}
import genesis_prime/world_map/spawn_cell
import genesis_prime/world_map/spawn_id.{type SpawnId, SpawnId}
import genesis_prime/world_map/stay.{type Stay}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, Some}
import gleam/order
import gleam/pair
import gleam/result
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

/// The sweep timer: it fires every `sweep_ms` and retires the creatures idle for
/// `idle_stop_ms`. A spawn's restart timer is the spawn's number, which starts at
/// 1, so this id is never one.
pub const sweep_timer = TimerId(0)

/// What a map is started with: which map it is, the incarnation Maps gave this
/// run of it, unique in the node's life, the realm its players' units are
/// created in, the client's game tables, which give a unit's body, the spawns
/// that start in its world (the world's persistent term, read by the map's start and
/// never copied: genesis_prime/content/spawn), how long a spawn whose
/// creature crashed waits before a creature is started there again, how long a
/// creature that no player sees keeps running, and how often the map looks for
/// one. The two times are the server's choice, settings so a test can shorten
/// them: 60 s and 10 s.
pub type Settings {
  Settings(
    map: MapId,
    incarnation: Int,
    realm_id: Int,
    tables: table_store.Tables,
    spawns: WorldSpawns,
    kinds: Kinds,
    numbers: GameNumbers,
    idle_stop_ms: Int,
    sweep_ms: Int,
  )
}

/// What a connection asks or tells a map.
pub type Message {
  /// Put the character in the map as the connection's player, placed at
  /// `place`, the bounded place the client is told, for the connection's stay
  /// `stay`, which every notice to it names. An ask, answered `Joined`.
  Join(connection: ConnectionId, character: Character, place: Place, stay: Stay)
  /// Take the connection's player out of the map, with its unit and the
  /// watch on the connection. An ask, answered `Left`.
  Leave(connection: ConnectionId)
  /// The connection's player now stands at `place`. A tell: the map answers no
  /// one, so a connection's rule goes on at once (8 moves a second per player).
  /// The map decides sight from it and sends no move: the connection sends its
  /// own player's moves to the players who see it. Taken only from a connection
  /// that is in the map. `seq` is the connection's move sequence number, which
  /// grows by one with each accepted 0x637, and which the map passes on with the
  /// place to a creature whose ring the player enters.
  Moved(connection: ConnectionId, place: Place, seq: Int)
  /// The connection's player is ready: its client sent the stay's first 0xF2
  /// (`opcode.0xf2`), so a creature may fight it. `seq` is the connection's move
  /// sequence number then, which counts for the connection's life: a player that
  /// entered again and has not moved is told to creatures with it, not with an
  /// earlier stay's lower one. A tell.
  Ready(connection: ConnectionId, seq: Int)
}

/// Why a join is refused: the data of the one character, which the load's
/// requirements cannot rule out for a character stored with a class, a faction
/// or a level no table holds.
pub type NotJoined {
  /// No Novice set holds the character's class and faction
  /// (genesis_prime/game/loadout).
  NoLoadout(class_id: Int, faction_id: Int)
  /// CreatureLevel has no row for the character's level, so its health is
  /// unknown (`loadout.max_health`).
  NoBaseHealth(level: Int)
}

/// What a map answers and sends.
pub type Outgoing {
  /// The player is in this run of the map as this unit, which the map keeps;
  /// the joiner watches `Map(map, incarnation)`. `unit` is the player's own
  /// 0x262, which its connection sends the players who see it, at its place and
  /// stamped from the map's clock; `clock_origin_ms` is the monotonic time the
  /// map started at, from which the connection stamps (`server_time`).
  Joined(
    unit: UnitCreatePlayer,
    loadout: Loadout,
    max_health: Int,
    incarnation: Int,
    clock_origin_ms: Int,
  )
  /// The character cannot be in the map: nothing was kept, no unit id was
  /// given and no watch was opened. An answer to a join, never a send.
  NotJoined(reason: NotJoined)
  /// The connection's player is not in the map any more, whether it was there
  /// or not.
  Left
  /// A send to a player's connection, never an answer: the notice, for the
  /// player's stay `stay`.
  Noticed(stay: Stay, notice: Notice)
  /// A send to a creature: the player of connection `by`, in its stay `stay`,
  /// sees it, so it sends `by` its 0x262, naming `stay`.
  Watched(by: ConnectionId, stay: Stay)
  /// A send to a creature: the player of connection `by` no longer sees it, by
  /// distance, by leaving the map or by its connection ending, so it sends `by`
  /// its 0x355.
  Unwatched(by: ConnectionId)
  /// A send to a creature, never to a connection: no player has seen it for the
  /// idle stop, so it ends (genesis_prime/world_map/creature).
  Retire
  /// A send to a creature: the ready player of connection `by`, its unit
  /// `unit_id`, entered the creature's ring at `place`, its move `seq`; or stood
  /// in it when it became ready or when the creature started.
  Approached(by: ConnectionId, unit_id: Int, place: Place, seq: Int, stay: Stay)
  /// A send to a creature: the player of connection `by` left its ring.
  Withdrew(by: ConnectionId)
}

/// What a map tells the connection of a player in it about who sees whom, for
/// that player's stay (`Noticed`).
pub type Notice {
  /// The player of connection `by`, in its stay `stay`, sees this connection's
  /// player, so this connection sends `by` its 0x262 at its place and then its
  /// moves, each for `stay`.
  SeenBy(by: ConnectionId, stay: Stay)
  /// The player of connection `by` no longer sees this connection's player, by
  /// distance, by leaving the map or by its connection ending, so this connection
  /// sends `by` its 0x355 and no more moves.
  UnseenBy(by: ConnectionId)
  /// The unit `unit_id` has no owner any more, since its connection or its
  /// creature ended, which sends nothing as it ends. It goes to every player in
  /// the map, also one that stopped seeing the unit a moment before. The
  /// connection of a player removes the unit from its client if it shows it, and
  /// shows it no more.
  Gone(unit_id: Int)
  /// The player sees these static objects now, each as its 0x262 under the unit
  /// id the map gave its spawn for the run, in spawn order: the connection writes
  /// each one its client does not show (genesis_prime/world_map/static_object).
  ObjectsSeen(units: List(UnitCreateStatic))
  /// The player no longer sees the static objects of these unit ids: the
  /// connection writes a 0x355 for each one its client shows.
  ObjectsUnseen(unit_ids: List(Int))
}

/// A map's players, its spawns that have a creature or a failure, the spawns'
/// unit ids and what it gives next: the players by their connection, the
/// connection each open watch was opened for, the state of each spawn that is not
/// dormant, the spawn each creature watch was opened for, the unit id each spawn
/// has had this run, the next unit id and the next watch id, neither of which goes
/// back, and the monotonic time the map started at, which its clock counts from
/// (`Joined` carries it). A dormant spawn is a spawn with no entry in `spawns`.
pub opaque type State {
  State(
    settings: Settings,
    players: Dict(ConnectionId, Player),
    watches: Dict(WatchId, ConnectionId),
    spawns: Dict(SpawnId, SpawnState),
    creature_watches: Dict(WatchId, SpawnId),
    unit_of_spawn: Dict(SpawnId, Int),
    next_unit_id: Int,
    next_watch: Int,
    started_ms: Int,
  )
}

/// What a spawn that is not dormant has: a creature running, a creature told to
/// stop, a wait for its restart, or a start that failed. A dormant spawn has
/// none of these and no entry in the map's state.
pub type SpawnState {
  /// A creature runs as `unit_id` under `life` (its watch's number). `viewers` are
  /// the players who see it, and `idle_since_ms` is the monotonic time the last
  /// one stopped seeing it, `None` while any does: the sweep retires it when
  /// `idle_stop_ms` has passed.
  Live(
    unit_id: Int,
    life: Int,
    viewers: Set(ConnectionId),
    idle_since_ms: Option(Int),
  )
  /// The creature was told `Retire` and has not ended. The players who see the
  /// spawn meanwhile are the players whose `seen` holds it, found when it ends.
  Retiring(unit_id: Int, life: Int)
  /// The creature crashed: the unit was sent `Gone`, and the spawn's restart
  /// timer runs.
  WaitingForRestart
  /// The creature did not start: the spawn stays empty for the run.
  Failed
}

/// One player in the map: the stay its connection's Join named, its unit, the
/// watch on its connection, the players
/// it sees, who see it (the relation is symmetric, so a pair is in one
/// player's `sees` exactly when it is in the other's), the spawns of the
/// map's world it sees, whatever their creature's state (a spawn is in `seen`
/// exactly when it is within sight of the player's place), the static objects
/// it sees (`objects`, likewise), whether it is ready,
/// the move sequence number of its place, and the hostile spawns whose ring it
/// stands in, empty until it is ready.
type Player {
  Player(
    stay: Stay,
    unit: PlayerUnit,
    watch: WatchId,
    sees: Set(ConnectionId),
    seen: Set(SpawnId),
    objects: Set(SpawnId),
    readiness: Readiness,
    seq: Int,
    inside: Set(SpawnId),
  )
}

/// Whether a player's client has finished loading the world: a creature fights
/// only a ready player.
type Readiness {
  /// Its client has sent no 0xF2 in this stay.
  StillLoading
  /// Its client sent the stay's first 0xF2.
  Loaded
}

/// Why a player is removed: it left, and its connection said so itself, or its
/// connection ended, and said nothing.
type Removal {
  Camped
  Ended
}

/// The state of the spawn, or `Error(Nil)` for a dormant one.
pub fn spawn_state(
  state state: State,
  spawn spawn: SpawnId,
) -> Result(SpawnState, Nil) {
  dict.get(state.spawns, spawn)
}

/// The map's rule, as its service shell runs it.
pub fn rule(
  map map: MapId,
  incarnation incarnation: Int,
  realm_id realm_id: Int,
  tables tables: table_store.Tables,
  spawns spawns: WorldSpawns,
  kinds kinds: Kinds,
  numbers numbers: GameNumbers,
  idle_stop_ms idle_stop_ms: Int,
  sweep_ms sweep_ms: Int,
) -> ServiceRule(Settings, State, Message, Outgoing) {
  step.Rule(
    name: rule_name,
    settings: Settings(
      map:,
      incarnation:,
      realm_id:,
      tables:,
      spawns:,
      kinds:,
      numbers:,
      idle_stop_ms:,
      sweep_ms:,
    ),
    new:,
    step:,
  )
}

/// A map's first state: no players and every spawn dormant; unit id 1 and watch
/// 1 are next.
pub fn new(settings: Settings) -> State {
  State(
    settings:,
    players: dict.new(),
    watches: dict.new(),
    spawns: dict.new(),
    creature_watches: dict.new(),
    unit_of_spawn: dict.new(),
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
    OwnEvent(ServiceTimerFired(timer:)) ->
      case timer == sweep_timer {
        True -> swept(state:, now_ms: input.now.monotonic_ms)
        False -> {
          let TimerId(number) = timer
          restart_due(state:, spawn: SpawnId(number))
        }
      }
    OwnEvent(Asked(
      caller:,
      message: Join(connection:, character:, place:, stay:),
    )) ->
      joined(
        state:,
        caller:,
        connection:,
        character:,
        place:,
        stay:,
        now_ms: input.now.monotonic_ms,
      )
    OwnEvent(Asked(caller:, message: Leave(connection:))) ->
      left(state:, caller:, connection:, now_ms: input.now.monotonic_ms)
    OwnEvent(Told(message: Moved(connection:, place:, seq:))) ->
      moved(state:, connection:, place:, seq:, now_ms: input.now.monotonic_ms)
    OwnEvent(Told(message: Ready(connection:, seq:))) ->
      ready(state:, connection:, seq:)
    OwnEvent(Asked(message: Moved(..), ..))
    | OwnEvent(Asked(message: Ready(..), ..))
    | OwnEvent(Told(message: Join(..)))
    | OwnEvent(Told(message: Leave(..))) ->
      panic as "a map is asked Join and Leave and told Moved and Ready only"
    WatchEnded(watch:) ->
      case dict.get(state.creature_watches, watch) {
        Ok(spawn) -> creature_ended(state:, spawn:, watch:)
        Error(Nil) -> ended(state:, watch:, now_ms: input.now.monotonic_ms)
      }
  }
}

/// A map's start: its clock is set and the sweep timer starts. No creature
/// starts: a spawn gets one when a player first sees it.
fn started(state: State) -> #(State, ServiceStep(Outgoing)) {
  #(
    state,
    Effects([
      OwnEffect(StartServiceTimer(
        timer: sweep_timer,
        after_ms: state.settings.sweep_ms,
      )),
    ]),
  )
}

/// The next unit id, and the map that has given it. Ids start at 1 and go up to
/// `unit_id_limit` less one, about a million, one for each player that joins,
/// each spawn that first has a creature and each creature that crashed and is
/// replaced. A map that has given them all crashes, which ends its run and its
/// players' connections; the next run starts from 1. A creature that crashes in
/// a loop takes one id for each respawn time, so the ids last a run for about
/// two years of them.
fn take_unit_id(state: State) -> #(State, Int) {
  let unit_id = state.next_unit_id
  case unit_id < unit_id_limit {
    True -> #(State(..state, next_unit_id: unit_id + 1), unit_id)
    False -> panic as "a map has given every unit id below 2^20"
  }
}

/// The unit id of the ghost of the player whose unit is `unit_id`: `unit_id_limit`
/// plus the player's id, so it is never an id a map gives (all are below the
/// limit), each player has one, and no map is asked for it. The server's choice:
/// the client takes any 32-bit id for a ghost's 0x262
/// (`0x140096970`), and a ghost never casts, so its id need not fit the cast id's
/// 2^20 (`0x140561c30`).
pub fn ghost_unit_id(unit_id unit_id: Int) -> Int {
  unit_id_limit + unit_id
}

/// A creature that did not start: an error line, and its spawn stays empty for
/// the rest of the run, with no later creature and no one told.
fn creature_not_started(
  state state: State,
  watch watch: WatchId,
  reason reason: String,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.creature_watches, watch) {
    Ok(spawn) -> {
      let SpawnId(number) = spawn
      #(
        State(
          ..state,
          spawns: dict.insert(state.spawns, spawn, Failed),
          creature_watches: dict.delete(state.creature_watches, watch),
        ),
        Effects([
          log_error(
            state:,
            about: step.no_one,
            text: "the creature of spawn "
              <> int.to_string(number)
              <> " did not start, so its spawn stays empty: "
              <> reason,
          ),
        ]),
      )
    }
    Error(Nil) -> panic as "a creature that did not start was never started"
  }
}

/// The sweep: every live spawn idle for `idle_stop_ms` or more is sent `Retire`
/// and becomes retiring, in the order of the spawns, and the sweep timer starts
/// again.
fn swept(
  state state: State,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  let idle =
    dict.to_list(state.spawns)
    |> list.filter_map(fn(entry) {
      case entry.1 {
        Live(unit_id:, life:, idle_since_ms: Some(since_ms), ..)
          if now_ms - since_ms >= state.settings.idle_stop_ms
        -> Ok(#(entry.0, unit_id, life))
        Live(..) | Retiring(..) | WaitingForRestart | Failed -> Error(Nil)
      }
    })
    |> list.sort(fn(first, second) { compare_spawns(first.0, second.0) })
  let spawns =
    list.fold(idle, state.spawns, fn(spawns, retired) {
      dict.insert(
        spawns,
        retired.0,
        Retiring(unit_id: retired.1, life: retired.2),
      )
    })
  #(
    State(..state, spawns:),
    Effects(
      list.append(
        list.map(idle, fn(retired) {
          tell_creature(
            state:,
            unit_id: retired.1,
            life: retired.2,
            message: Retire,
          )
        }),
        [
          OwnEffect(StartServiceTimer(
            timer: sweep_timer,
            after_ms: state.settings.sweep_ms,
          )),
        ],
      ),
    ),
  )
}

/// A creature's watch ended. A live creature crashed: every player is sent
/// `Gone` of its unit, the unit id is given up, and the spawn's restart timer
/// starts. A retiring one ended cleanly, whatever the reason: the spawn is
/// dormant with its unit id kept, or, when a player sees it now, a creature
/// starts at once under the same unit id and a new life, with those players as
/// its first viewers.
fn creature_ended(
  state state: State,
  spawn spawn: SpawnId,
  watch watch: WatchId,
) -> #(State, ServiceStep(Outgoing)) {
  let state =
    State(..state, creature_watches: dict.delete(state.creature_watches, watch))
  case dict.get(state.spawns, spawn) {
    Ok(Live(unit_id:, ..)) -> {
      let SpawnId(number) = spawn
      let gone =
        list.map(players_in_order(state), fn(player) {
          notify(to: player, notice: Gone(unit_id:))
        })
      #(
        State(
          ..state,
          spawns: dict.insert(state.spawns, spawn, WaitingForRestart),
          unit_of_spawn: dict.delete(state.unit_of_spawn, spawn),
        ),
        Effects(
          list.append(gone, [
            OwnEffect(StartServiceTimer(
              timer: TimerId(number),
              after_ms: restart_ms(state:, spawn:),
            )),
          ]),
        ),
      )
    }
    Ok(Retiring(..)) -> started_for_those_who_see(state:, spawn:)
    Ok(WaitingForRestart) | Ok(Failed) | Error(Nil) ->
      panic as "a watch ended for a creature the map holds no live or retiring spawn for"
  }
}

/// How long a spawn whose creature crashed waits before a creature starts there
/// again: the respawn time of its creature's kind (genesis_prime/world_map/creature_kind).
fn restart_ms(state state: State, spawn spawn: SpawnId) -> Int {
  case dict.get(state.settings.spawns.by_id, spawn) {
    Ok(found) ->
      creature_kind.kind_of(
        kinds: state.settings.kinds,
        creature2_id: { found.creature_id }.value,
      ).respawn_ms
    Error(Nil) ->
      panic as "a creature crashed for a spawn the map's world does not hold"
  }
}

/// A spawn's restart timer fired: when a player sees the spawn from where it
/// stands, a creature starts there under the next unit id with those players as
/// its first viewers; when none does, the spawn is dormant.
fn restart_due(
  state state: State,
  spawn spawn: SpawnId,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.spawns, spawn) {
    Ok(WaitingForRestart) -> started_for_those_who_see(state:, spawn:)
    Ok(Live(..)) | Ok(Retiring(..)) | Ok(Failed) | Error(Nil) ->
      panic as "a restart timer fired for a spawn that does not wait for one"
  }
}

/// The spawn is dormant when no player sees it from where it stands, and
/// otherwise a creature starts there with those players as its first viewers.
fn started_for_those_who_see(
  state state: State,
  spawn spawn: SpawnId,
) -> #(State, ServiceStep(Outgoing)) {
  case players_seeing(state:, spawn:) {
    [] -> #(
      State(..state, spawns: dict.delete(state.spawns, spawn)),
      Effects([]),
    )
    viewers -> {
      let #(state, start) = start_creature(state:, spawn:, viewers:)
      #(state, Effects([start, ..approaches_at_start(state:, spawn:)]))
    }
  }
}

/// `Approached` to the creature just started at the spawn from each ready player
/// that stands in its ring, in the order of their connections: the ring was kept
/// while no creature stood there to tell.
fn approaches_at_start(
  state state: State,
  spawn spawn: SpawnId,
) -> List(Effect(ServiceEffect(Outgoing))) {
  case dict.get(state.spawns, spawn) {
    Ok(Live(unit_id:, life:, ..)) ->
      players_in_order(state)
      |> list.filter(fn(player) {
        { player.1 }.readiness == Loaded
        && set.contains({ player.1 }.inside, spawn)
      })
      |> list.map(fn(player) {
        tell_creature(
          state:,
          unit_id:,
          life:,
          message: approached(connection: player.0, player: player.1),
        )
      })
    Ok(Retiring(..)) | Ok(WaitingForRestart) | Ok(Failed) | Error(Nil) -> []
  }
}

/// The `Approached` of a player: its unit, its place, its move's sequence
/// number and its stay.
fn approached(
  connection connection: ConnectionId,
  player player: Player,
) -> Outgoing {
  Approached(
    by: connection,
    unit_id: player_unit.unit_id(player.unit),
    place: player_unit.place(player.unit),
    seq: player.seq,
    stay: player.stay,
  )
}

/// The connections of the players who see the spawn from where they stand, each
/// with its player's stay, in the order of their numbers.
fn players_seeing(
  state state: State,
  spawn spawn: SpawnId,
) -> List(#(ConnectionId, Stay)) {
  players_in_order(state)
  |> list.filter(fn(player) { set.contains({ player.1 }.seen, spawn) })
  |> list.map(fn(player) { #(player.0, { player.1 }.stay) })
}

/// The connections of a set in the order of their numbers, so what is sent to each is
/// the same on every run.
pub fn sorted_connections(
  connections: Set(ConnectionId),
) -> List(ConnectionId) {
  list.sort(set.to_list(connections), fn(first, second) {
    compare_connections(first:, second:)
  })
}

/// The entries of a dict keyed by connection in the order of the connections'
/// numbers, so what is sent to each is the same on every run.
pub fn sorted_by_connection(
  entries: Dict(ConnectionId, value),
) -> List(#(ConnectionId, value)) {
  dict.to_list(entries)
  |> list.sort(fn(first, second) {
    compare_connections(first: first.0, second: second.0)
  })
}

/// The order of two connections by their numbers.
pub fn compare_connections(
  first first: ConnectionId,
  second second: ConnectionId,
) -> order.Order {
  let ConnectionId(first) = first
  let ConnectionId(second) = second
  int.compare(first, second)
}

/// The players by their connection's number.
fn players_in_order(state: State) -> List(#(ConnectionId, Player)) {
  sorted_by_connection(state.players)
}

fn compare_spawns(first: SpawnId, second: SpawnId) -> order.Order {
  let SpawnId(first) = first
  let SpawnId(second) = second
  int.compare(first, second)
}

/// Starts a creature at the spawn with these players as its first viewers, each
/// by its connection and its stay: under the spawn's unit id for the run, taken
/// from the counter when the spawn has had none (the first creature there, or the
/// first after a crash gave its id up), and a new life, the number of the watch it
/// is started under. The spawn is then live with those viewers.
fn start_creature(
  state state: State,
  spawn spawn: SpawnId,
  viewers viewers: List(#(ConnectionId, Stay)),
) -> #(State, Effect(ServiceEffect(Outgoing))) {
  let #(state, unit_id) = case dict.get(state.unit_of_spawn, spawn) {
    Ok(unit_id) -> #(state, unit_id)
    Error(Nil) -> {
      let #(state, unit_id) = take_unit_id(state)
      #(
        State(
          ..state,
          unit_of_spawn: dict.insert(state.unit_of_spawn, spawn, unit_id),
        ),
        unit_id,
      )
    }
  }
  let watch = WatchId(state.next_watch)
  let WatchId(life) = watch
  #(
    State(
      ..state,
      spawns: dict.insert(
        state.spawns,
        spawn,
        Live(
          unit_id:,
          life:,
          viewers: set.from_list(list.map(viewers, pair.first)),
          idle_since_ms: option.None,
        ),
      ),
      creature_watches: dict.insert(state.creature_watches, watch, spawn),
      next_watch: state.next_watch + 1,
    ),
    OwnEffect(StartCreature(
      watch:,
      creature: CreatureStart(
        map: state.settings.map,
        incarnation: state.settings.incarnation,
        unit_id:,
        life:,
        spawn_id: spawn,
        clock_origin_ms: state.started_ms,
        viewers:,
      ),
    )),
  )
}

/// The spawns of the map's world the player at `place` sees: those the cell
/// index finds near it that are within sight, exactly.
fn spawns_in_sight(state state: State, place place: Place) -> Set(SpawnId) {
  let spawns = state.settings.spawns
  spawn_cell.near(
    cells: spawns.cells,
    x: start_place.x(place),
    z: start_place.z(place),
    range: sight.range,
  )
  |> list.filter(fn(id) {
    dict.get(spawns.by_id, id)
    |> result.map(fn(spawn) { sight.sees(place, spawn.place) })
    |> result.unwrap(False)
  })
  |> set.from_list
}

/// The state and effects of the player of `connection` coming to see the spawns
/// `now` after it saw `was`, at monotonic time `now_ms`: a dormant spawn it now
/// sees starts a creature with the player as its first viewer (the creature
/// sends the 0x262 as it starts), a live one is told `Watched`, and a retiring,
/// waiting or failed one is not told, for the player is found among its viewers
/// when it needs them; for each spawn it no longer sees, a live creature is told
/// `Unwatched` and the spawn is idle from `now_ms` when the player was its last
/// viewer. The starts come first, in the order of the spawns, then the sends. A
/// spawn the player saw and sees is not told. `stay` is the player's, which a
/// creature names in everything it sends the player.
fn spawns_decided(
  state state: State,
  connection connection: ConnectionId,
  stay stay: Stay,
  was was: Set(SpawnId),
  now now: Set(SpawnId),
  now_ms now_ms: Int,
) -> #(State, List(Effect(ServiceEffect(Outgoing)))) {
  use <- bool.guard(when: was == now, return: #(state, []))
  let entered = in_order(set.difference(now, was))
  let left = in_order(set.difference(was, now))
  let #(state, starts, sends) =
    list.fold(entered, #(state, [], []), fn(held, spawn) {
      let #(state, starts, sends) = held
      case dict.get(state.spawns, spawn) {
        Error(Nil) -> {
          let #(state, start) =
            start_creature(state:, spawn:, viewers: [#(connection, stay)])
          #(state, [start, ..starts], sends)
        }
        Ok(Live(unit_id:, life:, viewers:, ..)) -> #(
          State(
            ..state,
            spawns: dict.insert(
              state.spawns,
              spawn,
              Live(
                unit_id:,
                life:,
                viewers: set.insert(viewers, connection),
                idle_since_ms: option.None,
              ),
            ),
          ),
          starts,
          [
            tell_creature(
              state:,
              unit_id:,
              life:,
              message: Watched(by: connection, stay:),
            ),
            ..sends
          ],
        )
        Ok(Retiring(..)) | Ok(WaitingForRestart) | Ok(Failed) -> held
      }
    })
  let #(state, sends) =
    list.fold(left, #(state, sends), fn(held, spawn) {
      let #(state, sends) = held
      case dict.get(state.spawns, spawn) {
        Ok(Live(unit_id:, life:, viewers:, idle_since_ms:)) -> {
          let viewers = set.delete(viewers, connection)
          let idle_since_ms = case set.is_empty(viewers) {
            True -> Some(now_ms)
            False -> idle_since_ms
          }
          #(
            State(
              ..state,
              spawns: dict.insert(
                state.spawns,
                spawn,
                Live(unit_id:, life:, viewers:, idle_since_ms:),
              ),
            ),
            [
              tell_creature(
                state:,
                unit_id:,
                life:,
                message: Unwatched(by: connection),
              ),
              ..sends
            ],
          )
        }
        Ok(Retiring(..)) | Ok(WaitingForRestart) | Ok(Failed) | Error(Nil) -> #(
          state,
          sends,
        )
      }
    })
  #(state, list.append(list.reverse(starts), list.reverse(sends)))
}

/// The spawns of a set in the order of their numbers.
fn in_order(spawns: Set(SpawnId)) -> List(SpawnId) {
  set.to_list(spawns) |> list.sort(compare_spawns)
}

/// The spawns the player sees by their number, so the sends about them are in
/// one order.
fn seen_in_order(player: Player) -> List(SpawnId) {
  in_order(player.seen)
}

/// The send that tells the creature `unit_id` under `life` that the player of
/// connection `by` sees it (`Watched`) or no longer does (`Unwatched`), or that
/// it ends (`Retire`).
fn tell_creature(
  state state: State,
  unit_id unit_id: Int,
  life life: Int,
  message message: Outgoing,
) -> Effect(ServiceEffect(Outgoing)) {
  OwnEffect(Send(
    to: step.Creature(
      map: state.settings.map,
      incarnation: state.settings.incarnation,
      unit_id:,
      life:,
    ),
    message:,
  ))
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
/// or breaks with a player, by the place it ends at, is told: `SeenBy` both ways
/// for a pair that comes into sight, `UnseenBy` both ways for one that leaves
/// it, each in one step. The map sends no unit and no move. A connection not in
/// the map is an error line and changes nothing.
fn moved(
  state state: State,
  connection connection: ConnectionId,
  place place: Place,
  seq seq: Int,
  now_ms now_ms: Int,
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
                  comes_into_sight(newcomer: #(connection, mover), other: #(
                    other_connection,
                    player,
                  )),
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
                  goes_out_of_sight(first: #(connection, mover), second: #(
                    other_connection,
                    player,
                  )),
                ),
              )
              True, True | False, False -> held
            }
          },
        )
      let seen = spawns_in_sight(state:, place:)
      let #(state, spawn_effects) =
        spawns_decided(
          state:,
          connection:,
          stay: mover.stay,
          was: mover.seen,
          now: seen,
          now_ms:,
        )
      let mover = Player(..mover, unit:, sees: mover_sees, seen:, seq:)
      let #(mover, ring_effects) = case mover.readiness {
        StillLoading -> #(mover, [])
        Loaded -> rings_decided(state:, connection:, player: mover)
      }
      #(
        State(..state, players: dict.insert(others, connection, mover)),
        Effects(list.flatten([effects, spawn_effects, ring_effects])),
      )
    }
  }
}

/// The player of `connection` is ready: each Live hostile creature whose ring it
/// stands in is sent `Approached`, and its later moves are checked against the
/// rings. A second `Ready` in one stay, or one from a connection not in the map,
/// changes nothing.
fn ready(
  state state: State,
  connection connection: ConnectionId,
  seq seq: Int,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.players, connection) {
    Ok(Player(readiness: StillLoading, ..) as player) -> {
      let #(player, effects) =
        rings_decided(
          state:,
          connection:,
          player: Player(
            ..player,
            readiness: Loaded,
            seq: int.max(player.seq, seq),
          ),
        )
      #(
        State(..state, players: dict.insert(state.players, connection, player)),
        Effects(effects),
      )
    }
    Ok(Player(readiness: Loaded, ..)) | Error(Nil) -> #(state, Effects([]))
  }
}

/// The rings the ready `player` of `connection` stands in at its place, against
/// the ones it stood in (`inside`): `Approached` to each Live creature whose ring it
/// entered and `Withdrew` to each whose ring it left, in the order of the spawns,
/// and the player with its new `inside`.
fn rings_decided(
  state state: State,
  connection connection: ConnectionId,
  player player: Player,
) -> #(Player, List(Effect(ServiceEffect(Outgoing)))) {
  let now = rings_holding(state:, player:)
  let entered = in_order(set.difference(now, player.inside))
  let left = in_order(set.difference(player.inside, now))
  let player = Player(..player, inside: now)
  let tell = fn(spawn, message) {
    case dict.get(state.spawns, spawn) {
      Ok(Live(unit_id:, life:, ..)) -> [
        tell_creature(state:, unit_id:, life:, message:),
      ]
      Ok(Retiring(..)) | Ok(WaitingForRestart) | Ok(Failed) | Error(Nil) -> []
    }
  }
  #(
    player,
    list.append(
      list.flat_map(entered, fn(spawn) {
        tell(spawn, approached(connection:, player:))
      }),
      list.flat_map(left, fn(spawn) { tell(spawn, Withdrew(by: connection)) }),
    ),
  )
}

/// The spawns hostile to the player's faction whose ring holds its place: within
/// the aggro range of the spawn's place, in three dimensions, found through the cell
/// index.
fn rings_holding(state state: State, player player: Player) -> Set(SpawnId) {
  let spawns = state.settings.spawns
  let place = player_unit.place(player.unit)
  let range = state.settings.numbers.aggro_range
  let faction_id = player_unit.faction_id(player.unit)
  spawn_cell.near(
    cells: spawns.cells,
    x: start_place.x(place),
    z: start_place.z(place),
    range:,
  )
  |> list.filter(fn(id) {
    case dict.get(spawns.by_id, id) {
      Ok(found) ->
        hostile(spawn: found, faction_id:)
        && sight.squared_distance(first: place, second: found.place)
        <=. range *. range
      Error(Nil) -> False
    }
  })
  |> set.from_list
}

/// Whether the spawn's creature fights a player of the faction on sight.
fn hostile(spawn spawn: spawn.Spawn, faction_id faction_id: Int) -> Bool {
  case shown.faction_of(faction_id:) {
    Ok(shown.Exile) -> spawn.combat.hostile_to.exile
    Ok(shown.Dominion) -> spawn.combat.hostile_to.dominion
    Error(Nil) -> False
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
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.players, connection) {
    Ok(player) -> {
      let #(state, told) =
        without(state:, connection:, player:, why: Camped, now_ms:)
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
/// the body of the character's look and the worn visuals of its Novice set
/// (genesis_prime/game/loadout), kept, and answered as 0x262's record, and
/// the connection is watched. The joiner is then sent a `SeenBy` for each player
/// in sight, and each of them a `SeenBy` of the joiner. A connection already in
/// the map is answered with the record built from the unit the map keeps for
/// it, and sent a `SeenBy` for each player it sees.
fn joined(
  state state: State,
  caller caller: CallerId,
  connection connection: ConnectionId,
  character character: Character,
  place place: Place,
  stay stay: Stay,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.players, connection) {
    Ok(player) ->
      joined_again(
        state:,
        caller:,
        connection:,
        character:,
        player: Player(..player, stay:),
      )
    Error(Nil) ->
      joined_new(
        state:,
        caller:,
        connection:,
        character:,
        place:,
        stay:,
        now_ms:,
      )
  }
}

/// A second join of a connection in the map: the player kept with the new
/// join's stay, an error line, the answer built from the unit the map keeps, and
/// for each player it sees a `SeenBy` for the joiner and one for that player,
/// which sends the joiner its 0x262 again.
fn joined_again(
  state state: State,
  caller caller: CallerId,
  connection connection: ConnectionId,
  character character: Character,
  player player: Player,
) -> #(State, ServiceStep(Outgoing)) {
  let CharacterId(second_character_id) = character.character_id
  let state =
    State(..state, players: dict.insert(state.players, connection, player))
  let watched_again =
    others_of(state:, connection:)
    |> list.filter(fn(other) { set.contains(player.sees, other.0) })
    |> list.flat_map(fn(other) {
      [
        watched(to: #(connection, player), by: other),
        watched(to: other, by: #(connection, player)),
      ]
    })
    |> list.append(
      seen_in_order(player)
      |> list.filter_map(fn(spawn) {
        case dict.get(state.spawns, spawn) {
          Ok(Live(unit_id:, life:, ..)) ->
            Ok(tell_creature(
              state:,
              unit_id:,
              life:,
              message: Watched(by: connection, stay: player.stay),
            ))
          Ok(Retiring(..)) | Ok(WaitingForRestart) | Ok(Failed) | Error(Nil) ->
            Error(Nil)
        }
      }),
    )
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
/// connection watched, and each pair with a player in sight made: `SeenBy`
/// both ways.
fn joined_new(
  state state: State,
  caller caller: CallerId,
  connection connection: ConnectionId,
  character character: Character,
  place place: Place,
  stay stay: Stay,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  let tables = state.settings.tables
  case gear_of(tables:, character:) {
    Error(reason) ->
      not_joined(state:, caller:, connection:, character:, reason:)
    Ok(#(loadout, max_health)) -> {
      let #(state, unit_id) = take_unit_id(state)
      let watch = WatchId(state.next_watch)
      let state = State(..state, next_watch: state.next_watch + 1)
      let unit =
        player_unit.new(
          character:,
          place:,
          unit_id:,
          body: appearance.character_body_visuals(
            index: appearance.index(tables:),
            character:,
          ),
          loadout:,
          max_health:,
        )
      joined_with(
        state:,
        caller:,
        connection:,
        place:,
        now_ms:,
        player: Player(
          stay:,
          unit:,
          watch:,
          sees: set.new(),
          seen: set.new(),
          objects: set.new(),
          readiness: StillLoading,
          seq: 0,
          inside: set.new(),
        ),
      )
    }
  }
}

/// The loadout of the character's class and faction and its maximum health at
/// its level, or why the character cannot be in the map.
fn gear_of(
  tables tables: table_store.Tables,
  character character: Character,
) -> Result(#(Loadout, Int), NotJoined) {
  use loadout <- result.try(
    loadout.of(
      tables:,
      class_id: character.class_id,
      faction_id: character.faction_id,
    )
    |> result.replace_error(NoLoadout(
      class_id: character.class_id.value,
      faction_id: character.faction_id,
    )),
  )
  loadout.max_health(tables:, loadout:, level: character.level)
  |> result.replace_error(NoBaseHealth(level: character.level))
  |> result.map(fn(max_health) { #(loadout, max_health) })
}

/// A join the map refuses: an error line naming the character and why, and the
/// answer `NotJoined`. No unit id is taken and nothing is kept.
fn not_joined(
  state state: State,
  caller caller: CallerId,
  connection connection: ConnectionId,
  character character: Character,
  reason reason: NotJoined,
) -> #(State, ServiceStep(Outgoing)) {
  let CharacterId(character_id) = character.character_id
  #(
    state,
    Effects([
      log_error(
        state:,
        about: step.About(
          ..step.no_one,
          connection: Some(connection),
          character_id: Some(character_id),
        ),
        text: "the character cannot join the map: "
          <> describe_not_joined(reason:),
      ),
      OwnEffect(Reply(caller, NotJoined(reason:))),
    ]),
  )
}

/// A sentence that says why a join is refused, for the log.
pub fn describe_not_joined(reason reason: NotJoined) -> String {
  case reason {
    NoLoadout(class_id:, faction_id:) ->
      "no Novice set holds class "
      <> int.to_string(class_id)
      <> " and faction "
      <> int.to_string(faction_id)
    NoBaseHealth(level:) ->
      "CreatureLevel has no row for level " <> int.to_string(level)
  }
}

/// The rest of the first join, once the player is built with its unit and its
/// watch, seeing nothing: its sight, its watch and its answer.
fn joined_with(
  state state: State,
  caller caller: CallerId,
  connection connection: ConnectionId,
  place place: Place,
  now_ms now_ms: Int,
  player player: Player,
) -> #(State, ServiceStep(Outgoing)) {
  let unit = player.unit
  let watch = player.watch
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
      comes_into_sight(newcomer: #(connection, player), other:)
    })
  let seen = spawns_in_sight(state:, place:)
  let #(state, spawn_effects) =
    spawns_decided(
      state:,
      connection:,
      stay: player.stay,
      was: set.new(),
      now: seen,
      now_ms:,
    )
  #(
    State(
      ..state,
      players: dict.insert(players, connection, Player(..player, sees:, seen:)),
      watches: dict.insert(state.watches, watch, connection),
    ),
    Effects(
      list.flatten([
        [
          Watch(watch:, target: Connection(connection)),
          OwnEffect(Reply(caller, answer(state:, unit:))),
        ],
        pairs,
        spawn_effects,
      ]),
    ),
  )
}

/// The send that tells the player `to` that the player `by`, in its stay, sees
/// it.
fn watched(
  to to: #(ConnectionId, Player),
  by by: #(ConnectionId, Player),
) -> Effect(ServiceEffect(Outgoing)) {
  notify(to:, notice: SeenBy(by: by.0, stay: { by.1 }.stay))
}

/// The send that tells the player `to` that the player of connection `by` no
/// longer sees it.
fn unwatched(
  to to: #(ConnectionId, Player),
  by by: ConnectionId,
) -> Effect(ServiceEffect(Outgoing)) {
  notify(to:, notice: UnseenBy(by:))
}

/// The sends of a pair that comes into sight, in one step: each of the two is
/// told the other sees it, in the other's stay. A joiner and a mover are the
/// newcomer.
fn comes_into_sight(
  newcomer newcomer: #(ConnectionId, Player),
  other other: #(ConnectionId, Player),
) -> List(Effect(ServiceEffect(Outgoing))) {
  [watched(to: other, by: newcomer), watched(to: newcomer, by: other)]
}

/// The sends of a pair that leaves sight, in one step: each of the two is told
/// the other no longer sees it.
fn goes_out_of_sight(
  first first: #(ConnectionId, Player),
  second second: #(ConnectionId, Player),
) -> List(Effect(ServiceEffect(Outgoing))) {
  [unwatched(to: second, by: first.0), unwatched(to: first, by: second.0)]
}

/// The answer to a join: the unit as message 0x262's record in the map's
/// realm, the map's incarnation and the origin of its clock.
fn answer(state state: State, unit unit: PlayerUnit) -> Outgoing {
  Joined(
    unit: player_unit.create(unit:, realm_id: state.settings.realm_id),
    loadout: player_unit.loadout(unit:),
    max_health: player_unit.max_health(unit:),
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
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.watches, watch) {
    Ok(connection) ->
      case dict.get(state.players, connection) {
        Ok(player) -> {
          let #(state, told) =
            without(state:, connection:, player:, why: Ended, now_ms:)
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
  now_ms now_ms: Int,
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
  let #(state, spawn_effects) =
    spawns_decided(
      state:,
      connection:,
      stay: player.stay,
      was: player.seen,
      now: set.new(),
      now_ms:,
    )
  #(
    State(..state, players:, watches: dict.delete(state.watches, player.watch)),
    list.append(
      case why {
        Camped ->
          list.map(viewers, fn(viewer) { unwatched(to: viewer, by: connection) })
        Ended ->
          list.flat_map(others, fn(other) {
            let gone =
              notify(
                to: other,
                notice: Gone(unit_id: player_unit.unit_id(player.unit)),
              )
            case set.contains(player.sees, other.0) {
              True -> [unwatched(to: other, by: connection), gone]
              False -> [gone]
            }
          })
      },
      spawn_effects,
    ),
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

/// A send to the connection of a player in the map: the notice, for the
/// player's stay.
fn notify(
  to player: #(ConnectionId, Player),
  notice notice: Notice,
) -> Effect(ServiceEffect(Outgoing)) {
  OwnEffect(Send(
    to: Connection(player.0),
    message: Noticed(stay: { player.1 }.stay, notice:),
  ))
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
