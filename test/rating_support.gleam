//// The rating formulas of the hit rule as the client's own rows hold them, for the tests
//// that have no client tables (`genesis_prime/game/rating`): GameFormula 1230, 1231,
//// 1232, 1234, 1235, 1236, 1245 and 1271 as the fact file records them (`0x140462ef0`,
//// `0x140463700`, `0x140463e80`, `0x140464240`, `0x140463340`, `0x140463ac0`,
//// `0x140461a30`, `0x1404615f0`), and a player's bases: UnitProperty2's defaults, BaseCritChance 0, a crit severity
//// of 1.5 and BaseAvoidReduceChance 0 (`0x140463e80`).

import genesis_prime/game/rating.{type Formulas, Formula, Formulas}

/// The formulas.
pub fn formulas() -> Formulas {
  Formulas(
    strikethrough: Formula(
      f0: 50.0,
      f01: 0.003,
      f02: 30.0,
      f03: 5000.0,
      int0: 0,
      int01: 100,
    ),
    crit_chance: Formula(
      f0: 50.0,
      f01: 0.0025,
      f02: 30.0,
      f03: 7000.0,
      int0: 0,
      int01: 100,
    ),
    crit_severity: Formula(
      f0: 50.0,
      f01: 0.01,
      f02: 250.0,
      f03: 5500.0,
      int0: 0,
      int01: 300,
    ),
    mitigation: Formula(
      f0: 50.0,
      f01: 0.008,
      f02: 0.0,
      f03: 7250.0,
      int0: 0,
      int01: 75,
    ),
    deflect_chance: Formula(
      f0: 50.0,
      f01: 0.0015,
      f02: 30.0,
      f03: 7000.0,
      int0: 0,
      int01: 100,
    ),
    crit_deflect: Formula(
      f0: 50.0,
      f01: 0.0025,
      f02: 100.0,
      f03: 778.0,
      int0: 0,
      int01: 100,
    ),
    glance_chance: Formula(
      f0: 50.0,
      f01: 0.005792,
      f02: 60.0,
      f03: 4000.0,
      int0: 0,
      int01: 100,
    ),
    glance_amount: Formula(
      f0: 50.0,
      f01: 0.0055,
      f02: 75.0,
      f03: 4000.0,
      int0: 0,
      int01: 100,
    ),
    player_base_crit_chance: 0.0,
    player_base_crit_severity: 1.5,
    player_base_strikethrough: 0.0,
  )
}
