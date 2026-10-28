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

import genesis_prime/step.{type ConnectionId, type Input, type Rule, type Step, type WatchId}
import genesis_prime/world_map/map_id.{type MapId}
import gleam/dict.{type Dict}

/// The rule's name in a recording's header.
pub const rule_name = "genesis_prime/world_map/map"

/// What a map is started with: which map it is.
pub type Settings {
  Settings(map: MapId)
}

/// What a connection asks a map.
pub type Message {
  /// Put the character in the map as the connection's player.
  Join(connection: ConnectionId, character_id: Int)
}

/// A map's answers.
pub type Outgoing {
  /// The player is in the map with this unit id.
  Joined(unit_id: Int)
}

/// A map's players and what it gives next.
pub opaque type State {
  State(
    settings: Settings,
    players: Dict(ConnectionId, Player),
    next_unit_id: Int,
    next_watch: Int,
  )
}

/// One player in the map.
type Player {
  Player(unit_id: Int, character_id: Int, watch: WatchId)
}

/// The map's rule, as its service shell runs it.
pub fn rule(map map: MapId) -> Rule(Settings, State, Message, Nil, Outgoing, Nil) {
  step.Rule(name: rule_name, settings: Settings(map:), new:, step:)
}

/// A map's first state: no players; unit id 1 and watch 1 are next.
pub fn new(settings: Settings) -> State {
  State(settings:, players: dict.new(), next_unit_id: 1, next_watch: 1)
}

/// One input in, the new state and what the shell must do out, as the
/// sequences above give.
pub fn step(state: State, input: Input(Message, Nil)) -> #(State, Step(Outgoing, Nil)) {
  todo as "built in the build"
}
