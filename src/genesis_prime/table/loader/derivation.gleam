//// The values the server builds once when its tables load, each from the
//// tables a rule reads, and stores under the tables' key.

import genesis_prime/game/appearance
import genesis_prime/game/loadout
import genesis_prime/game/top_zone
import genesis_prime/table/loader/store

/// Each derived value. A feature whose rule reads a value of the tables that
/// is costly to build adds it here.
/// - The appearance index: the factions of the labels and the rows the
///   character list's bodies are taken from (genesis_prime/game/appearance).
/// - The loadouts: each class and faction's Novice weapon, abilities and gear
///   properties, whose missing rows fail the load (genesis_prime/game/loadout).
/// - The top zones: each WorldZone's top zone, which a cycle in the parent chain
///   fails (genesis_prime/game/top_zone).
pub fn all() -> List(store.Derivation) {
  [
    appearance.derivation(),
    loadout.derivation(),
    top_zone.derivation(),
  ]
}
