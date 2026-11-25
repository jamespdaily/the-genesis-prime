//// The key of one spawn: the id of its row in the spawn table, which the world's import
//// keeps when it runs again, and which the map names when it has a creature started
//// there (genesis_prime/world_map/spawn). A spawn a development command makes for one
//// run of a map has a negative id (genesis_prime/world_map/spawn_source); one the
//// server places for a quest objective has an id fixed by the client's tables alone, from
//// 1,000,000,000 up, which no stored row may have (genesis_prime/world_map/objective_spawn).

import gleam/bool
import gleam/set.{type Set}

/// One spawn, by its id.
pub type SpawnId {
  SpawnId(Int)
}

/// The ids of the spawns the content load found: every row of the spawn table, started or
/// not, and every spawn the server placed for a quest objective.
pub type LoadedSpawns {
  LoadedSpawns(ids: Set(SpawnId))
}

/// What a spawn id is to the loaded world.
pub type Presence {
  /// A spawn the load found.
  Loaded
  /// A spawn the load does not hold: a row that was deleted, or a placed spawn a stored row
  /// now serves.
  Lost
}

/// The spawns with these ids.
pub fn loaded(ids ids: Set(SpawnId)) -> LoadedSpawns {
  LoadedSpawns(ids:)
}

/// What the spawn is to the loaded spawns.
pub fn presence(spawns spawns: LoadedSpawns, spawn spawn: SpawnId) -> Presence {
  use <- bool.guard(when: set.contains(spawns.ids, spawn), return: Loaded)
  Lost
}
