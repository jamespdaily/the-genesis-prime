//// The process that owns one world's map: the state of `world_map` and the
//// connections of the players on it. A player's connection asks it to join; the
//// map gives the player's unit an id, holds it, and tells the players in range
//// through a pool of sender processes (one for each scheduler online), so no
//// one message holds the map for long.
////
//// The supervision tree of one map is one supervisor, restarting its children
//// rest for one: the senders first, then the map process. A sender that
//// crashes takes the map process down with it, because the map process starts
//// after the senders. The map process is registered under a name made by
//// whoever starts the map; the senders under names of their own, so a rebuilt
//// map process reaches the rebuilt senders. A restarted map starts empty:
//// every player on it is told nothing, and each connection must join again.
////
//// The map process monitors the connection of each player that joined and
//// takes the player's unit off the map when the connection ends.

import genesis_prime/map/delivery.{type Delivery}
import genesis_prime/map/heap_limit.{type HeapLimits}
import genesis_prime/map/unit.{type Newcomer, type PlayerUnit}
import genesis_prime/map/world_map.{type JoinRefused}
import genesis_prime/telemetry/snapshot
import gleam/erlang/process.{type Name, type Subject}
import gleam/otp/actor
import gleam/otp/static_supervisor.{type Supervisor}

/// What a map starts with. `world_id` is the World row the map is of. `map` is
/// the name the map process registers under, and `snapshot` the name of the
/// snapshot process the map registers its processes with, each made once by
/// whoever starts the tree. `heap_limits` are the ceilings of the map process
/// and each sender.
pub type Settings {
  Settings(
    world_id: Int,
    map: Name(Message),
    snapshot: Name(snapshot.Message),
    heap_limits: HeapLimits,
  )
}

/// Every message the map process receives.
pub opaque type Message {
  Join(
    newcomer: Newcomer,
    connection: Subject(Delivery),
    reply: Subject(Result(PlayerUnit, JoinRefused)),
  )
  Units(reply: Subject(List(PlayerUnit)))
}

/// Why a join did not give the player a unit.
pub type JoinError {
  /// The map refused the character.
  Refused(JoinRefused)
  /// The map did not answer within the time given.
  NotAnswering
}

/// Starts one map: its supervisor, which starts the senders and then the map
/// process, restarting them rest for one, 3 restarts in 5 seconds: a rebuild
/// of a map takes milliseconds, so three are far inside that period, and a
/// fault that survives them ends the map, which the next entry starts again.
/// The supervisor is linked to the calling process.
pub fn start(settings settings: Settings) -> actor.StartResult(Supervisor) {
  todo as "starts the map's supervisor, its senders and the map process"
}

/// Asks the map to join a character's unit, with the subject its connection
/// receives deliveries on, and waits up to `within_ms` milliseconds for the
/// unit.
pub fn join(
  map map: Subject(Message),
  newcomer newcomer: Newcomer,
  connection connection: Subject(Delivery),
  within_ms within_ms: Int,
) -> Result(PlayerUnit, JoinError) {
  todo as "asks the map to join a character"
}

/// The units the map holds, waiting up to `within_ms` milliseconds for the
/// answer.
pub fn units(
  map map: Subject(Message),
  within_ms within_ms: Int,
) -> Result(List(PlayerUnit), Nil) {
  todo as "asks the map for its units"
}
