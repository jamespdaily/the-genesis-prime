//// The maps of the game: one map for each world that has a player on it,
//// started when the first character of the world enters and kept for the
//// next. A character enters a world through `enter`, which finds the world's
//// map, or starts it, and joins the character's unit to it.
////
//// The registry process holds which world has which map, and monitors each map
//// it started, so a map that ended is forgotten and started again on the next
//// entry. The maps themselves are children of a factory supervisor, each one
//// map supervisor (`world_map_process.supervised`), temporary: a map whose
//// restarts are used up is not started again by its supervisor but by the
//// next entry. The registry starts first and the factory after it, rest for
//// one, so a registry that is rebuilt stops every map, which no registry
//// remembers.

import genesis_prime/map/delivery.{type Delivery}
import genesis_prime/map/heap_limit.{type HeapLimits}
import genesis_prime/map/unit.{type Newcomer, type PlayerUnit}
import genesis_prime/map/world_map_process
import genesis_prime/telemetry/snapshot
import gleam/erlang/process.{type Name, type Subject}
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/static_supervisor.{type Supervisor}
import gleam/otp/supervision.{type ChildSpecification}

/// What the maps start with, each made once by whoever starts the tree: the
/// registry's name, the name of the factory supervisor that starts the maps,
/// the snapshot process's name and the ceilings of the processes of every
/// map.
pub type Settings {
  Settings(
    registry: Name(Message),
    factory: Name(
      factory_supervisor.Message(world_map_process.Settings, Supervisor),
    ),
    snapshot: Name(snapshot.Message),
    heap_limits: HeapLimits,
  )
}

/// Every message the registry receives.
pub opaque type Message {
  Enter(
    world_id: Int,
    newcomer: Newcomer,
    connection: Subject(Delivery),
    reply: Subject(Result(PlayerUnit, EnterError)),
  )
}

/// Why a character did not enter a map.
pub type EnterError {
  /// The map of the world could not be started.
  MapNotStarted(actor.StartError)
  /// The map did not give the character a unit.
  MapRefused(world_map_process.JoinError)
  /// The registry did not answer within the time given.
  RegistryNotAnswering
}

/// The maps' subtree as a child of the game's supervisor: the registry, then
/// the factory supervisor of the maps, rest for one.
pub fn supervised(
  settings settings: Settings,
) -> ChildSpecification(Supervisor) {
  todo as "the child specification of the maps' subtree"
}

/// Joins a character's unit to the map of the world, starting the map when the
/// world has none, and waits up to `within_ms` milliseconds for the unit. The
/// connection receives the map's deliveries on `connection`.
pub fn enter(
  registry registry: Name(Message),
  world_id world_id: Int,
  newcomer newcomer: Newcomer,
  connection connection: Subject(Delivery),
  within_ms within_ms: Int,
) -> Result(PlayerUnit, EnterError) {
  todo as "a character enters the map of its world"
}
