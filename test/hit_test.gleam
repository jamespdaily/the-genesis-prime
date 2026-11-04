//// The hit rule (`genesis_prime/game/hit`), run as the pure rule it is. Expected
//// values come from these places.
//// - The rule's doc comment: a deflect lands when the deflect roll is below the
////   target's deflect chance less the attacker's strikethrough; a critical hit when the
////   crit roll is below the crit chance less the target's critical deflect, at the
////   severity; a glance when the glance roll is below the target's glance chance, taking
////   the glance amount; then mitigation of the damage type; health stays in [0, max];
////   killed exactly at 0; the overkill is the damage beyond the health before.
//// - The Virtual Battle Beast at level 1: deflect chance 0.016, crit deflect 0, glance
////   chance 0, no mitigation (`Creature2.73464.crit_deflect_glance`,
////   `Creature2.73464.mitigation`).
//// - A Novice's crit severity is 1.5 (`0x140463e80`).
//// - Combat results: Hit 2 and Critical 1 (`GameLib.CodeEnumCombatResult`).

import genesis_prime/game/hit.{Blow, Defence, Deflected, Landed, Offence, Rolls}
import genesis_prime/message/combat_result
import gleam/int
import gleam/list
import owned_test
import qcheck

const beast =
  Defence(
    deflect_chance: 0.016,
    crit_deflect_chance: 0.0,
    glance_chance: 0.0,
    glance_amount: 0.0,
    physical_mitigation: 0.0,
    tech_mitigation: 0.0,
    magic_mitigation: 0.0,
    shield_mitigation_max: 0.0,
  )

fn offence(damage damage: Int, damage_type damage_type: Int) -> hit.Offence {
  Offence(
    blows: [
      Blow(
        spell4_effects_id: 62_159,
        damage_type:,
        damage:,
        delay_ms: 0,
        threat_multiplier: 1.0,
      ),
    ],
    crit_chance: 0.1,
    crit_severity: 1.5,
    strikethrough: 0.0,
  )
}

const no_luck = Rolls(crit: 0.9, deflect: 0.9, glance: 0.9)

pub fn the_seed_bytes_make_three_fractions_of_two_to_the_32_test() -> Nil {
  use <- owned_test.run(5000)
  assert hit.rolls_of(bytes: <<
      0:size(32),
      2_147_483_648:size(32),
      3_221_225_472:size(32),
    >>)
    == Ok(Rolls(crit: 0.0, deflect: 0.5, glance: 0.75))
  assert hit.rolls_of(bytes: <<1, 2, 3>>) == Error(Nil)
    as "any other length is no roll"
}

pub fn health_stays_in_range_and_killed_is_set_exactly_at_zero_test() -> Nil {
  use <- owned_test.run(60_000)
  qcheck.given(
    qcheck.tuple2(
      qcheck.bounded_int(from: 1, to: 200),
      qcheck.bounded_int(from: 1, to: 300),
    ),
    fn(drawn) {
      let #(health, damage) = drawn
      let assert Landed(descriptions: [description], health: left, killed:, ..) =
        hit.apply(
          shield: 0,
          health:,
          offence: offence(damage:, damage_type: 3),
          defence: hit.unprotected,
          rolls: no_luck,
        )
      assert left == int.max(0, health - damage) as "health stays in [0, max]"
      assert killed == { damage >= health }
        as "killed exactly when the blow takes the health to 0"
      assert description.damage.overkill == int.max(0, damage - health)
        as "the overkill is the damage beyond the health before the blow"
    },
  )
}

pub fn a_crit_lands_only_when_its_roll_is_below_the_crit_chance_test() -> Nil {
  use <- owned_test.run(5000)
  let struck = fn(roll) {
    let assert Landed(descriptions: [description], ..) =
      hit.apply(
        shield: 0,
        health: 100,
        offence: offence(damage: 18, damage_type: 3),
        defence: hit.unprotected,
        rolls: Rolls(..no_luck, crit: roll),
      )
    description.damage
  }
  assert struck(0.0999).combat_result == combat_result.Critical
  assert struck(0.0999).raw_damage == 27 as "18 x severity 1.5"
  assert struck(0.1).combat_result == combat_result.Hit
    as "a roll equal to the chance does not crit"
  assert struck(0.1).raw_damage == 18
}

pub fn a_deflect_lands_when_its_roll_is_below_the_targets_chance_test() -> Nil {
  use <- owned_test.run(5000)
  let by = fn(roll) {
    hit.apply(
      shield: 0,
      health: 52,
      offence: offence(damage: 18, damage_type: 3),
      defence: beast,
      rolls: Rolls(..no_luck, deflect: roll),
    )
  }
  assert by(0.015) == Deflected as "the Beast deflects 1.6%"
  assert by(0.016) != Deflected
}

pub fn strikethrough_takes_off_the_deflect_chance_and_crit_deflect_the_crit_chance_test() -> Nil {
  use <- owned_test.run(5000)
  let piercing =
    Offence(..offence(damage: 18, damage_type: 3), strikethrough: 0.016)
  assert hit.apply(
      shield: 0,
      health: 52,
      offence: piercing,
      defence: beast,
      rolls: Rolls(..no_luck, deflect: 0.0),
    )
    != Deflected
    as "0.016 deflect less 0.016 strikethrough is 0"
  let assert Landed(descriptions: [description], ..) =
    hit.apply(
      shield: 0,
      health: 52,
      offence: offence(damage: 18, damage_type: 3),
      defence: Defence(..hit.unprotected, crit_deflect_chance: 0.1),
      rolls: Rolls(..no_luck, crit: 0.0),
    )
  assert description.damage.combat_result == combat_result.Hit
    as "0.1 crit chance less 0.1 critical deflect is 0"
}

pub fn a_glance_takes_the_glance_amount_off_the_damage_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Landed(descriptions: [description], health:, ..) =
    hit.apply(
      shield: 0,
      health: 52,
      offence: offence(damage: 20, damage_type: 3),
      defence: Defence(
        ..hit.unprotected,
        glance_chance: 1.0,
        glance_amount: 0.25,
      ),
      rolls: no_luck,
    )
  assert description.damage.glance == 5 && health == 37
    as "a quarter of 20 is taken off: 15 reaches the health"
}

pub fn mitigation_takes_its_damage_types_share_off_the_damage_test() -> Nil {
  use <- owned_test.run(5000)
  let armoured = Defence(..hit.unprotected, physical_mitigation: 0.5)
  let taken = fn(damage_type) {
    let assert Landed(descriptions: [description], ..) =
      hit.apply(
        shield: 0,
        health: 52,
        offence: offence(damage: 20, damage_type:),
        defence: armoured,
        rolls: no_luck,
      )
    #(
      description.damage.health_damage_with_overkill,
      description.damage.absorbed,
    )
  }
  assert taken(1) == #(10, 10) as "physical: half of 20 is absorbed"
  assert taken(3) == #(20, 0) as "magic has no mitigation here"
}

pub fn the_beasts_numbers_pass_a_blow_through_unchanged_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Landed(descriptions: descriptions, health:, killed: False, ..) =
    hit.apply(
      shield: 0,
      health: 52,
      offence: offence(damage: 18, damage_type: 3),
      defence: beast,
      rolls: no_luck,
    )
  assert list.length(descriptions) == 1 && health == 34
    as "Creature2.73464.mitigation: a hit on it is its base value"
}
