//// A player's health and shield regenerating (`genesis_prime/game/player_life`), as
//// the pure rule it is: state and input in, new state and effects out, with the two
//// timers driven by hand. Expected values come from these places.
//// - The client sends the player nothing for either: it predicts none, so every
////   change is the server's message (`regen.client`). Health is 0x92f to the player
////   and 0x937 to its viewers, the shield 0x938 of stat 20 to both
////   (`opcode.0x92f`, `opcode.0x937`, `opcode.0x938`).
//// - Health regenerates "slowly out of combat" (text 149418), so it stops in combat
////   and with death; its rate is the server's choice, 2.5% of the maximum each
////   500 ms, scaled by HealthRegenMultiplier, UnitProperty2 8, default 1.0
////   (`UnitProperty2.176`). A tick adds `max(1, floor(max x 0.025 x multiplier))`,
////   worked by hand below: 736 gives floor(18.4) = 18, 20 gives floor(0.5) = 0
////   which is raised to 1, and 736 at a multiplier of 2.0 gives floor(36.8) = 36,
////   at 0.5 floor(9.2) = 9.
//// - The shield gains `floor(max_shield x ShieldRegenPct)` each ShieldTickTime
////   (text 531859), starting ShieldRebootTime after the last damage (text 531855),
////   in or out of combat: 450 x 0.25 = 112.5 gives 112. The values planted are the
////   UnitProperty2 defaults, 0.25 for 176, 500 for 177 and 2500 for 178
////   (`UnitProperty2.176`); a player's real ones are its shield item's.
//// - A level-1 Warrior's defence and the Beast's 12 are those of `player_life_test`
////   (Armor 250: mitigation 0.75, the shield takes up to 0.625 of the mitigated
////   blow, rounded half away from zero). A blow of 1000 is mitigated to 250, of
////   which the shield takes round(156.25) = 156 and the health 94: 450 left 294,
////   736 left 642.
//// - The timer ids 8 (health) and 9 (shield) are the connection's free ids above
////   the class resource's 4 to 7.

import character_tables
import genesis_prime/client_connection
import genesis_prime/game/hit.{Rolls}
import genesis_prime/game/loadout
import genesis_prime/game/player_life.{
  type Effect, type Life, CancelTimer, OwnCombatState, OwnHealth, OwnShield,
  Regeneration, ShieldRegeneration, StartTimer, ToClient, ToViewers,
}
import genesis_prime/game/rating
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell
import genesis_prime/step.{TimerId}
import genesis_prime/table/id.{ClassId}
import genesis_prime/world_map/map_id.{MapId}
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import message_support
import owned_test
import spawn_support

const health_timer = TimerId(8)

const shield_timer = TimerId(9)

/// The rule's numbers as the tests plant them: a fortieth of the maximum each
/// 500 ms, a multiplier of 1.0, a shield regenerating 0.25 of its maximum each
/// 500 ms after 2500 ms.
const regeneration =
  Regeneration(
    health_fraction: 0.025,
    health_multiplier: 1.0,
    health_tick_ms: 500,
    shield: Some(
      ShieldRegeneration(percent: 0.25, reboot_ms: 2500, tick_ms: 500),
    ),
  )

const rolls = Rolls(crit: 0.5, deflect: 0.0, glance: 0.0)

const own_unit = 20

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

fn defence() -> hit.Defence {
  let tables = character_tables.shared()
  let assert Ok(loadout) =
    loadout.of(tables:, class_id: ClassId(1), faction_id: 166)
    as "a Warrior has a Dominion Novice set"
  player_life.defence(loadout:, level: 1, formulas: rating.formulas(tables:))
}

/// The Beast's strike, its every blow dealing `damage`.
fn blow(cast_id cast_id: Int, damage damage: Int) -> strike_tell.Tell {
  strike_tell.Strike(
    key: strike_tell.Key(cast_id:, phase: 0, unit_id: own_unit),
    from: beast(),
    striker: strike_tell.CreatureStriker,
    offence: spawn_support.dealing(
      offence: spawn_support.beast_attack().offence,
      damage:,
    ),
    controls: [],
  )
}

