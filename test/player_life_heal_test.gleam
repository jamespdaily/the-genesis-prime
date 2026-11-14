//// A heal of a player's own shield or health (`genesis_prime/game/player_life` `healed`),
//// as the pure rule it is. Expected values come from these places.
//// - `Spell4Effects.effectType.10`: the client never changes the health on a heal
////   result either, so the server adds the amount to the health, capped at the most, and
////   sends it as 0x92f to the player and 0x937 to each viewer.
//// - `0x1405d8350` (the client's result of a heal): a heal whose target has property 111
////   (HealToShieldConversion) not 0 shows min(int(amount x property), max shield -
////   shield) as a HealShields event, and the heal's own amount lowered by it.
//// - `Spell4Effects.effectType.118`: the client never changes the shield on a heal
////   result, so the server adds the amount to the shield, capped at the most, and sends
////   the new shield as stat 20 of 0x938 (`opcode.0x938`): to the player's client and, as
////   the `Shield` news, to each viewer.
//// - The rule's "a change that moves nothing is not told": a heal on a full shield writes
////   nothing.
//// - A dead player takes no change but coming back (`player_life`'s dead state).
//// - Text 531855: the shield's reboot restarts only after a blow, so a heal leaves the
////   shield's clock as it was.
//// - A level-1 Warrior's defence (Armor 250: mitigation 0.75, the shield takes up to
////   0.625 of the mitigated blow, rounded half away from zero), as `player_life_test`
////   works it: a blow of 320 is mitigated to 80, of which the shield takes 50 and the
////   health 30, so 450 shield and 736 health leave 400 and 706. The shield's regeneration
////   is 0.25 of 450 each 500 ms after 2500 ms (`UnitProperty2.176`): a tick adds 112.

import cast_support
import genesis_prime/client_connection
import genesis_prime/game/effect_kind
import genesis_prime/game/player_life.{
  type Effect, type Life, OwnHealth, OwnShield, ToClient, ToViewers,
}
import genesis_prime/game/unit_properties.{type Properties}
import genesis_prime/table/id.{UnitProperty2Id}
import gleam/option.{None, Some}
import gleam/set
import owned_test
import player_life_support
import properties_support
import spawn_support

/// A level-1 player's properties at their defaults, in which both healing
/// multipliers are 1.0 (`UnitProperty2.damage_heal_multipliers`).
fn unmodified() -> Properties {
  properties_support.fresh(level: 1)
}

/// The properties with a modifier that makes `property` x into x * `factor`.
fn scaled(
  properties properties: Properties,
  property property: Int,
  factor factor: Float,
) -> Properties {
  properties_support.with_modifier(
    properties:,
    source: cast_support.source_of(cast_id: property, effect_id: 1900),
    modifier: unit_properties.Change(
      property: UnitProperty2Id(property),
      mode: 1,
      multiplier: factor,
      flat: 0.0,
      per_level: 0.0,
    ),
  )
}

fn struck(
  life life: Life,
  cast_id cast_id: Int,
  damage damage: Int,
) -> #(Life, List(Effect)) {
  player_life_support.struck(
    life:,
    defence: player_life_support.defence(),
    offence: spawn_support.dealing(
      offence: spawn_support.beast_attack().offence,
      damage:,
    ),
    cast_id:,
  )
}

/// A player of 736 health and 450 shield, fought by the Beast, struck by a blow of 320:
/// 706 health and 400 shield, with the shield's reboot running.
fn struck_to_400() -> Life {
  let #(life, _) =
    player_life.entering(
      saved: None,
      max_health: 736,
      shield: 450,
      regeneration: player_life_support.regeneration,
      place: player_life_support.place(),
    )
  let life =
    player_life.threatened(life:, unit_id: 7, creature_life: 3, gone: set.new()).0
  let #(life, _) = struck(life:, cast_id: 1, damage: 320)
  assert player_life.shield(life:) == 400
    as "the shield takes round(0.625 x 80) = 50 of the mitigated blow"
  life
}

