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
//// - An absorb pool (`Spell4Effects.effectType.29`) takes the damage types of its mask
////   (dataBits04: rows 42241 to 42243 'Absorbs X cutting damage' are damageType 1 with
////   mask 1, row 68969 'Water Shield' damageType 3 with mask 4; bit 1 Physical, 2 Tech,
////   4 Magic) before the shield and the health; the order, the oldest pool first and the
////   description's absorbed field holding the mitigated and the soaked part are the
////   server's choice (the effect type's gap).
//// - ShieldMitigationMax is 0.625 for a Novice (`player.level1_gear_properties`).

import genesis_prime/game/hit.{
  type Defence, type Offence, type Rolls, Blow, Defence, Deflected, Landed,
  Offence, Rolls,
}
import genesis_prime/game/unit_properties
import genesis_prime/message/combat_result
import genesis_prime/message/damage_type
import genesis_prime/table/id.{Spell4EffectsId}
import gleam/float
import gleam/int
import gleam/list
import owned_test
import player_life_support
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
    physical_taken: hit.as_dealt,
    tech_taken: hit.as_dealt,
    magic_taken: hit.as_dealt,
  )

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
          absorbs: [],
          health:,
          offence: player_life_support.offence_of(
            damage:,
            damage_type: 3,
            crit_chance: 0.1,
          ),
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
        absorbs: [],
        health: 100,
        offence: player_life_support.offence_of(
          damage: 18,
          damage_type: 3,
          crit_chance: 0.1,
        ),
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
      absorbs: [],
      health: 52,
      offence: player_life_support.offence_of(
        damage: 18,
        damage_type: 3,
        crit_chance: 0.1,
      ),
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
    Offence(
      ..player_life_support.offence_of(
        damage: 18,
        damage_type: 3,
        crit_chance: 0.1,
      ),
      strikethrough: 0.016,
    )
  assert hit.apply(
      shield: 0,
      absorbs: [],
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
      absorbs: [],
      health: 52,
      offence: player_life_support.offence_of(
        damage: 18,
        damage_type: 3,
        crit_chance: 0.1,
      ),
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
      absorbs: [],
      health: 52,
      offence: player_life_support.offence_of(
        damage: 20,
        damage_type: 3,
        crit_chance: 0.1,
      ),
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
        absorbs: [],
        health: 52,
        offence: player_life_support.offence_of(
          damage: 20,
          damage_type:,
          crit_chance: 0.1,
        ),
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
      absorbs: [],
      health: 52,
      offence: player_life_support.offence_of(
        damage: 18,
        damage_type: 3,
        crit_chance: 0.1,
      ),
      defence: beast,
      rolls: no_luck,
    )
  assert list.length(descriptions) == 1 && health == 34
    as "Creature2.73464.mitigation: a hit on it is its base value"
}

/// A pool of the cast `cast_id` with `left` and the damage types of `mask`.
fn pool(cast_id cast_id: Int, left left: Int, mask mask: Int) -> hit.Absorb {
  hit.Absorb(
    source: unit_properties.Source(
      cast_id:,
      effect_id: Spell4EffectsId(178_144),
    ),
    left:,
    mask:,
  )
}

/// A defence with the Novice's shield (ShieldMitigationMax 0.625) and no mitigation.
const shielded =
  Defence(
    deflect_chance: 0.0,
    crit_deflect_chance: 0.0,
    glance_chance: 0.0,
    glance_amount: 0.0,
    physical_mitigation: 0.0,
    tech_mitigation: 0.0,
    magic_mitigation: 0.0,
    shield_mitigation_max: 0.625,
    physical_taken: hit.as_dealt,
    tech_taken: hit.as_dealt,
    magic_taken: hit.as_dealt,
  )

/// A strike of Magic blows of these damages, with no crit chance.
fn strike_of(damages damages: List(Int)) -> hit.Offence {
  Offence(
    ..player_life_support.offence_of(
      damage: 0,
      damage_type: 3,
      crit_chance: 0.0,
    ),
    blows: list.map(damages, fn(damage) {
      Blow(
        spell4_effects_id: 62_159,
        damage_type: 3,
        damage:,
        delay_ms: 0,
        threat_multiplier: 1.0,
      )
    }),
  )
}

