//// Where a started creature's spawn comes from: the server's stored spawn table,
//// or a run-only spawn that a development command made for one run of a map
//// (genesis_prime/game/dev_command). A leaf module: a creature's start
//// (genesis_prime/step `CreatureStart`) names its source here, and
//// genesis_prime/world_map/spawn, which cannot be imported by the step module
//// (it reaches the step module through the creature's strike rule), builds the
//// spawn of either.
////
//// ```
//// stored   Stored(id)          ─▶ the creature start reads the world's term: by_id(id)
//// run-only RunOnly(summoned)   ─▶ the creature start builds it again with the world's
////                                 SummonChecks (genesis_prime/world_map/spawn `summoned`),
////                                 as the map did when it answered the summon
//// ```
////
//// - **A run-only spawn id is negative**, counting down from -1. A stored spawn's
////   id is an identity value above 0 (migration 0008's `spawn_id_is_positive`),
////   and a map's sweep timer is 0, so no run-only id is ever a stored id, a timer
////   or 0. A server choice: the client sees only the unit id the map gives.
//// - **A run-only spawn is not saved.** A map that ends or restarts loses its run
////   spawns with the rest of its state.

import genesis_prime/game/start_place.{type Place}
import genesis_prime/table/id.{type Creature2Id}
import genesis_prime/world_map/spawn_id.{type SpawnId, SpawnId}

/// What a run-only spawn is made from: a creature and the place it stands at,
/// as the player who summoned it stands (position and facing). Its display,
/// outfit and factions are worked out from the creature's Creature2 row
/// (genesis_prime/world_map/spawn `summoned`), so the same value gives the same
/// spawn in the map and in the creature's start.
pub type Summoned {
  Summoned(id: SpawnId, creature_id: Creature2Id, place: Place)
}

/// The spawn a creature is started at.
pub type SpawnSource {
  /// A row of the stored spawn table, by its id.
  Stored(id: SpawnId)
  /// A spawn made for this run of the map only.
  RunOnly(summoned: Summoned)
}

/// The id of the first run-only spawn of a map's run.
pub const first_run_only_id = SpawnId(-1)

/// The run-only id after `id`: one lower, so it is never a stored id.
pub fn run_only_id_after(id id: SpawnId) -> SpawnId {
  let SpawnId(number) = id
  SpawnId(number - 1)
}

/// Whether the spawn was made for this run only, so its creature does not
/// respawn after it dies.
pub fn is_run_only(source source: SpawnSource) -> Bool {
  case source {
    Stored(..) -> False
    RunOnly(..) -> True
  }
}

/// The id of the source's spawn.
pub fn id(source source: SpawnSource) -> SpawnId {
  case source {
    Stored(id:) -> id
    RunOnly(summoned:) -> summoned.id
  }
}