pub fn a_shield_heal_raises_the_shield_capped_at_its_maximum_and_tells_the_client_and_viewers_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(life, effects) =
    player_life.healed(
      vital: effect_kind.Shield,
      life: struck_to_400(),
      amount: 30,
      properties: unmodified(),
    )
  assert player_life.shield(life:) == 430 as "400 and 30"
  assert effects
    == [
      ToClient(OwnShield(shield: 430)),
      ToViewers(client_connection.Shield(shield: 430)),
    ]
    as "0x938 stat 20 to the player and to each viewer"
  let #(life, effects) =
    player_life.healed(
      vital: effect_kind.Shield,
      life:,
      amount: 60,
      properties: unmodified(),
    )
  assert player_life.shield(life:) == 450
    as "430 and 60 is 490: the maximum is 450"
  assert effects
    == [
      ToClient(OwnShield(shield: 450)),
      ToViewers(client_connection.Shield(shield: 450)),
    ]
    as "the new shield is the capped one"
  assert player_life.health(life:) == 706
    as "a shield heal never touches the health"
}

pub fn a_shield_heal_on_a_full_shield_writes_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(life, _) =
    player_life.entering(
      saved: None,
      max_health: 736,
      shield: 450,
      regeneration: player_life_support.regeneration,
      place: player_life_support.place(),
    )
  let #(healed, effects) =
    player_life.healed(
      vital: effect_kind.Shield,
      life:,
      amount: 60,
      properties: unmodified(),
    )
  assert healed == life && effects == []
    as "a change that moves nothing is not told"
  let #(healed, effects) =
    player_life.healed(
      vital: effect_kind.Shield,
      life: struck_to_400(),
      amount: 0,
      properties: unmodified(),
    )
  assert player_life.shield(life: healed) == 400 && effects == []
    as "an amount of 0 moves nothing either"
}

pub fn a_shield_heal_on_a_dead_player_changes_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(dead, _) = struck(life: struck_to_400(), cast_id: 2, damage: 100_000)
  assert player_life.state(life: dead) == player_life.Dead
  let #(healed, effects) =
    player_life.healed(
      vital: effect_kind.Shield,
      life: dead,
      amount: 60,
      properties: unmodified(),
    )
  assert healed == dead && effects == []
    as "a dead player takes no change but coming back"
}

pub fn a_shield_heal_leaves_the_shield_clock_as_it_was_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(life, effects) =
    player_life.healed(
      vital: effect_kind.Shield,
      life: struck_to_400(),
      amount: 30,
      properties: unmodified(),
    )
  assert player_life.shield(life:) == 430 as "400 and 30"
  assert player_life_support.timers(effects) == []
    as "the reboot running since the blow is neither cancelled nor restarted (text 531855)"
  let #(life, tick) =
    player_life.timer_fired(life:, timer: player_life_support.shield_timer)
  assert player_life.shield(life:) == 450
    as "the reboot's first tick adds floor(450 x 0.25) = 112 to 430 and stops at the maximum"
  assert tick
    == [
      ToClient(OwnShield(shield: 450)),
      ToViewers(client_connection.Shield(shield: 450)),
    ]
    as "and the shield is full, so no next tick"
}

