//// Names, settings and characters for the tests of the map: one set of names
//// for each test, a snapshot process the maps register with, and the newcomers
//// the tests join.

import genesis_prime/map/heap_limit.{type HeapLimits, HeapLimits}
import genesis_prime/map/position.{type Position, Position}
import genesis_prime/map/unit.{type Newcomer, Newcomer}
import genesis_prime/map/world_map_process
import genesis_prime/telemetry/snapshot
import gleam/erlang/process.{type Name, type Pid}

/// No ceiling on the map process or on any sender, as in a test that does not
/// read them.
pub fn no_limits() -> HeapLimits {
  HeapLimits(map: heap_limit.no_limit, sender: heap_limit.no_limit)
}

/// A snapshot process that writes no line within a test's lifetime, started
/// under a name of its own, for the maps to register with.
pub fn start_snapshot() -> Name(snapshot.Message) {
  let name = process.new_name("snapshot_of_the_maps")
  let assert Ok(_) =
    snapshot.start(snapshot.Settings(name:, interval_milliseconds: 3_600_000))
    as "the snapshot process did not start"
  name
}

/// Settings of the map of a world, with names of their own.
pub fn settings(
  world_id world_id: Int,
  snapshot snapshot: Name(snapshot.Message),
  limits limits: HeapLimits,
) -> world_map_process.Settings {
  world_map_process.Settings(
    world_id:,
    map: process.new_name("map"),
    snapshot:,
    heap_limits: limits,
  )
}

/// A character that joins a map at a place on the x axis.
pub fn newcomer(character_id character_id: Int, x x: Float) -> Newcomer {
  Newcomer(
    character_id:,
    name: "Ab Cd",
    race_id: 1,
    class_id: 3,
    gender: 1,
    path: 2,
    position: Position(x:, y: 0.0, z: 0.0),
  )
}

/// A place on the x axis.
pub fn at(x x: Float) -> Position {
  Position(x:, y: 0.0, z: 0.0)
}

/// The heap ceiling a running process has set on itself, in words; 0 for none.
@external(erlang, "map_support_ffi", "max_heap_words")
pub fn max_heap_words(pid: Pid) -> Int

/// The schedulers online.
@external(erlang, "map_support_ffi", "schedulers_online")
pub fn schedulers_online() -> Int
