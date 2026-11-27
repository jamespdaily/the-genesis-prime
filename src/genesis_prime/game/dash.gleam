//// Stub of the dash rule: the rule comes in a later commit.

import genesis_prime/shared/spell_plan.{type Cost}
import genesis_prime/table/loader/store as table_store

/// The dash spell of each direction.
pub type Dashes {
  Dashes
}

/// The dashes of the tables.
pub fn dashes(tables _tables: table_store.Tables) -> Dashes {
  Dashes
}

/// The Spell4 a direction's dash is.
pub fn spell4_id_of(
  dashes _dashes: Dashes,
  direction _direction: Int,
) -> Result(Int, Nil) {
  Error(Nil)
}

/// The innate costs of a direction's dash.
pub fn costs_of(
  dashes _dashes: Dashes,
  direction _direction: Int,
) -> Result(List(Cost), Nil) {
  Error(Nil)
}
