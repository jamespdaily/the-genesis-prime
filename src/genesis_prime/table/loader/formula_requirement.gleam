//// The load's requirement that one GameFormula row exists, for each server rule that reads a
//// row of that table by its id. It sits in the loader, not beside the generated GameFormula
//// module, which the table generator writes and checks whole.

import genesis_prime/table/game_formula
import genesis_prime/table/id.{GameFormulaId}
import genesis_prime/table/loader/store

/// A requirement that GameFormula row `id` exists, named for the rule `from_table` that reads it.
pub fn row_present(
  from_table from_table: String,
  id id: Int,
) -> store.Requirement {
  store.Requirement(
    from_table:,
    column: "GameFormula id",
    to_table: "GameFormula",
    missing: fn(tables) {
      case game_formula.get(tables:, id: GameFormulaId(id)) {
        Ok(_) -> []
        Error(Nil) -> [id]
      }
    },
  )
}
