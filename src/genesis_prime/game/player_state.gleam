//// What a press at another player judges of that player, as the caster's client was told
//// of it: the picture a connection keeps of each player in sight.
////
//// ```
//// the player's 0x262 (health stat, position, race, faction, PvP flags, group) ─▶ of_appeared
//// its Health, Died, CameBack, CombatState, crowd-control and Moving news ─▶ the connection's picture changes
//// the press ─▶ genesis_prime/game/cast/press_target `judge` ─▶ a refusal or none
//// ```
////
//// - **The state is the viewer's copy.** It changes only by news the viewer takes, so a
////   press is judged by what the caster's own client shows (`opcode.0x9d.target_checks`).
//// - **The health** is the health stat of the 0x262 (stat 0) and its Base Health (property 7,
////   the value `Unit:GetMaxHealth` reads, `0x1404584b0`), kept by the owner's `Health` and
////   `PropertiesChanged` news. A gear change tells each viewer that news too
////   (genesis_prime/game/connection/properties `rebased`), so the copy is one news behind at
////   worst.
//// - **The place** is the last position command's x, y and z (none before one), in the
////   viewer's world and zone: the client measures the range by the unit's movement height
////   less its own lift (`0x1403b2240`, `unit.ground_lift`).
//// - **The hit radius** is the Race row's: a player's 0x262 has display id 0 and a
////   disguise changes item visuals, not the display (`hit_radius.of_playing`).
//// - **The disposition** is the viewer's faction's toward the player's (`GetUnitDispositionTo`
////   `0x14045a950`, with no duel and no threat entry between players).
//// - **The PvP flag** is bit 0 of the 0x262's flags (`IsUnitPvpFlagged`, `0x1403b48b0`) and the
////   group id the 0x262's; a change of either while the player is in sight reaches no viewer.

import genesis_prime/game/faction_level.{type Disposition}
import genesis_prime/game/held_state.{type HeldState}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/unit_properties
import genesis_prime/message/float32
import genesis_prime/message/unit_property.{type UnitProperty}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/result

/// A player in sight, as its viewer's client holds it.
pub type PlayerState {
  PlayerState(
    alive: Bool,
    /// The health stat the viewer's client holds (stat 0).
    health: Int,
    /// The maximum health the viewer's client holds (property 7, BaseHealth).
    maximum_health: Int,
    in_combat: Bool,
    held: List(HeldState),
    place: Option(Place),
    hit_radius: Float,
    disposition: Disposition,
    pvp_flagged: Bool,
    group_id: Int,
  )
}

/// The health a player's copy misses: its maximum less its health, 0 for a player at full
/// health and for a copy whose health the news left above a maximum it has not yet heard of.
pub fn missing_health(state state: PlayerState) -> Int {
  int.max(state.maximum_health - state.health, 0)
}

/// The Base Health (property 7) value of the properties a 0x262 or a 0x93a carries, rounded,
/// or `Error(Nil)` when none holds it or its bits are not a finite float.
pub fn base_health_of(
  properties properties: List(UnitProperty),
) -> Result(Int, Nil) {
  use property <- result.try(
    list.find(properties, fn(property) {
      property.property_id == unit_properties.base_health.value
    }),
  )
  float32.of_column(number: property.value) |> result.map(float.round)
}