/// Jim's decision (issue 464, 2026-11-08): a heal is its amount times the healer's
/// HealingMultiplierOutgoing (162) times the target's HealingMultiplierIncoming (163);
/// the client reads neither (`UnitProperty2.damage_heal_multipliers`). The player heals
/// only itself, so both are its own. 400 of 450 shield and a heal of 40: the two
/// multipliers 1.5 and 0.5 give 30, so 430; 162 alone would give 60 (450, capped) and
/// 163 alone 20 (420).
pub fn self_heal_uses_healing_multipliers_test() -> Nil {
  use <- owned_test.run(60_000)
  let both =
    unmodified()
    |> scaled(property: 162, factor: 1.5)
    |> scaled(property: 163, factor: 0.5)
  let #(life, effects) =
    player_life.healed(
      vital: effect_kind.Shield,
      life: struck_to_400(),
      amount: 40,
      properties: both,
    )
  assert player_life.shield(life:) == 430 as "40 x 1.5 x 0.5 = 30 on 400"
  assert effects
    == [
      ToClient(OwnShield(shield: 430)),
      ToViewers(client_connection.Shield(shield: 430)),
    ]
    as "the shield told is the healed one"
  let #(life, _) =
    player_life.healed(
      vital: effect_kind.Shield,
      life: struck_to_400(),
      amount: 40,
      properties: scaled(properties: unmodified(), property: 163, factor: 0.5),
    )
  assert player_life.shield(life:) == 420 as "incoming 0.5 alone: 20"
  let #(life, _) =
    player_life.healed(
      vital: effect_kind.Shield,
      life: struck_to_400(),
      amount: 40,
      properties: scaled(properties: unmodified(), property: 162, factor: 0.5),
    )
  assert player_life.shield(life:) == 420 as "outgoing 0.5 alone: 20"
  let #(life, effects) =
    player_life.healed(
      vital: effect_kind.Shield,
      life: struck_to_400(),
      amount: 40,
      properties: scaled(properties: unmodified(), property: 163, factor: 0.0),
    )
  assert player_life.shield(life:) == 400 && effects == []
    as "a multiplier of 0 heals nothing and tells nothing"
}

/// The properties with HealToShieldConversion (111) set to `share`: the client reads it
/// as the share of a heal that goes to the shield (`0x1405d8350`, unit+0x93c); its default
/// is 0.
fn converting(share share: Float) -> Properties {
  properties_support.with_modifier(
    properties: unmodified(),
    source: cast_support.source_of(cast_id: 111, effect_id: 1900),
    modifier: unit_properties.Change(
      property: UnitProperty2Id(111),
      mode: 1,
      multiplier: 1.0,
      flat: share,
      per_level: 0.0,
    ),
  )
}

/// A player saved at `health` of 736, struck by a blow of 320 as `struck_to_400` is: the
/// blow takes 30 of the health and 50 of the shield, leaving 400 of 450 shield.
fn struck_from(health health: Int) -> Life {
  let #(life, _) =
    player_life.entering(
      saved: Some(health),
      max_health: 736,
      shield: 450,
      regeneration: player_life_support.regeneration,
      place: player_life_support.place(),
    )
  let life =
    player_life.threatened(life:, unit_id: 7, creature_life: 3, gone: set.new()).0
  let #(life, _) = struck(life:, cast_id: 1, damage: 320)
  assert player_life.shield(life:) == 400
    as "the shield takes round(0.625 x 80) = 50 of the mitigated blow"
  life
}

fn health_told(health health: Int) -> List(Effect) {
  [
    ToClient(OwnHealth(health:)),
    ToViewers(client_connection.Health(health:, dead: False)),
  ]
}

pub fn a_health_heal_raises_health_capped_and_tells_the_client_test() -> Nil {
  use <- owned_test.run(60_000)
  let life = struck_from(health: 600)
  assert player_life.health(life:) == 570 as "600 less the blow's 30"
  let #(life, effects) =
    player_life.healed(
      life:,
      vital: effect_kind.Health,
      amount: 100,
      properties: unmodified(),
    )
  assert player_life.health(life:) == 670 as "570 and 100"
  assert effects == health_told(health: 670)
    as "0x92f to the player and 0x937 to each viewer"
  assert player_life.shield(life:) == 400
    as "a health heal never touches the shield"
  assert player_life_support.timers(effects) == [] as "and starts no timer"
  let #(life, effects) =
    player_life.healed(
      life:,
      vital: effect_kind.Health,
      amount: 500,
      properties: unmodified(),
    )
  assert player_life.health(life:) == 736
    as "670 and 500 is 1170: the maximum is 736"
  assert effects == health_told(health: 736)
    as "the told health is the capped one"
  // 5 x 1.5 x 1.0 = 7.5, which rounds half away from zero to 8
  // (`UnitProperty2.damage_heal_multipliers`).
  let #(life, _) =
    player_life.healed(
      life: struck_from(health: 600),
      vital: effect_kind.Health,
      amount: 5,
      properties: scaled(properties: unmodified(), property: 162, factor: 1.5),
    )
  assert player_life.health(life:) == 578
    as "570 and round(7.5) = 8: the healing multipliers apply to a health heal as to a shield one"
}

