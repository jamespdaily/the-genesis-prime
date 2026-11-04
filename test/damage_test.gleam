//// The value of a damage effect for a player (`genesis_prime/game/damage`), on the
//// raw columns of the client's Spell4Effects rows (`table_rows -- Spell4Effects
//// spellId=<id>`). Expected values come from these places.
//// - At level 1 with rating 0 the stat part is 0 and the value is level x the type 10
////   parameter: Kick 4.16 (row 140383), Zap 9.08 (125182), Telekinetic Strike 18.0
////   (62159), Crush's second spell 8.94 (95950), Paralytic Surge 8.14 (96125) and
////   Stagger's per-hit spell 3.0 (83829); each row's dataBits00 is the float 1.0
////   (bits 1065353216) and dataBits01 is 0.
//// - The level-1 gear's ratings: Assault Rating 203.0625 and Support Rating 55.6875
////   (`player.level1_gear_properties`), Assault Power and Support Power 0.25 of
////   each (`0x140462930`, `0x140462980`), the stat part rounded half away from zero
////   (`0x140566d40`).
//// - A parameter type the rule does not read fails the load of its spell.

import genesis_prime/game/damage.{Attacker, Formula, Parameter, Unread}
import gleam/float
import gleam/option.{None, Some}
import owned_test

fn near(value value: Float, expected expected: Float) -> Bool {
  float.absolute_value(value -. expected) <. 0.0001
}

/// An effect row of the client: dataBits00 1.0 as a float, dataBits01 0, and the
/// parameters (type 12 Assault Power, type 13 Support Power, type 10 level).
fn row(
  assault assault: Float,
  support support: Float,
  per_level per_level: Float,
) -> damage.Formula {
  Formula(multiplier: 1.0, base: 0, parameters: [
    Parameter(kind: 12, value: assault),
    Parameter(kind: 13, value: support),
    Parameter(kind: 10, value: per_level),
  ])
}

fn level_one(rating rating: Float, support support: Float) -> damage.Attacker {
  Attacker(level: 1, assault_rating: rating, support_rating: support)
}

pub fn each_level_one_ability_hits_for_its_level_parameter_at_rating_zero_test() -> Nil {
  use <- owned_test.run(5000)
  let none = level_one(rating: 0.0, support: 0.0)
  assert near(
    value: damage.value(
      formula: row(assault: 0.0656, support: 0.0656, per_level: 4.16),
      attacker: none,
    ),
    expected: 4.16,
  )
    as "Kick, Spell4Effects 140383"
  assert near(
    value: damage.value(
      formula: row(assault: 0.1434, support: 0.1434, per_level: 9.08),
      attacker: none,
    ),
    expected: 9.08,
  )
    as "Zap, 125182"
  assert near(
    value: damage.value(
      formula: row(assault: 0.336, support: 0.0, per_level: 18.0),
      attacker: none,
    ),
    expected: 18.0,
  )
    as "Telekinetic Strike, 62159"
  assert near(
    value: damage.value(
      formula: row(assault: 0.0837, support: 0.0837, per_level: 8.94),
      attacker: none,
    ),
    expected: 8.94,
  )
    as "Crush's second spell, 95950"
  assert near(
    value: damage.value(
      formula: row(assault: 0.0935, support: 0.0935, per_level: 8.14),
      attacker: none,
    ),
    expected: 8.14,
  )
    as "Paralytic Surge, 96125"
  assert near(
    value: damage.value(
      formula: row(assault: 0.035, support: 0.035, per_level: 3.0),
      attacker: none,
    ),
    expected: 3.0,
  )
    as "Stagger's per-hit spell, 83829"
}

pub fn the_gear_ratings_add_a_rounded_stat_part_test() -> Nil {
  use <- owned_test.run(5000)
  let gear = level_one(rating: 203.0625, support: 55.6875)
  assert near(
    value: damage.value(
      formula: row(assault: 0.336, support: 0.0, per_level: 18.0),
      attacker: gear,
    ),
    expected: 35.0,
  )
    as "Telekinetic Strike: Assault Power 50.77 x 0.336 = 17.06 rounds to 17, plus 18"
  assert near(
    value: damage.value(
      formula: row(assault: 0.0656, support: 0.0656, per_level: 4.16),
      attacker: gear,
    ),
    expected: 8.16,
  )
    as "Kick: 0.0656 x 50.77 + 0.0656 x 13.92 = 4.24 rounds to 4, plus 4.16"
}

pub fn a_parameter_type_the_rule_does_not_read_is_named_test() -> Nil {
  use <- owned_test.run(5000)
  assert damage.unread(formula: row(
      assault: 0.0656,
      support: 0.0656,
      per_level: 4.16,
    ))
    == None
  assert damage.unread(
      formula: Formula(multiplier: 1.0, base: 0, parameters: [
        Parameter(kind: 19, value: 0.1),
      ]),
    )
    == Some(Unread(parameter_kind: 19))
    as "type 19 reads the target's health (0x140566ad0), which is not built"
}
