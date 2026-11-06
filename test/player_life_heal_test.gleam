//// A heal of a player's own shield (`genesis_prime/game/player_life` `shield_healed`), as
//// the pure rule it is. Expected values come from these places.
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

import character_tables
import genesis_prime/client_connection
import genesis_prime/game/hit
import genesis_prime/game/loadout
import genesis_prime/game/player_life.{
  type Effect, type Life, CancelTimer, OwnShield, StartTimer, ToClient,
  ToViewers,
}
import genesis_prime/game/rating
import genesis_prime/table/id.{ClassId}
import gleam/list
import gleam/option.{None}
import gleam/set
import owned_test
import player_life_support
import properties_support
import spawn_support

fn defence() -> hit.Defence {
  let tables = character_tables.shared()
  let assert Ok(loadout) =
    loadout.of(tables:, class_id: ClassId(1), faction_id: 166)
    as "a Warrior has a Dominion Novice set"
  player_life.defence(
    properties: properties_support.wearing(loadout:),
    level: 1,
    formulas: rating.formulas(tables:),
  )
}

fn struck(
  life life: Life,
  cast_id cast_id: Int,
  damage damage: Int,
) -> #(Life, List(Effect)) {
  player_life_support.struck(
    life:,
    defence: defence(),
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

/// The timers an effect list starts and cancels, in order.
fn timers(effects: List(Effect)) -> List(Effect) {
  list.filter(effects, fn(effect) {
    case effect {
      StartTimer(..) | CancelTimer(..) -> True
      ToClient(..)
      | ToViewers(..)
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

pub fn a_shield_heal_raises_the_shield_capped_at_its_maximum_and_tells_the_client_and_viewers_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(life, effects) =
    player_life.shield_healed(life: struck_to_400(), amount: 30)
  assert player_life.shield(life:) == 430 as "400 and 30"
  assert effects
    == [
      ToClient(OwnShield(shield: 430)),
      ToViewers(client_connection.Shield(shield: 430)),
    ]
    as "0x938 stat 20 to the player and to each viewer"
  let #(life, effects) = player_life.shield_healed(life:, amount: 60)
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
  let #(healed, effects) = player_life.shield_healed(life:, amount: 60)
  assert healed == life && effects == []
    as "a change that moves nothing is not told"
  let #(healed, effects) =
    player_life.shield_healed(life: struck_to_400(), amount: 0)
  assert player_life.shield(life: healed) == 400 && effects == []
    as "an amount of 0 moves nothing either"
}

pub fn a_shield_heal_on_a_dead_player_changes_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(dead, _) = struck(life: struck_to_400(), cast_id: 2, damage: 100_000)
  assert player_life.state(life: dead) == player_life.Dead
  let #(healed, effects) = player_life.shield_healed(life: dead, amount: 60)
  assert healed == dead && effects == []
    as "a dead player takes no change but coming back"
}

pub fn a_shield_heal_leaves_the_shield_clock_as_it_was_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(life, effects) =
    player_life.shield_healed(life: struck_to_400(), amount: 30)
  assert player_life.shield(life:) == 430 as "400 and 30"
  assert timers(effects) == []
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
