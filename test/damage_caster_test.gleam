//// The value of an effect on its caster (`genesis_prime/game/damage`
//// `value_on_caster`, `amount_on_caster`, `caster_unread`). Expected values come from
//// these places.
//// - `0x140565600` (ComputeEffectValue) and `0x140566ad0` (SumFlatEffectParameters): a
////   parameter of type 7 reads the target's maximum health, 8 the caster's, 10 the
////   caster's level, 14 the caster's shield and 15 the target's, 16 the caster's
////   maximum shield and 17 the target's, 19 the target's health and 23 the caster's, 21
////   the target's missing health (maximum less health) and 25 the caster's, 22 the
////   target's missing shield and 26 the caster's; 18 is a value passed in. When the
////   caster is the target, each pair reads the same unit.
//// - `0x140566d40` and GameFormula 1266: a parameter of type 12 or 13 reads the caster's
////   Assault Power or Support Power, a rating times 0.25, and the sum is rounded half
////   away from zero.
//// - Spell4Effects 228914 (Medic Energize 69450): parameter type 22 with value 0.3,
////   dataBits00 1.0 and dataBits01 0, whose text 560581 reads "restore
////   $(spell=69450.lasData00pct) of your missing shield"; and
////   `player.level1_gear_properties`: a level-1 Medic's ShieldCapacityMax is 450.
//// - The player's DamageDealtMultiplier is 1.0 (`damage.gleam`'s reading of
////   `0x140565600`).
//// - The whole-number amount rounds half away from zero: the server's choice, as each
////   damage step rounds.

import genesis_prime/game/damage.{
  type Formula, Attacker, Formula, OnCaster, Parameter, Vitals,
}
import gleam/list
import gleam/option.{None, Some}
import owned_test

/// A level-1 Medic with 500 of 736 health and 250 of 450 shield, and no rating.
fn medic() -> damage.OnCaster {
  OnCaster(
    attacker: Attacker(level: 1, assault_rating: 0.0, support_rating: 0.0),
    vitals: Vitals(health: 500, max_health: 736, shield: 250, max_shield: 450),
  )
}

/// A formula of a multiplier 1.0 and a base of 0 with one parameter.
fn formula(kind kind: Int, factor factor: Float) -> Formula {
  Formula(multiplier: 1.0, base: 0, parameters: [
    Parameter(kind:, value: factor),
    Parameter(kind: 0, value: 0.0),
    Parameter(kind: 0, value: 0.0),
    Parameter(kind: 0, value: 0.0),
  ])
}

pub fn energize_refills_three_tenths_of_the_missing_shield_test() -> Nil {
  use <- owned_test.run(5000)
  assert damage.amount_on_caster(
      formula: formula(kind: 22, factor: 0.3),
      caster: medic(),
    )
    == 60
    as "0.3 x (450 - 250) = 60: row 228914 on a shield of 250 of 450"
}

pub fn each_flat_kind_reads_the_casters_own_vital_test() -> Nil {
  use <- owned_test.run(5000)
  // 736 maximum health, 500 health, 450 maximum shield, 250 shield, level 1, so the
  // missing health is 236 and the missing shield 200.
  let expected = [
    #(7, 736.0),
    #(8, 736.0),
    #(10, 1.0),
    #(14, 250.0),
    #(15, 250.0),
    #(16, 450.0),
    #(17, 450.0),
    #(19, 500.0),
    #(21, 236.0),
    #(22, 200.0),
    #(23, 500.0),
    #(25, 236.0),
    #(26, 200.0),
  ]
  list.each(expected, fn(entry) {
    assert damage.value_on_caster(
        formula: formula(kind: entry.0, factor: 1.0),
        caster: medic(),
      )
      == entry.1
      as "0x140566ad0 reads this kind of the unit that is both caster and target"
    assert damage.caster_unread(formula: formula(kind: entry.0, factor: 1.0))
      == None
      as "and the load reads the kind"
  })
}

pub fn the_stat_part_reads_the_powers_and_rounds_half_away_from_zero_test() -> Nil {
  use <- owned_test.run(5000)
  // Support Rating 55.6875 is a Support Power of 13.921875 (x 0.25); x 0.51 is 7.1,
  // which rounds to 7.
  let caster =
    OnCaster(
      ..medic(),
      attacker: Attacker(level: 1, assault_rating: 0.0, support_rating: 55.6875),
    )
  assert damage.value_on_caster(
      formula: formula(kind: 13, factor: 0.51),
      caster:,
    )
    == 7.0
    as "GameFormula 1266 and 0x140566d40: round(0.51 x 13.921875) = 7"
  assert damage.amount_on_caster(
      formula: formula(kind: 13, factor: 0.51),
      caster:,
    )
    == 7
  let assault =
    OnCaster(
      ..medic(),
      attacker: Attacker(level: 1, assault_rating: 10.0, support_rating: 0.0),
    )
  assert damage.value_on_caster(
      formula: formula(kind: 12, factor: 1.0),
      caster: assault,
    )
    == 3.0
    as "type 12 reads the Assault Power, 10.0 x 0.25 = 2.5, which rounds away from zero to 3"
}

pub fn the_amount_rounds_half_away_from_zero_test() -> Nil {
  use <- owned_test.run(5000)
  // 450 - 435 = 15 missing: 0.3 x 15 = 4.5, which is the server's choice to round up.
  let caster =
    OnCaster(
      ..medic(),
      vitals: Vitals(health: 500, max_health: 736, shield: 435, max_shield: 450),
    )
  assert damage.amount_on_caster(
      formula: formula(kind: 22, factor: 0.3),
      caster:,
    )
    == 5
}

pub fn a_parameter_the_formula_does_not_read_is_named_by_its_type_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x140565600 sums types 1 to 5 and 11 into the stat part and 18 is a value passed in:
  // the server reads neither for an effect on its caster.
  list.each([1, 3, 5, 11, 18], fn(kind) {
    assert damage.caster_unread(formula: formula(kind:, factor: 0.5))
      == Some(damage.Unread(parameter_kind: kind))
  })
  assert damage.caster_unread(formula: formula(kind: 3, factor: 0.0)) == None
    as "a parameter with a factor of 0 adds nothing, whatever its type"
}

pub fn a_negative_amount_is_0_test() -> Nil {
  use <- owned_test.run(5000)
  assert damage.amount_on_caster(
      formula: formula(kind: 22, factor: -0.5),
      caster: medic(),
    )
    == 0
    as "an unsigned field cannot carry it: a heal below 0 is 0 (the server's choice)"
}
