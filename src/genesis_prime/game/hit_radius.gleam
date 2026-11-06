//// A creature's hit radius: the body size the client measures a unit's edge by,
//// which an area counts when it decides who a spell strikes
//// (genesis_prime/game/area `Placement`).
////
//// - **A creature's** is its Creature2DisplayInfo row's hitRadius times the unit's
////   scale (`unit.hit_radius`, `0x14047a940`).
//// - **A player's** would be its race's Race hitRadius (1.2 for the eight player
////   races); no area strikes a player, so nothing reads it and it is not loaded.
//// - **The scale** is `unit_scale`, 1.0: the client's scale is its model's, and where
////   that is set (Creature2DisplayInfo.scale, which is 1.0 in 13,370 of 13,948 rows,
////   or Creature2.modelScale, 1.0 in 41,616 of 56,369 rows) is not read.

import genesis_prime/table/creature2_display_info

/// The scale a creature's radius is multiplied by: 1.0 for every creature, since the
/// source of the client's unit scale is not read (the module's doc comment).
const unit_scale = 1.0

/// The hit radius of a creature shown with the display row.
pub fn of_creature(
  display display: creature2_display_info.Creature2DisplayInfo,
) -> Float {
  display.hit_radius *. unit_scale
}
