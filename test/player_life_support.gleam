//// What the tests of a player's life (`genesis_prime/game/player_life`) share: the numbers
//// the player regenerates by, the Beast that strikes it, the place it stands and a strike
//// on it.

import character_tables
import genesis_prime/game/hit.{type Defence, type Offence, Rolls}
import genesis_prime/game/loadout
import genesis_prime/game/player_life.{
  type Effect, type Life, CancelTimer, Regeneration, ShieldRegeneration,
  StartTimer, ToClient, ToViewers,
}
import genesis_prime/game/rating
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell
import genesis_prime/step.{TimerId}
import genesis_prime/table/id.{ClassId}
import genesis_prime/world_map/map_id.{MapId}
import gleam/list
import gleam/option.{Some}
import properties_support

/// The shield's regeneration timer: the connection's free id 9.
pub const shield_timer = TimerId(9)

/// The rule's numbers as the tests plant them: a fortieth of the maximum each 500 ms, a
/// multiplier of 1.0, a shield regenerating 0.25 of its maximum each 500 ms after 2500 ms.
pub const regeneration =
  Regeneration(
    health_fraction: 0.025,
    health_multiplier: 1.0,
    health_tick_ms: 500,
    shield: Some(
      ShieldRegeneration(percent: 0.25, reboot_ms: 2500, tick_ms: 500),
    ),
  )

/// Rolls a level-1 player's defence never reads: deflect, crit deflect and glance are 0,
/// and the Beast's offence has no crit chance.
pub const rolls = Rolls(crit: 0.5, deflect: 0.0, glance: 0.0)

/// The player's unit in these rules: the unit the Beast's strikes name.
pub const own_unit = 20

/// The Beast that strikes: unit 7, life 3.
pub fn beast() -> step.Address {
  step.Creature(
    map: MapId(world_id: 3460, instance: 0),
    incarnation: 1,
    unit_id: 7,
    life: 3,
  )
}

/// Where the player stands.
pub fn place() -> Place {
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

/// The Beast's strike of cast `cast_id` with this offence on the player's `life`, on
/// `rolls`.
pub fn struck(
  life life: Life,
  defence defence: Defence,
  offence offence: Offence,
  cast_id cast_id: Int,
) -> #(Life, List(Effect)) {
  player_life.struck(
    life:,
    defence:,
    strike: strike_tell.Strike(
      key: strike_tell.Key(cast_id:, phase: 0, unit_id: own_unit),
      from: beast(),
      striker: strike_tell.CreatureStriker,
      offence:,
      controls: [],
    ),
    rolls:,
    place: place(),
  )
}

/// A level 1 Dominion Warrior's defence, from the client's novice set.
pub fn defence() -> hit.Defence {
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

/// The effects that start or cancel a timer, in order.
pub fn timers(effects: List(Effect)) -> List(Effect) {
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