pub fn a_blow_is_taken_by_the_absorb_then_the_shields_share_of_the_rest_then_health_test() -> Nil {
  use <- owned_test.run(5000)
  // Worked by hand: a Magic blow of 90 after mitigation (no mitigation here, so the 90 is
  // the damage); a pool of 50 takes 50, leaving 40; the shield takes round(40 x 0.625) = 25
  // of the 100 it holds; the health takes the other 15.
  let assert Landed(descriptions: [description], health:, shield:, absorbs:, ..) =
    hit.apply(
      health: 100,
      shield: 100,
      absorbs: [pool(cast_id: 1, left: 50, mask: 7)],
      offence: strike_of(damages: [90]),
      defence: shielded,
      rolls: no_luck,
    )
  assert description.damage.absorbed == 0 + 50
    as "the description's absorbed is the mitigated part (0) and the soaked part (50)"
  assert description.damage.shield_absorbed == 25
  assert description.damage.health_damage_with_overkill == 15
  assert health == 85 && shield == 75
  assert absorbs == [] as "a pool used up is dropped"
  // With a Magic mitigation of 0.1 a blow of 100 is 90 after mitigation: 10 mitigated.
  let assert Landed(descriptions: [mitigated], ..) =
    hit.apply(
      health: 100,
      shield: 100,
      absorbs: [pool(cast_id: 1, left: 50, mask: 7)],
      offence: strike_of(damages: [100]),
      defence: Defence(..shielded, magic_mitigation: 0.1),
      rolls: no_luck,
    )
  assert mitigated.damage.absorbed == 10 + 50
    as "mitigated 10 and soaked 50 are both in the absorbed field"
  assert mitigated.damage.shield_absorbed == 25
    as "the shield's share is of the 40 the pool left: round(40 x 0.625)"
  assert mitigated.damage.health_damage_with_overkill == 15
}

pub fn a_blow_of_a_type_outside_the_mask_passes_the_absorb_test() -> Nil {
  use <- owned_test.run(5000)
  let blow_of = fn(damage_type, mask) {
    let assert Landed(descriptions: [description], absorbs:, ..) =
      hit.apply(
        health: 100,
        shield: 0,
        absorbs: [pool(cast_id: 1, left: 50, mask:)],
        offence: player_life_support.offence_of(
          damage: 20,
          damage_type:,
          crit_chance: 0.0,
        ),
        defence: hit.unprotected,
        rolls: no_luck,
      )
    #(
      description.damage.absorbed,
      description.damage.health_damage_with_overkill,
      list.map(absorbs, fn(absorb) { absorb.left }),
    )
  }
  assert blow_of(3, 1) == #(0, 20, [50])
    as "mask 1 (rows 42241 to 42243, 'cutting') is Physical alone: a Magic blow passes it"
  assert blow_of(1, 1) == #(20, 0, [30]) as "mask 1 soaks a Physical blow"
  assert blow_of(3, 4) == #(20, 0, [30])
    as "mask 4 (row 68969, 'Water Shield') soaks Magic"
  assert blow_of(2, 4) == #(0, 20, [50]) as "and passes a Tech blow"
  assert blow_of(2, 2) == #(20, 0, [30]) as "mask 2 soaks Tech"
  assert blow_of(1, 6) == #(0, 20, [50])
    as "mask 6 (Tech and Magic, 24 rows) passes Physical"
  assert blow_of(2, 7) == #(20, 0, [30])
    as "mask 7 (every type, 461 rows) soaks Tech"
}

pub fn the_oldest_absorb_soaks_first_and_the_next_takes_the_rest_test() -> Nil {
  use <- owned_test.run(5000)
  let pools = [
    pool(cast_id: 1, left: 30, mask: 7),
    pool(cast_id: 2, left: 50, mask: 7),
  ]
  let apply = fn(damage) {
    let assert Landed(descriptions: [description], health:, absorbs:, ..) =
      hit.apply(
        health: 100,
        shield: 0,
        absorbs: pools,
        offence: strike_of(damages: [damage]),
        defence: hit.unprotected,
        rolls: no_luck,
      )
    #(description.damage.absorbed, health, absorbs)
  }
  assert apply(20)
    == #(20, 100, [
      pool(cast_id: 1, left: 10, mask: 7),
      pool(cast_id: 2, left: 50, mask: 7),
    ])
    as "20 is taken by the oldest pool alone, which keeps 10"
  assert apply(60) == #(60, 100, [pool(cast_id: 2, left: 20, mask: 7)])
    as "60: the oldest gives its 30 and is dropped, the next gives 30 and keeps 20"
  assert apply(100) == #(80, 80, [])
    as "100: 30 and 50 soaked, both dropped, and the other 20 reaches the health"
  let assert Landed(absorbs:, ..) =
    hit.apply(
      health: 100,
      shield: 0,
      absorbs: [
        pool(cast_id: 1, left: 30, mask: 1),
        pool(cast_id: 2, left: 50, mask: 4),
      ],
      offence: strike_of(damages: [20]),
      defence: hit.unprotected,
      rolls: no_luck,
    )
  assert absorbs
    == [
      pool(cast_id: 1, left: 30, mask: 1),
      pool(cast_id: 2, left: 30, mask: 4),
    ]
    as "the oldest pool's mask does not hold Magic, so the next pool takes the blow"
}

