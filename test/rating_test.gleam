//// A rating turned into a chance (`genesis_prime/game/rating`). Expected values come
//// from these places.
//// - RatingToPercent emulated by the decode on GameFormula 1231 at level 1: rating 0,
////   100 and 300 give 0, 0.125 and 0.374993; at level 8 with base 0.05 rating 50
////   gives 0.0578125; at level 50 rating 2000 gives 0.05 (`0x140453b60`).
//// - The cap: the chance never exceeds the row's int01 / 100 (`0x140453b60`).
//// - Mitigation is the same curve from GameFormula 1234 (cap 75), never below 0
////   (`0x140464240`).
//// - The rows of the client's tables: 1231 holds 50, 0.0025, 30, 7000, 0 and a cap of
////   100 (`0x140463700`); 1234 holds 50, 0.008, 0, 7250, 0 and a cap of 75
////   (`0x140464240`); a player's BaseCritChance default is read from UnitProperty2 102
////   and the severity default is 1.5 (`0x140463e80`).

import client_tables
import genesis_prime/game/rating.{Formula}
import gleam/float
import owned_test
import rating_support
import unitest

fn crit_formula() -> rating.Formula {
  Formula(f0: 50.0, f01: 0.0025, f02: 30.0, f03: 7000.0, int0: 0, int01: 100)
}

fn near(value value: Float, expected expected: Float) -> Bool {
  float.absolute_value(value -. expected) <. 0.000001
}

pub fn a_rating_below_the_knee_is_linear_test() -> Nil {
  use <- owned_test.run(5000)
  assert near(
    value: rating.to_fraction(
      formula: crit_formula(),
      level: 1,
      base: 0.0,
      rating: 0.0,
    ),
    expected: 0.0,
  )
  assert near(
    value: rating.to_fraction(
      formula: crit_formula(),
      level: 1,
      base: 0.0,
      rating: 100.0,
    ),
    expected: 0.125,
  )
    as "the decode's emulation: per 0.125 below the knee of 240"
}

pub fn a_rating_past_the_knee_follows_the_cosine_curve_test() -> Nil {
  use <- owned_test.run(5000)
  assert near(
    value: rating.to_fraction(
      formula: crit_formula(),
      level: 1,
      base: 0.0,
      rating: 300.0,
    ),
    expected: 0.374993,
  )
}

pub fn the_level_and_the_base_enter_the_curve_test() -> Nil {
  use <- owned_test.run(5000)
  assert near(
    value: rating.to_fraction(
      formula: crit_formula(),
      level: 8,
      base: 0.05,
      rating: 50.0,
    ),
    expected: 0.0578125,
  )
  assert near(
    value: rating.to_fraction(
      formula: crit_formula(),
      level: 50,
      base: 0.0,
      rating: 2000.0,
    ),
    expected: 0.05,
  )
}

pub fn a_chance_never_exceeds_the_rows_cap_test() -> Nil {
  use <- owned_test.run(5000)
  assert rating.to_fraction(
      formula: crit_formula(),
      level: 1,
      base: 2.0,
      rating: 0.0,
    )
    == 1.0
    as "int01 100 caps the chance at 1"
}

pub fn mitigation_is_never_below_zero_test() -> Nil {
  use <- owned_test.run(5000)
  let formulas =
    rating.Formulas(
      crit_chance: crit_formula(),
      crit_severity: crit_formula(),
      deflect_chance: crit_formula(),
      strikethrough: crit_formula(),
      crit_deflect: crit_formula(),
      glance_chance: crit_formula(),
      glance_amount: crit_formula(),
      mitigation: Formula(
        f0: 50.0,
        f01: 0.008,
        f02: 0.0,
        f03: 7250.0,
        int0: 0,
        int01: 75,
      ),
    )
  assert rating.mitigation_fraction(
      formulas:,
      level: 1,
      base: -0.5,
      rating: 0.0,
    )
    == 0.0
    as "0x140464240 returns max(0, result)"
}

pub fn the_clients_rows_build_the_formulas_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let formulas = rating.formulas(tables: client_tables.shared())
  let crit = formulas.crit_chance
  assert near(value: crit.f0, expected: 50.0)
    && near(value: crit.f01, expected: 0.0025)
    && near(value: crit.f02, expected: 30.0)
    && near(value: crit.f03, expected: 7000.0)
    && crit.int0 == 0
    && crit.int01 == 100
    as "GameFormula 1231 (0x140463700)"
  let mitigation = formulas.mitigation
  assert near(value: mitigation.f01, expected: 0.008)
    && near(value: mitigation.f03, expected: 7250.0)
    && mitigation.int01 == 75
    as "GameFormula 1234 (0x140464240)"
}

pub fn the_test_support_formulas_are_the_clients_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let real = rating.formulas(tables: client_tables.shared())
  let planted = rating_support.formulas()
  let same = fn(first: rating.Formula, second: rating.Formula) {
    near(value: first.f0, expected: second.f0)
    && near(value: first.f01, expected: second.f01)
    && near(value: first.f02, expected: second.f02)
    && near(value: first.f03, expected: second.f03)
    && first.int0 == second.int0
    && first.int01 == second.int01
  }
  assert same(planted.strikethrough, real.strikethrough)
    && same(planted.crit_chance, real.crit_chance)
    && same(planted.crit_severity, real.crit_severity)
    && same(planted.mitigation, real.mitigation)
    && same(planted.deflect_chance, real.deflect_chance)
    && same(planted.crit_deflect, real.crit_deflect)
    && same(planted.glance_chance, real.glance_chance)
    && same(planted.glance_amount, real.glance_amount)
    as "every GameFormula row the tests plant is the client's"
}
