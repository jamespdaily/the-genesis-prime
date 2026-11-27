//// The Focus formulas (`genesis_prime/shared/focus`): what a Focus cost needs, the share
//// of the pool recovered and what each tick adds. Expected values come from these
//// places, each named at its assertion:
//// - `CheckInnateCost` 0x1403b3320 case 0xe: a cost needs `(int)(m x cost + 0.5)` whole
////   points; `m` is `FUN_140462a90` = the intensity fraction x GameFormula 1267
////   datafloat01 + property 135 (the table row holds 1.0); DAT_140b79e48 is 0.5. A cost of
////   0 or more is compared as it is (0x1403b37f0 to 0x1403b3813). A negative cost is read
////   as 2^32 + cost in a 32-bit float, the cut number is out of the 32-bit range from a
////   multiplier of 0.5 up (the cut gives -2147483648) and is taken as an absolute value
////   (0x1403b33aa to 0x1403b33d9); the rows below work each by hand in 32-bit floats.
//// - `FUN_140462af0`: the intensity fraction is RatingToPercent (`0x140453b60`) over
////   GameFormula 1243 at the unit's level, with the base property 158 and the rating
////   property 56, and 0.0 when both are 0 (0x140462b15 to 0x140462b24, from the
////   disassembly). GameFormula 1243: f0 50, f01 0.0028, f02 30, f03 5000, int0 0,
////   int01 500 (`table_rows -- GameFormula 1243`).
//// - `FUN_1404602f0` (called by `GetFocusRegenInCombat` 0x14064a8b0): the in-combat
////   share is RatingToPercent over GameFormula 1237 with the base property 107 and the
////   rating property 6 (0x140460311, 0x140460322); GameFormula 1237: f0 50, f01 0.0002,
////   f02 1.5, f03 2000, int0 0, int01 100. `GetFocusRegenNonCombat` 0x14064ac80 is
////   property 108 alone.
//// - `GetFocusRegenInCombat`: a tick adds GameFormula 88 dataint0 (500) x 0.001 x the
////   maximum x the share.
//// - RatingToPercent worked by hand from the rows: per = f0 / level x f01, knee =
////   (f02 - int0) / per, linear below the knee.

import client_tables
import fixture_tables
import genesis_prime/message/float32
import genesis_prime/shared/focus.{Numbers}
import genesis_prime/shared/rating.{Formula}
import genesis_prime/table/loader/store as table_store
import gleam/float
import gleam/int
import gleam/list
import owned_test
import qcheck
import unitest

fn formulas() -> focus.Formulas {
  focus.formulas(tables: fixture_tables.shared())
}

/// A healer at level 6 with the client's property defaults: 0.011 recovery in and out
/// of combat (`UnitProperty2` 107 and 108), a cost modifier of 1.0 (135), no rating
/// (6, 56) and no intensity base (158).
fn numbers() -> focus.Numbers {
  Numbers(
    maximum: 1000.0,
    recovery_rating: 0.0,
    recovery_in_combat: 0.011,
    recovery_out_of_combat: 0.011,
    cost_modifier: 1.0,
    intensity_rating: 0.0,
    intensity_base: 0.0,
    level: 6,
  )
}

fn near(first: Float, second: Float) -> Bool {
  float.loosely_equals(first, second, tolerating: 0.000001)
}