pub fn an_absorb_used_up_by_one_blow_leaves_the_next_blow_of_the_strike_to_the_shield_test() -> Nil {
  use <- owned_test.run(5000)
  // A pool of 30 and a strike of two Magic blows of 30 and 40: the first is taken whole and
  // the pool is dropped; the second finds no pool: the shield takes round(40 x 0.625) = 25
  // and the health 15.
  let assert Landed(
    descriptions: [first, second],
    health:,
    shield:,
    absorbs:,
    ..,
  ) =
    hit.apply(
      health: 100,
      shield: 100,
      absorbs: [pool(cast_id: 1, left: 30, mask: 7)],
      offence: strike_of(damages: [30, 40]),
      defence: shielded,
      rolls: no_luck,
    )
  assert #(
      first.damage.absorbed,
      first.damage.shield_absorbed,
      first.damage.health_damage_with_overkill,
    )
    == #(30, 0, 0)
  assert #(
      second.damage.absorbed,
      second.damage.shield_absorbed,
      second.damage.health_damage_with_overkill,
    )
    == #(0, 25, 15)
  assert health == 85 && shield == 75 && absorbs == []
}

pub fn a_deflected_strike_leaves_the_absorbs_test() -> Nil {
  use <- owned_test.run(5000)
  assert hit.apply(
      health: 100,
      shield: 100,
      absorbs: [pool(cast_id: 1, left: 50, mask: 7)],
      offence: strike_of(damages: [90]),
      defence: Defence(..shielded, deflect_chance: 1.0),
      rolls: Rolls(..no_luck, deflect: 0.5),
    )
    == Deflected
    as "a deflect misses every blow of the strike, so no pool is touched: Deflected carries none"
}

/// What a strike gave a unit in the old rule's terms: for each blow its raw damage,
/// absorbed, shield absorbed, health damage and overkill, then the health and shield
/// left and whether a blow killed.
type Taken =
  #(List(#(Int, Int, Int, Int, Int)), Int, Int, Bool)

/// The hit rule as it was before it took a pool: the shield's share of a blow after
/// mitigation, then health. `share` rounds the shield's share, so a test can plant a
/// difference.
fn old_apply(
  health health: Int,
  shield shield: Int,
  offence offence: Offence,
  defence defence: Defence,
  rolls rolls: Rolls,
  share share: fn(Float) -> Int,
) -> Taken {
  let deflect_chance =
    float.max(0.0, defence.deflect_chance -. offence.strikethrough)
  case rolls.deflect <. deflect_chance {
    True -> #([], health, shield, False)
    False -> {
      let crit_chance =
        float.max(0.0, offence.crit_chance -. defence.crit_deflect_chance)
      let critical = rolls.crit <. crit_chance
      let glancing = rolls.glance <. defence.glance_chance
      let #(done, left, shield_left, killed) =
        list.fold(offence.blows, #([], health, shield, False), fn(so_far, blow) {
          let #(done, left, shield_left, killed) = so_far
          let raw = case critical {
            True ->
              float.round(int.to_float(blow.damage) *. offence.crit_severity)
            False -> blow.damage
          }
          let glanced = case glancing {
            True -> float.round(int.to_float(raw) *. defence.glance_amount)
            False -> 0
          }
          let after_glance = raw - glanced
          let mitigation = case damage_type.from_value(blow.damage_type) {
            damage_type.Physical -> defence.physical_mitigation
            damage_type.Tech -> defence.tech_mitigation
            damage_type.Magic -> defence.magic_mitigation
            damage_type.Heal
            | damage_type.HealShields
            | damage_type.Fall
            | damage_type.Suffocate
            | damage_type.Other(..) -> 0.0
          }
          let taken =
            float.round(int.to_float(after_glance) *. { 1.0 -. mitigation })
          let shielded =
            int.min(
              shield_left,
              share(int.to_float(taken) *. defence.shield_mitigation_max),
            )
          let to_health = taken - shielded
          let kills = left > 0 && to_health >= left
          #(
            [
              #(
                raw,
                after_glance - taken,
                shielded,
                to_health,
                int.max(0, to_health - left),
              ),
              ..done
            ],
            int.max(0, left - to_health),
            shield_left - shielded,
            killed || kills,
          )
        })
      #(list.reverse(done), left, shield_left, killed)
    }
  }
}