fn struck(
  life life: Life,
  cast_id cast_id: Int,
  damage damage: Int,
) -> #(Life, List(Effect)) {
  player_life.struck(
    life:,
    defence: defence(),
    strike: blow(cast_id:, damage:),
    rolls:,
    place: place(),
  )
}

/// The player entering at `saved` of 736 health and 450 shield, and what its
/// entry asks.
fn entering(saved saved: option.Option(Int)) -> #(Life, List(Effect)) {
  player_life.entering(saved:, max_health: 736, shield: 450, regeneration:)
}

fn fought_by_the_beast(life life: Life) -> Life {
  player_life.threatened(life:, unit_id: 7, creature_life: 3, gone: set.new()).0
}

/// The timers an effect list starts and cancels, in order.
fn timers(effects: List(Effect)) -> List(Effect) {
  list.filter(effects, fn(effect) {
    case effect {
      StartTimer(..) | CancelTimer(..) -> True
      ToClient(..)
      | ToViewers(..)
      | player_life.Answer(..)
      | player_life.StreamTo(..)
      | player_life.EndCasts
      | player_life.GoToHolocrypt -> False
    }
  })
}

/// The health tick: the timer fires.
fn ticked(life life: Life) -> #(Life, List(Effect)) {
  player_life.timer_fired(life:, timer: health_timer)
}

// ---- 1 and 2: the health tick ----

pub fn out_of_combat_and_below_the_max_a_health_tick_adds_its_share_and_tells_the_player_and_its_viewers_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(life, entry) = entering(saved: Some(700))
  assert entry == [StartTimer(timer: health_timer, after_ms: 500)]
    as "below the maximum and out of combat, the first tick is 500 ms away"
  let #(life, effects) = ticked(life:)
  assert player_life.health(life:) == 718 as "700 and floor(736 x 0.025) = 18"
  assert effects
    == [
      ToClient(OwnHealth(health: 718)),
      ToViewers(client_connection.Health(health: 718, dead: False)),
      StartTimer(timer: health_timer, after_ms: 500),
    ]
    as "0x92f to the player, 0x937 to each viewer, and the next tick while below the maximum"
  let #(life, _) = ticked(life:)
  assert player_life.health(life:) == 736 as "700, 18, 18 is 736: the maximum"
}

pub fn a_health_tick_adds_at_least_1_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(life, _) =
    player_life.entering(
      saved: Some(10),
      max_health: 20,
      shield: 0,
      regeneration:,
    )
  let #(life, _) = ticked(life:)
  assert player_life.health(life:) == 11
    as "floor(20 x 0.025) = 0 is raised to 1"
}

pub fn a_player_at_the_max_arms_no_health_tick_test() -> Nil {
  use <- owned_test.run(60_000)
  assert entering(saved: None).1 == [] as "full health: nothing to regenerate"
  assert entering(saved: Some(1000)).1 == []
    as "a saved health above the maximum enters at the maximum"
}

pub fn health_never_goes_above_the_max_and_the_last_tick_tops_it_up_exactly_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(life, _) = entering(saved: Some(730))
  let #(life, effects) = ticked(life:)
  assert player_life.health(life:) == 736
    as "6 short: the tick of 18 stops at the maximum"
  assert effects
    == [
      ToClient(OwnHealth(health: 736)),
      ToViewers(client_connection.Health(health: 736, dead: False)),
    ]
    as "the player is full: no next tick"
  let #(after, more) = ticked(life:)
  assert after == life && more == []
    as "a tick that fires after the player is full changes nothing"
}

// ---- 3: combat ----