pub fn the_required_points_are_the_clients_cost_times_the_modifier_plus_one_half_cut_to_a_whole_number_test() -> Nil {
  use <- owned_test.run(5000)
  // Cost, modifier (property 135), intensity fraction, the points needed, why.
  [
    #(15, 1.0, 0.0, 15, "1.0 x 15 + 0.5 = 15.5 cut to 15"),
    #(15, 0.75, 0.0, 11, "0.75 x 15 + 0.5 = 11.75 cut to 11"),
    #(22, 0.75, 0.0, 17, "0.75 x 22 + 0.5 = 17.0"),
    #(73, 1.25, 0.0, 91, "1.25 x 73 + 0.5 = 91.75 cut to 91"),
    #(
      150,
      1.0,
      0.1,
      165,
      "m = 0.1 x GameFormula 1267 datafloat01 (1.0) + 1.0 = 1.1; 1.1 x 150 + 0.5 = 165.5 cut to 165",
    ),
    #(1, 0.4, 0.0, 0, "0.4 x 1 + 0.5 = 0.9 cut to 0"),
    #(
      15,
      -1.0,
      0.0,
      -14,
      "a negative modifier: -15 + 0.5 = -14.5 cut to -14, and a cost of 0 or more is not made an absolute value (0x1403b3813 compares it as it is)",
    ),
    #(
      -15,
      1.0,
      0.0,
      -2_147_483_648,
      "a negative cost is read as 2^32 - 15 = 4294967281, which a 32-bit float holds as 2^32; x 1.0 + 0.5 is out of the 32-bit range, so the cut gives -2147483648, which the absolute value leaves (0x1403b33aa, 0x1403b33b4, 0x1403b33c5)",
    ),
    #(
      -1,
      0.4,
      0.0,
      1_717_986_944,
      "2^32 - 1 is 2^32 in a 32-bit float; x 0.4 (the 32-bit float 0.4000000059604645) = 1717986944, + 0.5 is the same float, cut to 1717986944 and not lowered by the absolute value",
    ),
    #(
      -15,
      0.0,
      0.0,
      0,
      "a negative cost with a multiplier of 0: 0 + 0.5 cut to 0",
    ),
  ]
  |> list.each(fn(row) {
    let #(cost, modifier, intensity_fraction, points, reason) = row
    assert focus.required_points(
        formulas: formulas(),
        cost:,
        modifier:,
        intensity_fraction:,
      )
      == points
      as reason
  })
}

pub fn the_intensity_fraction_is_0_with_properties_56_and_158_at_0_and_rises_by_the_curve_of_game_formula_1243_test() -> Nil {
  use <- owned_test.run(5000)
  // Rating (56), base (158), the fraction, why; level 6 throughout.
  [
    #(0.0, 0.0, 0.0, "0x140462b15 to 0x140462b24: both 0 returns 0.0 early"),
    #(
      100.0,
      0.0,
      0.0233333,
      "per = 50 / 6 x 0.0028 = 0.0233333; the knee is 30 / per = 1285.7, so 100 is linear: 2.33333 percent",
    ),
    #(0.0, 0.2, 0.2, "a base alone: the curve gives 0 and the base is added"),
  ]
  |> list.each(fn(row) {
    let #(intensity_rating, intensity_base, fraction, reason) = row
    assert near(
      focus.intensity_fraction(
        formulas: formulas(),
        numbers: Numbers(..numbers(), intensity_rating:, intensity_base:),
      ),
      fraction,
    )
      as reason
  })
}

pub fn a_recovery_rating_raises_the_in_combat_share_by_the_curve_of_game_formula_1237_at_the_players_level_and_never_the_out_of_combat_share_test() -> Nil {
  use <- owned_test.run(5000)
  // Rating (6), in combat, level, base 107, base 108, the share, why.
  [
    #(0.0, True, 6, 0.011, 0.011, 0.011, "no rating: property 107 alone"),
    #(0.0, True, 50, 0.011, 0.011, 0.011, "no rating at level 50: the same"),
    #(
      450.0,
      True,
      6,
      0.011,
      0.011,
      0.0185,
      "per = 50 / 6 x 0.0002 = 0.0016667, the knee is 1.5 / per = 900, so 450 is linear: 0.75 percent, 0.0075 + 0.011",
    ),
    #(
      1900.0,
      True,
      6,
      0.011,
      0.011,
      0.0404338,
      "past the knee: beyond 1000, 1.5 + 0.0016667 x 1000 x cos(pi / 2 x 1000 / 3000) = 2.943376 percent, + 0.011",
    ),
    #(
      450.0,
      True,
      6,
      0.02,
      0.011,
      0.0275,
      "a modified property 107 is the base: 0.0075 + 0.02",
    ),
    #(
      450.0,
      False,
      6,
      0.011,
      0.011,
      0.011,
      "out of combat the rating changes nothing (0x14064ac80)",
    ),
    #(
      450.0,
      False,
      50,
      0.011,
      0.03,
      0.03,
      "out of combat the level changes nothing and property 108 is the share",
    ),
  ]
  |> list.each(fn(row) {
    let #(
      recovery_rating,
      in_combat,
      level,
      recovery_in_combat,
      recovery_out_of_combat,
      share,
      reason,
    ) = row
    assert near(
      focus.share(
        formulas: formulas(),
        numbers: Numbers(
          ..numbers(),
          recovery_rating:,
          level:,
          recovery_in_combat:,
          recovery_out_of_combat:,
        ),
        in_combat:,
      ),
      share,
    )
      as reason
  })
}

