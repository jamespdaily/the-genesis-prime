//// A unit's hit radius: the body size the client measures a unit's edge by, which
//// an area counts when it decides who a spell strikes
//// (genesis_prime/game/area `Placement`).
////
//// ```
//// a creature: Creature2DisplayInfo.hitRadius x its scale ─┐
//// a player:   Race.hitRadius of its race                  ─┴─▶ the radius, read when the tables load
//// neither row: 0
//// ```
////
//// - **A creature's** is its display row's hitRadius times the unit's scale
////   (`unit.hit_radius`, `0x14047a940`).
//// - **A player's** is the hitRadius of its race's Race row, 1.2 for each of the
////   eight player races; a race with no row has radius 0 (`0x14022d500`).
//// - **The scale** is `unit_scale`, 1.0: the client's scale is its model's, and where
////   that is set (Creature2DisplayInfo.scale, which is 1.0 in 13,370 of 13,948 rows,
////   or Creature2.modelScale, 1.0 in 41,616 of 56,369 rows) is not read.

import genesis_prime/table/creature2_display_info
import genesis_prime/table/id.{RaceId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/race
import gleam/result

/// The scale a creature's radius is multiplied by: 1.0 for every creature, since the
/// source of the client's unit scale is not read (the module's doc comment).
const unit_scale = 1.0

/// The hit radius of a creature shown with the display row.
pub fn of_creature(
  display display: creature2_display_info.Creature2DisplayInfo,
) -> Float {
  display.hit_radius *. unit_scale
}

/// The hit radius of a player of the race (a `Race` id): its row's hitRadius, or 0 for
/// a race with no row.
pub fn of_player(
  tables tables: table_store.Tables,
  race_id race_id: Int,
) -> Float {
  race.get(tables:, id: RaceId(race_id))
  |> result.map(fn(row) { row.hit_radius })
  |> result.unwrap(0.0)
}
