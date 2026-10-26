//// Where a new character starts: one WorldLocation2 row of the client's
//// table, read from the loaded tables.

import genesis_prime/character/character.{type Place}
import genesis_prime/table/loader/store.{type Tables}

/// The place of a WorldLocation2 row, or an error when the table has no such
/// row.
pub fn place(
  tables tables: Tables,
  location_id location_id: Int,
) -> Result(Place, Nil) {
  let _ = tables
  let _ = location_id
  Error(Nil)
}

/// The rows the server requires of the tables so that every new character has
/// a place: the WorldLocation2 row, and the World row it names.
pub fn requirements(location_id location_id: Int) -> List(store.Requirement) {
  let _ = location_id
  []
}
