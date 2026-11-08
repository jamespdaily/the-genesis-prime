//// The rating formulas of the hit rule (`genesis_prime/game/rating`), as the
//// committed fixture's tables build them.

import fixture_tables
import genesis_prime/game/rating.{type Formulas}

/// The formulas the hit rule reads.
pub fn formulas() -> Formulas {
  rating.formulas(tables: fixture_tables.shared())
}
