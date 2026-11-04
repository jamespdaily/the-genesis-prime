//// The rating formulas of the hit rule as the client's own rows hold them, for the tests
//// that have no client tables (`genesis_prime/game/rating`): GameFormula 1230, 1231,
//// 1232, 1234, 1235, 1236, 1245 and 1271 as the fact file records them (`0x140462ef0`,
//// `0x140463700`, `0x140463e80`, `0x140464240`, `0x140463340`, `0x140463ac0`,
//// `0x140461a30`, `0x1404615f0`), and a player's bases: UnitProperty2's defaults, BaseCritChance 0, a crit severity
//// of 1.5 and BaseAvoidReduceChance 0 (`0x140463e80`).

import genesis_prime/game/rating.{type Formula, type Formulas, Formula, Formulas}
import gleam/list
import novice_tables

/// The formulas, built from the planted GameFormula rows (`novice_tables.formulas`).
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
    player_base_crit_chance: 0.0,
    player_base_crit_severity: 1.5,
    player_base_strikethrough: 0.0,
  )
}

fn row(id id: Int) -> Formula {
  let assert Ok(planted) =
    list.find(novice_tables.formulas(), fn(planted) { planted.id == id })
    as "the planted GameFormula rows hold the hit rule's formula"
  Formula(
    f0: planted.float0,
    f01: planted.float01,
    f02: planted.float02,
    f03: planted.float03,
    int0: planted.dataint0,
    int01: planted.dataint01,
  )
}
