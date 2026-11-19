//// The passed-in value in a formula (`genesis_prime/game/damage`). Expected values come from
//// these places.
//// - Spell4Effects 69917 (Basic Medishot: Instant Healing, Spell4 34985): a Heal row with
////   dataBits00 1.0, dataBits01 0 and parameter 18 with the value 200.0; its text 271179
////   reads "Restores $(eff=69917.input0pct) health."
//// - `ComputeEffectValue` `0x140565600`: a type 18 parameter is its value times the
////   passed-in float, in the flat part, for any effect.
//// - A parameter with no factor adds nothing, whatever its type (`first_unread` skips it).
//// - A strike's row keeps refusing type 18, and a creature caster does not read it
////   (`damage.unread`, `damage.creature_unread`): the passed-in value of a strike is the
////   level of the spell's item, which a strike does not hold.

import attacker_support
import fixture_tables
import genesis_prime/game/damage.{
  type OnCaster, Attacker, Formula, OnCaster, Parameter, Unread, Vitals,
}
import genesis_prime/table/id.{Spell4EffectsId}
import genesis_prime/table/spell4_effects
import gleam/list
import gleam/option.{None, Some}
import owned_test

/// The formula of the client's Heal row 69917, as the plan builds it.
fn medishot() -> damage.Formula {
  let assert Ok(row) =
    spell4_effects.get(
      tables: fixture_tables.shared(),
      id: Spell4EffectsId(69_917),
    )
    as "the fixture holds the row"
  let assert Ok(formula) = damage.formula_of(effect: row)
    as "the row's dataBits00 is a finite float"
  formula
}

fn healer(passed_in passed_in: Float) -> OnCaster {
  OnCaster(
    attacker: Attacker(..attacker_support.fresh(), passed_in:),
    vitals: Vitals(health: 300, max_health: 736, shield: 450, max_shield: 450),
  )
}

pub fn a_type_18_parameter_reads_the_passed_in_value_test() -> Nil {
  use <- owned_test.run(5000)
  // #(passed-in value, the amount 200 x it gives, what the row shows)
  list.each(
    [
      #(6.5, 1300, "200 x 6.5, the value at Basic Medishot's level 5"),
      #(
        5.3,
        1060,
        "200 x 5.3 at the same player level: the amount follows passed_in",
      ),
    ],
    fn(row) {
      assert damage.amount_on_caster(
          formula: medishot(),
          caster: healer(passed_in: row.0),
        )
        == row.1
        as row.2
    },
  )
  assert damage.amount_on_caster(
      formula: Formula(multiplier: 1.0, base: 0.0, parameters: [
        Parameter(kind: 18, value: 0.0),
      ]),
      caster: healer(passed_in: 6.5),
    )
    == 0
    as "a parameter 18 with the value 0 adds nothing"
  assert damage.unread(formula: medishot()) == Some(Unread(parameter_kind: 18))
    as "a strike's row still names 18 unread"
  assert damage.unread_on_caster(formula: medishot()) == None
    as "an effect on its caster reads it"
  assert damage.creature_unread(formula: medishot())
    == Some(Unread(parameter_kind: 18))
    as "a creature caster refuses it"
}

pub fn a_parameter_type_the_rule_does_not_read_is_named_test() -> Nil {
  use <- owned_test.run(5000)
  assert damage.unread(
      formula: Formula(multiplier: 1.0, base: 0.0, parameters: [
        Parameter(kind: 12, value: 0.0656),
        Parameter(kind: 13, value: 0.0656),
        Parameter(kind: 10, value: 4.16),
      ]),
    )
    == None
    as "the stat kinds 12 and 13 and the level are read"
  assert damage.unread(
      formula: Formula(multiplier: 1.0, base: 0.0, parameters: [
        Parameter(kind: 9, value: 0.1),
      ]),
    )
    == Some(Unread(parameter_kind: 9))
    as "type 9 is the caster's Weapon DPS, which is not built (Spell4Effects.parameterType.6_9)"
  assert damage.unread_on_caster(
      formula: Formula(multiplier: 1.0, base: 0.0, parameters: [
        Parameter(kind: 9, value: 0.1),
      ]),
    )
    == Some(Unread(parameter_kind: 9))
    as "an effect on its caster refuses it too"
}
