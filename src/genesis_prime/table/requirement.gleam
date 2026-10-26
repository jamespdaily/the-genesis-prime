//// The rows the server requires of the client's tables: columns whose ids
//// must all have a row in another table, checked at load.

import genesis_prime/table/store

/// Each required column. A feature that reads a column adds it here, with the
/// evidence that the client reads it. The list is empty.
pub fn all() -> List(store.Requirement) {
  []
}
