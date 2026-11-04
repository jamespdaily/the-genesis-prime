//// The values the server builds once when its tables load, each from the
//// tables a rule reads, and stores under the tables' key.

import genesis_prime/game/appearance
import genesis_prime/game/top_zone
import genesis_prime/table/loader/store
import genesis_prime/world_map/spawn

/// Each derived value. A feature whose rule reads a value of the tables that
/// is costly to build adds it here.
/// - The appearance index: the factions of the labels and the rows the
///   character list's bodies are taken from (genesis_prime/game/appearance).
/// - The top zones: each WorldZone's top zone, which a cycle in the parent chain
///   fails (genesis_prime/game/top_zone).
/// - The spawns: each creature's place and values, which a creature the client
///   would not load fails (genesis_prime/world_map/spawn).
pub fn all() -> List(store.Derivation) {
  [appearance.derivation(), top_zone.derivation(), spawn.derivation()]
}
