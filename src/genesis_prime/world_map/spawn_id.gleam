//// The key of one spawn: the id of its row in the spawn table, which the world's import
//// keeps when it runs again, and which the map names when it has a creature started
//// there (genesis_prime/world_map/spawn). A spawn a development command makes for one
//// run of a map has a negative id (genesis_prime/world_map/spawn_source); one the
//// server places for a quest objective takes an id above the highest stored one
//// (genesis_prime/world_map/objective_spawn).

import gleam/int
import gleam/set.{type Set}

/// One spawn, by its id.
pub type SpawnId {
  SpawnId(Int)
}

/// The ids of the spawn table's rows as the load found them, and the highest. A spawn id
/// above the highest is no stored row's: the server placed it, and a later import can give
/// the same number to a stored row.
pub type StoredSpawns {
  StoredSpawns(ids: Set(SpawnId), highest: Int)
}

/// What a spawn id is to the loaded world.
pub type Presence {
  /// A row of the spawn table.
  Stored
  /// A spawn the table had, and the loaded world lacks.
  Lost
  /// A spawn the server placed, which no row names.
  Placed
}

/// The stored spawns with these ids.
pub fn stored(ids ids: Set(SpawnId)) -> StoredSpawns {
  let highest =
    set.fold(ids, 0, fn(highest, id) {
      let SpawnId(number) = id
      int.max(highest, number)
    })
  StoredSpawns(ids:, highest:)
}

/// What the spawn is to the stored spawns.
pub fn presence(stored stored: StoredSpawns, spawn spawn: SpawnId) -> Presence {
  let SpawnId(number) = spawn
  case set.contains(stored.ids, spawn), number > stored.highest {
    True, _ -> Stored
    False, True -> Placed
    False, False -> Lost
  }
}