/// What `hit.apply` with no pool gives, in the old rule's terms.
fn new_apply(
  health health: Int,
  shield shield: Int,
  offence offence: Offence,
  defence defence: Defence,
  rolls rolls: Rolls,
) -> Taken {
  case hit.apply(health:, shield:, absorbs: [], offence:, defence:, rolls:) {
    Deflected -> #([], health, shield, False)
    Landed(descriptions:, health: left, shield: shield_left, absorbs:, killed:) -> {
      assert absorbs == [] as "no pool in, none out"
      #(
        list.map(descriptions, fn(description) {
          let damage = description.damage
          #(
            damage.raw_damage,
            damage.absorbed,
            damage.shield_absorbed,
            damage.health_damage_with_overkill,
            damage.overkill,
          )
        }),
        left,
        shield_left,
        killed,
      )
    }
  }
}

/// A strike and a defence drawn from the ranges a player or a creature holds.
type Drawn {
  Drawn(
    health: Int,
    shield: Int,
    damages: List(Int),
    damage_type: Int,
    mitigation: Float,
    shield_max: Float,
    glance_amount: Float,
    rolls: Rolls,
  )
}

fn thousandths(from low: Int, to high: Int) -> qcheck.Generator(Float) {
  qcheck.map(qcheck.bounded_int(from: low, to: high), fn(thousandths) {
    int.to_float(thousandths) /. 1000.0
  })
}

fn drawn_cases() -> qcheck.Generator(Drawn) {
  qcheck.map(
    qcheck.tuple4(
      qcheck.tuple3(
        qcheck.bounded_int(from: 1, to: 300),
        qcheck.bounded_int(from: 0, to: 300),
        qcheck.list_from(qcheck.bounded_int(from: 0, to: 200)),
      ),
      qcheck.tuple3(
        qcheck.bounded_int(from: 1, to: 3),
        thousandths(from: 0, to: 900),
        thousandths(from: 0, to: 900),
      ),
      thousandths(from: 0, to: 500),
      qcheck.tuple3(
        thousandths(from: 0, to: 999),
        thousandths(from: 0, to: 999),
        thousandths(from: 0, to: 999),
      ),
    ),
    fn(parts) {
      let #(held, kinds, glance_amount, rolled) = parts
      Drawn(
        health: held.0,
        shield: held.1,
        damages: held.2,
        damage_type: kinds.0,
        mitigation: kinds.1,
        shield_max: kinds.2,
        glance_amount:,
        rolls: Rolls(crit: rolled.0, deflect: rolled.1, glance: rolled.2),
      )
    },
  )
}

/// Whether the old rule, rounding the shield's share with `share`, and the new rule with
/// no pool agree on the drawn case.
fn agree(drawn drawn: Drawn, share share: fn(Float) -> Int) -> Bool {
  let offence =
    Offence(
      blows: list.map(drawn.damages, fn(damage) {
        Blow(
          spell4_effects_id: 62_159,
          damage_type: drawn.damage_type,
          damage:,
          delay_ms: 0,
          threat_multiplier: 1.0,
        )
      }),
      crit_chance: 0.3,
      crit_severity: 1.5,
      strikethrough: 0.0,
    )
  let defence =
    Defence(
      deflect_chance: 0.2,
      crit_deflect_chance: 0.0,
      glance_chance: 0.3,
      glance_amount: drawn.glance_amount,
      physical_mitigation: drawn.mitigation,
      tech_mitigation: drawn.mitigation,
      magic_mitigation: drawn.mitigation,
      shield_mitigation_max: drawn.shield_max,
      physical_taken: hit.as_dealt,
      tech_taken: hit.as_dealt,
      magic_taken: hit.as_dealt,
    )
  old_apply(
    health: drawn.health,
    shield: drawn.shield,
    offence:,
    defence:,
    rolls: drawn.rolls,
    share:,
  )
  == new_apply(
    health: drawn.health,
    shield: drawn.shield,
    offence:,
    defence:,
    rolls: drawn.rolls,
  )
}

pub fn with_no_absorb_the_hit_rule_gives_what_it_gave_before_test() -> Nil {
  use <- owned_test.run(60_000)
  qcheck.given(drawn_cases(), fn(drawn) {
    assert agree(drawn:, share: float.round)
      as "every health, shield, strike, defence and roll gives the old rule's outcome"
  })
}

pub fn the_comparison_with_the_old_rule_fails_on_a_planted_difference_test() -> Nil {
  use <- owned_test.run(60_000)
  // The old rule with the shield's share truncated instead of rounded: some drawn case
  // must tell it from the new rule, or the comparison above could not fail.
  let differs =
    list.any([1, 2, 3, 5, 8, 13, 21, 34], fn(damage) {
      !agree(
        drawn: Drawn(
          health: 300,
          shield: 300,
          damages: [damage],
          damage_type: 3,
          mitigation: 0.0,
          shield_max: 0.625,
          glance_amount: 0.0,
          rolls: Rolls(crit: 0.9, deflect: 0.9, glance: 0.9),
        ),
        share: float.truncate,
      )
    })
  assert differs as "a blow of 1 gives a share of 0.625: rounded 1, truncated 0"
}
