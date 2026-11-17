//// What each held unit state refuses of a cast (`genesis_prime/game/unit_state`). Expected
//// values come from these places:
//// - `Spell.CodeEnumCastResult.306_308`: 306 refuses a hostile cast ("Target immune to
////   hostile spells", text 484558), 308 a beneficial one ("Target immune to beneficial
////   spells", 484560), and 307 has no state that gives it.
//// - `Spell4Effects.effectType.15`: the reading of each state is a guess from the names of
////   the spells that hold it, from the client's rows: 6 "Invulnerability - Generic Invuln
////   Spell" (row 7022, Spell4 4178, which holds 6 and 13 to 18) and "[RAID] Generic Infinite
////   Invulnerability" (row 112154), 7 to 9 and 3 to 5 "Makes the recipient immune to ALL
////   spells" (Spell4 2362 and 5632), 22 "Generic Hostile Invulnerability" (row 176054, Spell4
////   69781), 19 "Immune (Beneficial)" (row 219651, Spell4 83193), 1 Block, and 0, 2, 10 and
////   23 with no name that says what they do.

import genesis_prime/game/unit_state.{
  ImmuneToBeneficial, Invulnerable, NoReading,
}
import genesis_prime/message/cast_result
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test

pub fn each_state_of_the_clients_rows_has_its_stated_reading_test() -> Nil {
  use <- owned_test.run(10_000)
  // The states the client's rows hold are 0 to 10, 13 to 19, 22 and 23 (dataBits00 of the
  // 752 rows of type 15); 11, 12, 20 and 21 hold none.
  let invulnerable = [3, 4, 5, 6, 7, 8, 9, 13, 14, 15, 16, 17, 18, 22]
  list.each(invulnerable, fn(state) {
    assert unit_state.reading_of(state:) == Invulnerable
      as "a state whose spells are named invulnerability or immunity to all spells reads as invulnerable"
  })
  assert unit_state.reading_of(state: 19) == ImmuneToBeneficial
    as "state 19 is 'Immune (Beneficial)' (Spell4 83193)"
  let without = [0, 1, 2, 10, 23, 11, 12, 20, 21, 24, 100, -1]
  list.each(without, fn(state) {
    assert unit_state.reading_of(state:) == NoReading
      as "state 1 is Block, and 0, 2, 10, 23 and any number no row holds say nothing the server acts on"
  })
}

pub fn a_hostile_cast_is_refused_306_by_an_invulnerable_state_test() -> Nil {
  use <- owned_test.run(10_000)
  assert unit_state.cast_refusal(held: [6], beneficial: False)
    == Some(cast_result.TargetHostileInvulnerability)
    as "state 6 and a hostile cast give 306"
  assert unit_state.cast_refusal(held: [1, 14], beneficial: False)
    == Some(cast_result.TargetHostileInvulnerability)
    as "one invulnerable state among others is enough"
  assert cast_result.to_value(cast_result.TargetHostileInvulnerability) == 306
}

pub fn a_beneficial_cast_is_not_refused_by_an_invulnerable_state_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([6, 7, 8, 9, 13, 14, 15, 16, 17, 18, 22, 3, 4, 5], fn(state) {
    assert unit_state.cast_refusal(held: [state], beneficial: True) == None
      as "an invulnerable creature may still be helped (the issue's second acceptance condition)"
  })
}

pub fn a_beneficial_cast_is_refused_308_by_state_19_test() -> Nil {
  use <- owned_test.run(10_000)
  assert unit_state.cast_refusal(held: [19], beneficial: True)
    == Some(cast_result.TargetBeneficialInvulnerability)
  assert cast_result.to_value(cast_result.TargetBeneficialInvulnerability)
    == 308
}

pub fn a_hostile_cast_is_not_refused_by_state_19_test() -> Nil {
  use <- owned_test.run(10_000)
  assert unit_state.cast_refusal(held: [19], beneficial: False) == None
    as "state 19 is immune to beneficial casts only"
}

pub fn states_without_a_reading_refuse_nothing_and_order_does_not_matter_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([True, False], fn(beneficial) {
    assert unit_state.cast_refusal(held: [], beneficial:) == None
    assert unit_state.cast_refusal(held: [1, 23, 0, 2, 10], beneficial:) == None
      as "Block (1) and the states with no reading refuse nothing"
  })
  let held = [1, 19, 6, 23]
  list.each(
    [held, list.reverse(held), [6, 1, 23, 19], [23, 19, 1, 6]],
    fn(order) {
      assert unit_state.cast_refusal(held: order, beneficial: False)
        == Some(cast_result.TargetHostileInvulnerability)
      assert unit_state.cast_refusal(held: order, beneficial: True)
        == Some(cast_result.TargetBeneficialInvulnerability)
        as "the result does not depend on the order the states were held in"
    },
  )
}

pub fn no_state_gives_result_307_test() -> Nil {
  use <- owned_test.run(10_000)
  // `Spell.CodeEnumCastResult.306_308`: nothing the client's data says tells which state
  // gives 307, so the server names it and never sends it.
  assert cast_result.to_value(cast_result.TargetInvulnerableToOther) == 307
  list.each(int.range(from: -1, to: 31, with: [], run: list.prepend), fn(state) {
    list.each([True, False], fn(beneficial) {
      assert unit_state.cast_refusal(held: [state], beneficial:)
        != Some(cast_result.TargetInvulnerableToOther)
        as "no state of 0 to 30 gives 307"
    })
  })
}

pub fn a_creature_blocks_hostile_effects_only_while_holding_an_invulnerable_state_test() -> Nil {
  use <- owned_test.run(10_000)
  assert unit_state.blocks_hostile(held: [6])
  assert unit_state.blocks_hostile(held: [1, 22, 19])
  assert !unit_state.blocks_hostile(held: [])
    as "a creature that holds nothing blocks nothing"
  assert !unit_state.blocks_hostile(held: [1, 19, 23, 0, 2, 10])
    as "Block, the beneficial immunity and the states with no reading do not block a strike"
}
