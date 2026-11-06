//// The absorb pools of a player's life (`genesis_prime/game/player_life` `absorb_started`,
//// `absorb_ended`, `struck`), as the pure rule it is. Expected values come from these
//// places.
//// - `opcode.0x938` and `0x14064fb40`: stat 22 of 0x938 is the unit's absorption, written
////   to the player's own client and, as the `Absorption` news, to each viewer.
//// - `Spell4Effects.effectType.29`: a pool takes damage before the shield and the health;
////   the client has no class for the effect, so the sum of the pools is the server's to
////   send at the start, after each blow that soaks and at the end. Row 178144 (Spectral
////   Form): 164 at level 1 (`player.level1_gear_properties`, GameFormula 1266); row 183643:
////   45 ('Granted 45 Absorb', text 581159).
//// - Server choices, stated in the module's doc: the order of the writes at a blow (stat
////   22, then stat 20, then the health), the pools dropped with stat 22 = 0 before the
////   death state, one pool for each source (a later start of the same source refills the
////   pool and keeps its place in the order), an end for a source holding no pool writes
////   nothing, and a blow wholly soaked counts as damage taken but does not restart the
////   shield's reboot (text 531855: the reboot restarts after a blow that lowers shield or
////   health).
//// - The shield takes round(rest x 0.625) of a blow (ShieldMitigationMax 0.625,
////   `player.level1_gear_properties`), rounded half away from zero (the hit rule's doc).
//// A Magic blow here has no mitigation: the defence is `hit.unprotected` with the shield's
//// 0.625.

import genesis_prime/client_connection
import genesis_prime/game/hit.{type Defence, Blow, Defence, Offence, Rolls}
import genesis_prime/game/player_life.{
  type Effect, type Life, OwnAbsorption, OwnDeathState, OwnHealth, OwnShield,
  Regeneration, ShieldRegeneration, StartTimer, ToClient, ToViewers,
}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell
import genesis_prime/game/unit_properties.{Source}
import genesis_prime/step.{TimerId}
import genesis_prime/table/id.{Spell4EffectsId}
import genesis_prime/world_map/map_id.{MapId}
import gleam/list
import gleam/option.{None, Some}
import owned_test

const shield_timer = TimerId(9)

const regeneration =
  Regeneration(
    health_fraction: 0.025,
    health_multiplier: 1.0,
    health_tick_ms: 500,
    shield: Some(
      ShieldRegeneration(percent: 0.25, reboot_ms: 2500, tick_ms: 500),
    ),
  )

const own_unit = 20

const rolls = Rolls(crit: 0.5, deflect: 0.0, glance: 0.0)

fn beast() -> step.Address {
  step.Creature(
    map: MapId(world_id: 3460, instance: 0),
    incarnation: 1,
    unit_id: 7,
    life: 3,
  )
}

fn place() -> Place {
  let assert Ok(place) =
    start_place.place(
      world_id: 3460,
      world_zone_id: 5967,
      x: 0.0,
      y: 0.0,
      z: 0.0,
      facing: start_place.unturned,
    )
    as "world 3460 is a world"
  place
}

/// The defence of a player whose shield takes 0.625 of a blow and that mitigates nothing.
fn defence() -> Defence {
  Defence(..hit.unprotected, shield_mitigation_max: 0.625)
}

/// A player of 736 health and 450 shield, alive.
fn player() -> Life {
  player_life.entering(
    saved: None,
    max_health: 736,
    shield: 450,
    regeneration:,
    place: place(),
  ).0
}

/// A blow of `damage` of the damage type `damage_type`, with no crit chance, on the rolls
/// of a strike that crits, glances and deflects nothing.
fn struck(
  life life: Life,
  damage damage: Int,
  damage_type damage_type: Int,
) -> #(Life, List(Effect)) {
  player_life.struck(
    life:,
    defence: defence(),
    strike: strike_tell.Strike(
      key: strike_tell.Key(cast_id: 1, phase: 0, unit_id: own_unit),
      from: beast(),
      striker: strike_tell.CreatureStriker,
      offence: Offence(
        blows: [
          Blow(
            spell4_effects_id: 62_159,
            damage_type:,
            damage:,
            delay_ms: 0,
            threat_multiplier: 1.0,
          ),
        ],
        crit_chance: 0.0,
        crit_severity: 1.5,
        strikethrough: 0.0,
      ),
      controls: [],
    ),
    rolls:,
    place: place(),
  )
}

