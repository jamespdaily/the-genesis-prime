//// The rating formulas of the hit rule (`genesis_prime/game/rating`), read from the
//// client's GameFormula rows 1230, 1231, 1232, 1234, 1235, 1236, 1245 and 1271 in the
//// committed fixture.

import fixture_tables
import genesis_prime/game/rating.{type Formula, type Formulas, Formula, Formulas}
import genesis_prime/table/game_formula
import genesis_prime/table/id.{GameFormulaId}

/// The formulas the hit rule reads.
pub fn formulas() -> Formulas {
  Formulas(
    strikethrough: row(id: 1230),
    crit_chance: row(id: 1231),
    crit_severity: row(id: 1232),
    mitigation: row(id: 1234),
    deflect_chance: row(id: 1235),
    crit_deflect: row(id: 1236),
    glance_chance: row(id: 1245),
    glance_amount: row(id: 1271),
  )
}

fn row(id id: Int) -> Formula {
  let assert Ok(row) =
    game_formula.get(tables: fixture_tables.shared(), id: GameFormulaId(id))
    as "the committed GameFormula rows hold the hit rule's formula"
  Formula(
    f0: row.datafloat0,
    f01: row.datafloat01,
    f02: row.datafloat02,
    f03: row.datafloat03,
    int0: row.dataint0,
    int01: row.dataint01,
  )
}
