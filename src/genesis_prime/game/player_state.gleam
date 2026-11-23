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
import gleam/option.{type Option}

/// A player in sight, as its viewer's client holds it.
pub type PlayerState {
  PlayerState(
    alive: Bool,
    in_combat: Bool,
    held: List(HeldState),
    place: Option(Place),
    hit_radius: Float,
    disposition: Disposition,
    pvp_flagged: Bool,
    group_id: Int,
  )
}