/// The effect of the cast `cast_id`'s Absorption row 178144.
fn source(cast_id cast_id: Int) -> unit_properties.Source {
  Source(cast_id:, effect_id: Spell4EffectsId(178_144))
}

fn started(
  life life: Life,
  cast_id cast_id: Int,
  amount amount: Int,
  mask mask: Int,
) -> #(Life, List(Effect)) {
  player_life.absorb_started(life:, source: source(cast_id:), amount:, mask:)
}

/// The writes of an effect list to the player's client and to its viewers, in order.
fn written(effects effects: List(Effect)) -> List(Effect) {
  list.filter(effects, fn(effect) {
    case effect {
      ToClient(..) | ToViewers(..) -> True
      StartTimer(..)
      | player_life.CancelTimer(..)
      | player_life.Answer(..)
      | player_life.StreamTo(..)
      | player_life.DamageTaken
      | player_life.CombatLeft
      | player_life.EndCasts
      | player_life.GoToHolocrypt
      | player_life.TellMap(..) -> False
    }
  })
}

/// The sum of the pools, as the client and viewers are told it.
fn sum_told(sum sum: Int) -> List(Effect) {
  [
    ToClient(OwnAbsorption(absorption: sum)),
    ToViewers(client_connection.Absorption(absorption: sum)),
  ]
}

pub fn an_entry_holds_no_absorb_test() -> Nil {
  use <- owned_test.run(5000)
  assert player_life.absorption(life: player()) == 0
    as "the pools die with the connection: an entry holds none"
}

pub fn an_absorb_start_tells_the_client_and_viewers_the_sum_test() -> Nil {
  use <- owned_test.run(5000)
  let #(life, effects) =
    started(life: player(), cast_id: 1, amount: 164, mask: 7)
  assert effects == sum_told(sum: 164)
    as "row 178144 at level 1 is 164: stat 22 to the player and the viewers"
  assert player_life.absorption(life:) == 164
  let #(life, effects) = started(life:, cast_id: 2, amount: 45, mask: 7)
  assert effects == sum_told(sum: 209)
    as "a second pool of 45 (row 183643): the sum 164 + 45 is stat 22"
  assert player_life.absorption(life:) == 209
}

pub fn an_absorb_end_tells_the_new_sum_and_an_end_for_a_pool_not_held_writes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(life, _) = started(life: player(), cast_id: 1, amount: 164, mask: 7)
  let #(life, _) = started(life:, cast_id: 2, amount: 45, mask: 7)
  let #(life, effects) =
    player_life.absorb_ended(life:, source: source(cast_id: 1))
  assert effects == sum_told(sum: 45) as "the pool of cast 1 goes: 209 less 164"
  assert player_life.absorption(life:) == 45
  let #(unchanged, effects) =
    player_life.absorb_ended(life:, source: source(cast_id: 1))
  assert effects == [] && unchanged == life
    as "the same end again finds no pool: nothing is written"
  let #(unchanged, effects) =
    player_life.absorb_ended(
      life:,
      source: Source(cast_id: 1, effect_id: Spell4EffectsId(1)),
    )
  assert effects == [] && unchanged == life
    as "a source of another effect holds no pool"
  let #(life, _) = struck(life:, damage: 45, damage_type: 3)
  assert player_life.absorption(life:) == 0 as "the blow used cast 2's pool up"
  let #(unchanged, effects) =
    player_life.absorb_ended(life:, source: source(cast_id: 2))
  assert effects == [] && unchanged == life
    as "an end for a pool used up writes nothing"
}

