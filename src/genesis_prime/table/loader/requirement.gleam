//// The rows the server requires of the client's tables: columns whose ids
//// must all have a row in another table, checked at load.

import genesis_prime/game/start_place
import genesis_prime/table/loader/store

/// Each required column. A feature that reads a column adds it here, with the
/// evidence that the client reads it.
/// - The start places of the starts of each race and faction, each a row of
///   WorldLocation2 (genesis_prime/game/start_place).
pub fn all() -> List(store.Requirement) {
  [start_place.requirement()]
}