pub fn in_combat_no_health_tick_runs_leaving_combat_arms_it_and_entering_combat_cancels_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(life, _) = entering(saved: Some(700))
  let #(life, threat) =
    player_life.threatened(life:, unit_id: 7, creature_life: 3, gone: set.new())
  assert timers(threat) == [CancelTimer(timer: health_timer)]
    as "the first fighter stops the health tick"
  let #(still, none) = ticked(life:)
  assert still == life && none == []
    as "a tick already on its way when combat began changes nothing"
  let #(life, second) =
    player_life.threatened(life:, unit_id: 9, creature_life: 4, gone: set.new())
  assert timers(second) == [] as "a second fighter has nothing left to cancel"
  let #(life, one_left) = player_life.released(life:, unit_id: 7)
  assert timers(one_left) == [] as "a fighter is left: still in combat"
  let #(life, last) = player_life.released(life:, unit_id: 9)
  assert last
    == [
      ToClient(OwnCombatState(in_combat: False)),
      ToViewers(client_connection.CombatState(in_combat: False)),
      StartTimer(timer: health_timer, after_ms: 500),
    ]
    as "the last release clears the flag and arms the health tick"
  let #(life, _) = ticked(life:)
  assert player_life.health(life:) == 718
}

pub fn leaving_combat_at_full_health_arms_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let life = fought_by_the_beast(life: entering(saved: None).0)
  let #(_, released) = player_life.released(life:, unit_id: 7)
  assert timers(released) == [] as "nothing to regenerate"
}

// ---- 4: death ----

pub fn the_dead_regenerate_neither_and_coming_back_arms_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(life, _) = entering(saved: Some(5))
  let #(life, first) = struck(life:, cast_id: 1, damage: 12)
  assert player_life.health(life:) == 4 as "Armor 250: the health takes 1 of 12"
  assert timers(first) == [StartTimer(timer: shield_timer, after_ms: 2500)]
    as "the blow arms the shield's reboot; the health tick armed at entry runs on"
  let #(dead, killing) = struck(life:, cast_id: 2, damage: 100_000)
  assert player_life.state(life: dead) == player_life.Dead
  assert timers(killing)
    == [CancelTimer(timer: health_timer), CancelTimer(timer: shield_timer)]
    as "death cancels the health tick and the shield's clock"
  let #(still, none) = ticked(life: dead)
  assert still == dead && none == []
    as "a health tick that fires after the death changes nothing"
  let #(still, none) = player_life.timer_fired(life: dead, timer: shield_timer)
  assert still == dead && none == [] as "nor does a shield tick"
  let assert Ok(#(alive, back)) =
    player_life.take(
      life: dead,
      message: player_life.ResurrectionChosen,
      body: message_support.choice_body(unit_id: own_unit, choice: 1, value: 0),
      unit_id: own_unit,
    )
  assert player_life.health(life: alive) == 736
    && player_life.shield(life: alive) == 450
  assert timers(back) == [] as "coming back is full: nothing to arm"
}

// ---- 5: the shield's reboot ----

pub fn a_blow_arms_the_shield_for_the_reboot_time_and_a_second_blow_pushes_it_back_test() -> Nil {
  use <- owned_test.run(60_000)
  let life = fought_by_the_beast(life: entering(saved: None).0)
  let #(life, first) = struck(life:, cast_id: 1, damage: 12)
  assert timers(first) == [StartTimer(timer: shield_timer, after_ms: 2500)]
    as "ShieldRebootTime from the blow"
  let #(life, second) = struck(life:, cast_id: 2, damage: 12)
  assert timers(second)
    == [
      CancelTimer(timer: shield_timer),
      StartTimer(timer: shield_timer, after_ms: 2500),
    ]
    as "a blow before it fires starts the reboot again"
  assert player_life.shield(life:) == 446 as "450 less 2 and 2"
}

pub fn a_blow_that_changes_neither_shield_nor_health_leaves_the_shields_clock_test() -> Nil {
  use <- owned_test.run(60_000)
  let life = fought_by_the_beast(life: entering(saved: None).0)
  let #(life, _) = struck(life:, cast_id: 1, damage: 12)
  let #(_, effects) = struck(life:, cast_id: 2, damage: 0)
  assert timers(effects) == []
    as "a blow of 0 lowers nothing: the reboot is not pushed back"
}

// ---- 6: the shield's tick ----