pub fn a_blow_on_an_absorb_tells_stat_22_then_stat_20_then_health_test() -> Nil {
  use <- owned_test.run(5000)
  let #(life, _) = started(life: player(), cast_id: 1, amount: 164, mask: 7)
  // Worked by hand: a Magic blow of 200: the pool takes 164 and is used up; of the other 36
  // the shield takes round(36 x 0.625) = round(22.5) = 23 and the health 13.
  let #(life, effects) = struck(life:, damage: 200, damage_type: 3)
  assert list.take(written(effects:), 6)
    == list.flatten([
      sum_told(sum: 0),
      [
        ToClient(OwnShield(shield: 427)),
        ToViewers(client_connection.Shield(shield: 427)),
      ],
      [
        ToClient(OwnHealth(health: 723)),
        ToViewers(client_connection.Health(health: 723, dead: False)),
      ],
    ])
    as "stat 22, then stat 20, then the health"
  assert player_life.absorption(life:) == 0
  assert player_life.shield(life:) == 427 && player_life.health(life:) == 723
}

pub fn a_blow_taken_wholly_by_the_absorb_counts_as_damage_taken_but_does_not_restart_the_shield_reboot_test() -> Nil {
  use <- owned_test.run(5000)
  let #(life, _) = started(life: player(), cast_id: 1, amount: 164, mask: 7)
  let #(life, effects) = struck(life:, damage: 100, damage_type: 3)
  assert list.contains(effects, player_life.DamageTaken)
    as "the stealth rule hears of a blow that took only the absorb"
  assert list.any(effects, fn(effect) {
      case effect {
        StartTimer(timer:, ..) -> timer == shield_timer
        ToClient(..)
        | ToViewers(..)
        | player_life.CancelTimer(..)
        | player_life.Answer(..)
        | player_life.StreamTo(..)
        | player_life.DamageTaken
        | player_life.CombatLeft
        | player_life.EndCasts
        | player_life.GoToHolocrypt
        | player_life.TellMap(..) -> False
      }
    })
    == False
    as "the shield and the health did not fall, so the reboot does not restart (text 531855)"
  assert player_life.absorption(life:) == 64
  assert player_life.shield(life:) == 450 && player_life.health(life:) == 736
  // The same blow on a shield that it lowers does start the reboot.
  let #(_, effects) = struck(life: player(), damage: 100, damage_type: 3)
  assert list.any(effects, fn(effect) {
    case effect {
      StartTimer(timer:, ..) -> timer == shield_timer
      ToClient(..)
      | ToViewers(..)
      | player_life.CancelTimer(..)
      | player_life.Answer(..)
      | player_life.StreamTo(..)
      | player_life.DamageTaken
      | player_life.CombatLeft
      | player_life.EndCasts
      | player_life.GoToHolocrypt
      | player_life.TellMap(..) -> False
    }
  })
    as "with no pool the same blow lowers the shield and restarts the reboot"
}

