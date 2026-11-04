//// The key of one spawn: a place a creature stands at, in the server's list of
//// spawns (genesis_prime/world_map/spawn), which the map names when it has a
//// creature started there.

/// One spawn, by its number in the list of spawns, which the load fixes.
pub type SpawnId {
  SpawnId(Int)
}