pub fn a_tick_adds_the_maximum_times_the_share_times_one_half_from_game_formula_88_test() -> Nil {
  use <- owned_test.run(5000)
  // The maximum, the share, the points a tick adds, why.
  [
    #(1000.0, 0.011, 5.5, "500 ms x 0.001 x 1000 x 0.011"),
    #(1500.0, 0.011, 8.25, "a pool of 1500"),
    #(1000.0, 0.0, 0.0, "a share of 0"),
  ]
  |> list.each(fn(row) {
    let #(maximum, share, added, reason) = row
    assert near(focus.per_tick(formulas: formulas(), maximum:, share:), added)
      as reason
  })
}

pub fn the_formulas_load_from_game_formula_88_1237_1243_and_1267_and_a_missing_row_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let loaded = focus.formulas(tables: client_tables.shared())
  assert loaded.tick_ms == 500 as "GameFormula 88 dataint0"
  assert loaded.recovery
    == Formula(
      f0: 50.0,
      f01: float32.rounded(0.0002),
      f02: 1.5,
      f03: 2000.0,
      int0: 0,
      int01: 100,
    )
    as "GameFormula 1237"
  assert loaded.intensity
    == Formula(
      f0: 50.0,
      f01: float32.rounded(0.0028),
      f02: 30.0,
      f03: 5000.0,
      int0: 0,
      int01: 500,
    )
    as "GameFormula 1243"
  assert loaded.intensity_weight == 1.0 as "GameFormula 1267 datafloat01"
  list.each([88, 1237, 1243, 1267], fn(id) {
    let assert Ok(without) =
      fixture_tables.remove(
        rows: fixture_tables.rows(),
        table: "GameFormula",
        id:,
      )
      as "the client's table holds the row"
    let assert Error(table_store.DerivationFailed(name:, reason:)) =
      fixture_tables.load(rows: without)
      as "a load without a row the Focus rule reads fails"
    assert name == "FocusFormulas"
    assert reason
      == "the table GameFormula has no row "
      <> int.to_string(id)
      <> ", which the Focus rule reads"
  })
}

pub fn the_required_points_and_the_tick_are_never_negative_and_the_in_combat_share_is_never_below_the_base_for_a_rating_at_or_above_0_test() -> Nil {
  use <- owned_test.run(30_000)
  qcheck.given(
    qcheck.tuple5(
      qcheck.bounded_float(from: 0.0, to: 3.0),
      qcheck.bounded_int(from: 0, to: 500),
      qcheck.bounded_float(from: 0.0, to: 5000.0),
      qcheck.bounded_float(from: 0.0, to: 0.5),
      qcheck.bounded_int(from: 1, to: 50),
    ),
    fn(drawn) {
      let #(modifier, cost, rating, base, level) = drawn
      let formulas = formulas()
      let intensity_fraction = rating /. 5000.0
      let required =
        focus.required_points(formulas:, cost:, modifier:, intensity_fraction:)
      assert required >= 0
        as "a cost of 0 or more with a modifier of 0 or more needs a count"
      // The exact product the 32-bit arithmetic approximates: m x cost + 0.5, cut.
      let exact =
        { modifier +. intensity_fraction *. formulas.intensity_weight }
        *. int.to_float(cost)
        +. 0.5
      let slack = 0.000001 *. exact +. 0.000001
      assert int.to_float(required) <=. exact +. slack
        as "the whole points never exceed m x cost + 0.5"
      assert int.to_float(required) >. exact -. 1.0 -. slack
        as "the cut takes less than one whole point"
      let share =
        focus.share(
          formulas:,
          numbers: Numbers(
            ..numbers(),
            recovery_rating: rating,
            recovery_in_combat: base,
            level:,
          ),
          in_combat: True,
        )
      assert share >=. float32.rounded(base) -. 0.000001
        as "a rating at or above 0 never lowers the base (RatingToPercent adds to it)"
      assert focus.per_tick(formulas:, maximum: 1000.0, share:) >=. 0.0
        as "a tick never takes points away"
    },
  )
}