pub fn a_health_heal_at_full_health_or_dead_writes_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(full, _) =
    player_life.entering(
      saved: None,
      max_health: 736,
      shield: 450,
      regeneration: player_life_support.regeneration,
      place: player_life_support.place(),
    )
  let #(healed, effects) =
    player_life.healed(
      life: full,
      vital: effect_kind.Health,
      amount: 60,
      properties: unmodified(),
    )
  assert healed == full && effects == []
    as "a change that moves nothing is not told"
  let #(healed, effects) =
    player_life.healed(
      life: struck_from(health: 600),
      vital: effect_kind.Health,
      amount: 0,
      properties: unmodified(),
    )
  assert player_life.health(life: healed) == 570 && effects == []
    as "an amount of 0 moves nothing either"
  let #(dead, _) = struck(life: struck_to_400(), cast_id: 2, damage: 100_000)
  assert player_life.state(life: dead) == player_life.Dead
  let #(healed, effects) =
    player_life.healed(
      life: dead,
      vital: effect_kind.Health,
      amount: 60,
      properties: unmodified(),
    )
  assert healed == dead && effects == []
    as "a dead player takes no change but coming back"
}

/// The client's split (`0x1405d8350`): for a heal of type 10 on a unit whose property 111
/// is not 0, converted = min(int(amount x p), max shield - shield) is shown as a
/// HealShields event and the heal's own amount is lowered by it. The server makes the
/// shield rise by `converted` and the health by the rest.
pub fn a_heal_with_shield_conversion_splits_between_shield_and_health_test() -> Nil {
  use <- owned_test.run(60_000)
  // Shield 430 of 450 (20 below), health 570 of 736: 0.5 of 100 is 50, of which the
  // shield has room for 20, and the other 80 go to the health.
  let #(life, _) =
    player_life.healed(
      life: struck_from(health: 600),
      vital: effect_kind.Shield,
      amount: 30,
      properties: unmodified(),
    )
  assert player_life.shield(life:) == 430
  let #(life, effects) =
    player_life.healed(
      life:,
      vital: effect_kind.Health,
      amount: 100,
      properties: converting(share: 0.5),
    )
  assert player_life.shield(life:) == 450
    as "20 to the shield, up to its maximum"
  assert player_life.health(life:) == 650 as "570 and the other 80"
  assert effects
    == [
      ToClient(OwnShield(shield: 450)),
      ToViewers(client_connection.Shield(shield: 450)),
      ToClient(OwnHealth(health: 650)),
      ToViewers(client_connection.Health(health: 650, dead: False)),
    ]
    as "stat 20 of 0x938 and the Shield news for the shield, then the health"
  // The client works the share with int(), which drops the fraction: 0.5 of 5 is 2.
  let #(life, _) =
    player_life.healed(
      life: struck_from(health: 600),
      vital: effect_kind.Health,
      amount: 5,
      properties: converting(share: 0.5),
    )
  assert player_life.shield(life:) == 402
    as "int(5 x 0.5) = 2 to the shield (rounding would give 3)"
  assert player_life.health(life:) == 573 as "570 and the other 3"
}

pub fn a_heal_with_shield_conversion_at_full_shield_all_goes_to_health_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(life, _) =
    player_life.entering(
      saved: Some(500),
      max_health: 736,
      shield: 450,
      regeneration: player_life_support.regeneration,
      place: player_life_support.place(),
    )
  let #(life, effects) =
    player_life.healed(
      life:,
      vital: effect_kind.Health,
      amount: 100,
      properties: converting(share: 0.5),
    )
  assert player_life.shield(life:) == 450
    as "max shield - shield is 0, so converted is 0"
  assert player_life.health(life:) == 600 as "and the whole 100 is health"
  assert effects == health_told(health: 600)
    as "no stat 20: the shield did not move"
}