pub fn a_death_drops_every_absorb_and_tells_zero_before_the_death_state_test() -> Nil {
  use <- owned_test.run(5000)
  // A pool of mask 1 (Physical) does not take the Magic killing blow, so it is still held
  // when the player dies.
  let #(life, _) = started(life: player(), cast_id: 1, amount: 164, mask: 1)
  let #(dead, effects) = struck(life:, damage: 100_000, damage_type: 3)
  assert player_life.state(life: dead) == player_life.Dead
  assert player_life.absorption(life: dead) == 0 as "every pool is dropped"
  let writes = written(effects:)
  let at = fn(wanted) {
    let assert Ok(#(index, _)) =
      list.index_map(writes, fn(effect, index) { #(index, effect) })
      |> list.find(fn(entry) { entry.1 == wanted })
    index
  }
  assert at(ToClient(OwnHealth(health: 0)))
    < at(ToClient(OwnAbsorption(absorption: 0)))
    as "stat 22 = 0 follows the killing blow's health"
  assert at(ToClient(OwnAbsorption(absorption: 0)))
    < at(ToClient(OwnDeathState(dead: True)))
    as "and comes before the death state"
  assert at(ToViewers(client_connection.Absorption(absorption: 0)))
    < at(ToViewers(client_connection.Died))
  let #(unchanged, effects) =
    player_life.absorb_ended(life: dead, source: source(cast_id: 1))
  assert effects == [] && unchanged == dead
    as "the cast rule's death ends find no pool and write nothing"
  // With no pool held a death tells no stat 22.
  let #(_, effects) = struck(life: player(), damage: 100_000, damage_type: 3)
  assert !list.contains(
    written(effects:),
    ToClient(OwnAbsorption(absorption: 0)),
  )
    as "stat 22 = 0 is written only when the sum was above 0"
}

pub fn the_same_absorb_started_again_is_refilled_test() -> Nil {
  use <- owned_test.run(5000)
  let #(life, _) = started(life: player(), cast_id: 1, amount: 50, mask: 7)
  let #(life, _) = started(life:, cast_id: 2, amount: 60, mask: 7)
  let #(life, effects) = started(life:, cast_id: 1, amount: 70, mask: 7)
  assert effects == sum_told(sum: 130)
    as "cast 1's pool is 70 now, not 50 and 70: 70 and 60 are 130"
  assert player_life.absorption(life:) == 130
  // The refilled pool keeps its place: it soaks first. A blow of 80 takes cast 1's 70 and
  // 10 of cast 2's 60, so cast 2's pool is the one left, with 50.
  let #(life, _) = struck(life:, damage: 80, damage_type: 3)
  assert player_life.absorption(life:) == 50
  let #(_, effects) =
    player_life.absorb_ended(life:, source: source(cast_id: 2))
  assert effects == sum_told(sum: 0)
    as "cast 2's pool is the one that held the 50"
  let #(life, _) = started(life: player(), cast_id: 1, amount: 50, mask: 7)
  let #(life, effects) = started(life:, cast_id: 1, amount: 0, mask: 7)
  assert effects == sum_told(sum: 0) && player_life.absorption(life:) == 0
    as "a pool refilled to 0 is not held"
}

pub fn two_blows_in_one_millisecond_each_see_the_pools_the_other_left_test() -> Nil {
  use <- owned_test.run(5000)
  let #(life, _) = started(life: player(), cast_id: 1, amount: 100, mask: 7)
  let #(life, first) = struck(life:, damage: 60, damage_type: 3)
  assert list.take(written(effects: first), 2) == sum_told(sum: 40)
  let #(life, second) = struck(life:, damage: 60, damage_type: 3)
  assert list.take(written(effects: second), 2) == sum_told(sum: 0)
    as "the second blow finds the 40 the first left: it soaks 40 and the shield takes round(20 x 0.625) = 13 of the other 20"
  assert player_life.shield(life:) == 437 && player_life.health(life:) == 729
}

pub fn a_blow_after_the_absorbs_end_goes_to_the_shield_and_health_test() -> Nil {
  use <- owned_test.run(5000)
  let #(life, _) = started(life: player(), cast_id: 1, amount: 100, mask: 7)
  let #(life, _) = player_life.absorb_ended(life:, source: source(cast_id: 1))
  let #(life, effects) = struck(life:, damage: 100, damage_type: 3)
  assert list.take(written(effects:), 2)
    == [
      ToClient(OwnShield(shield: 387)),
      ToViewers(client_connection.Shield(shield: 387)),
    ]
    as "no stat 22: the shield takes round(100 x 0.625) = 63 and the health 37"
  assert player_life.health(life:) == 699
}

pub fn an_end_and_a_blow_in_one_millisecond_are_taken_in_arrival_order_test() -> Nil {
  use <- owned_test.run(5000)
  let #(life, _) = started(life: player(), cast_id: 1, amount: 100, mask: 7)
  // The blow first: the pool soaks 60, then its end takes the other 40.
  let #(after_blow, _) = struck(life:, damage: 60, damage_type: 3)
  let #(after_blow, ended) =
    player_life.absorb_ended(life: after_blow, source: source(cast_id: 1))
  assert ended == sum_told(sum: 0)
    && player_life.shield(life: after_blow) == 450
  // The end first: the shield and the health take the blow.
  let #(ended_first, _) =
    player_life.absorb_ended(life:, source: source(cast_id: 1))
  let #(ended_first, _) = struck(life: ended_first, damage: 60, damage_type: 3)
  assert player_life.shield(life: ended_first) == 450 - 38
    as "round(60 x 0.625) = 38"
}

pub fn a_pool_started_on_a_dead_player_is_not_held_test() -> Nil {
  use <- owned_test.run(5000)
  let #(dead, _) = struck(life: player(), damage: 100_000, damage_type: 3)
  let #(after, effects) = started(life: dead, cast_id: 1, amount: 164, mask: 7)
  assert after == dead && effects == []
    as "a dead player takes no change but coming back"
}