pub fn after_the_reboot_each_tick_adds_its_share_in_combat_too_until_full_test() -> Nil {
  use <- owned_test.run(60_000)
  let life = fought_by_the_beast(life: entering(saved: None).0)
  let #(life, hit) = struck(life:, cast_id: 1, damage: 1000)
  assert player_life.shield(life:) == 294 && player_life.health(life:) == 642
    as "1000 mitigated to 250: the shield takes 156, the health 94"
  assert timers(hit) == [StartTimer(timer: shield_timer, after_ms: 2500)]
    && !list.contains(
      timers(hit),
      StartTimer(timer: health_timer, after_ms: 500),
    )
    as "in combat no health tick runs, and the shield waits out its reboot"
  let #(life, first) = player_life.timer_fired(life:, timer: shield_timer)
  assert player_life.shield(life:) == 406 as "294 and floor(450 x 0.25) = 112"
  assert first
    == [
      ToClient(OwnShield(shield: 406)),
      ToViewers(client_connection.Shield(shield: 406)),
      StartTimer(timer: shield_timer, after_ms: 500),
    ]
    as "0x938 stat 20 to the player and its viewers, then a tick later again"
  assert player_life.in_combat(life:) as "still in combat"
  let #(life, last) = player_life.timer_fired(life:, timer: shield_timer)
  assert player_life.shield(life:) == 450 as "406 and 112 stops at the maximum"
  assert last
    == [
      ToClient(OwnShield(shield: 450)),
      ToViewers(client_connection.Shield(shield: 450)),
    ]
    as "full: no next tick"
  let #(after, none) = player_life.timer_fired(life:, timer: shield_timer)
  assert after == life && none == []
    as "a shield tick that fires after the shield is full changes nothing"
}

// ---- 7: entry ----

pub fn a_player_entering_below_its_max_health_out_of_combat_starts_regenerating_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(life, entry) = entering(saved: Some(500))
  assert entry == [StartTimer(timer: health_timer, after_ms: 500)]
  assert !player_life.in_combat(life:) as "a player enters out of combat"
  let #(life, _) = ticked(life:)
  assert player_life.health(life:) == 518
}

// ---- 8: the multiplier ----

pub fn a_health_regen_multiplier_other_than_1_scales_the_tick_test() -> Nil {
  use <- owned_test.run(60_000)
  let tick_with = fn(multiplier) {
    let #(life, _) =
      player_life.entering(
        saved: Some(500),
        max_health: 736,
        shield: 450,
        regeneration: Regeneration(
          ..regeneration,
          health_multiplier: multiplier,
        ),
      )
    player_life.health(life: ticked(life:).0)
  }
  assert tick_with(2.0) == 536 as "floor(736 x 0.025 x 2.0) = 36"
  assert tick_with(0.5) == 509 as "floor(736 x 0.025 x 0.5) = 9"
}

// ---- 10: the timers ----

pub fn the_life_rule_owns_timer_ids_8_and_9_and_leaving_cancels_the_running_ones_test() -> Nil {
  use <- owned_test.run(60_000)
  assert player_life.owns(timer: TimerId(8))
    && player_life.owns(timer: TimerId(9))
  assert !player_life.owns(timer: TimerId(7))
    && !player_life.owns(timer: TimerId(10))
    as "the class resource has 4 to 7"
  let #(life, _) = entering(saved: Some(500))
  assert player_life.left(life:) == [health_timer]
    as "only the health tick runs"
  let #(life, _) = struck(life:, cast_id: 1, damage: 12)
  assert player_life.left(life:) == [health_timer, shield_timer]
    as "the health tick and the shield's reboot"
  let #(full, _) = entering(saved: None)
  assert player_life.left(life: full) == [] as "none runs at full health"
}

pub fn a_player_with_no_shield_item_has_no_shield_clock_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(life, _) =
    player_life.entering(
      saved: None,
      max_health: 736,
      shield: 450,
      regeneration: Regeneration(..regeneration, shield: None),
    )
  let #(life, hit) =
    struck(life: fought_by_the_beast(life:), cast_id: 1, damage: 1000)
  assert timers(hit) == [] as "no shield item: no reboot to wait for"
  assert player_life.left(life:) == []
  let #(after, none) = player_life.timer_fired(life:, timer: shield_timer)
  assert after == life && none == [] as "a stray shield timer changes nothing"
}
