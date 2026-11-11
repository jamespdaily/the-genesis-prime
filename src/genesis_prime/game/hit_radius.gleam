//// A creature's hit radius: the body size the client measures a unit's edge by,
//// which an area counts when it decides who a spell strikes
//// (genesis_prime/game/area `Placement`).
////
//// - **A creature's** is its Creature2DisplayInfo row's hitRadius times the unit's
////   scale (`unit.hit_radius`, `0x14047a940`).
//// - **A player's** is its race's Race hitRadius (1.2 for the eight player races),
////   which a quest giver's reach counts (`of_player`) and which a creature's area counts
////   when it decides which players it strikes (`of_playing`).
//// - **The scale** is `unit_scale`, 1.0: the client's scale is its model's, and where
////   that is set (Creature2DisplayInfo.scale, which is 1.0 in 13,370 of 13,948 rows,
////   or Creature2.modelScale, 1.0 in 41,616 of 56,369 rows) is not read.

import genesis_prime/game/start_place
import genesis_prime/table/creature2_display_info
import genesis_prime/table/id.{type RaceId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/race
import gleam/list
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

/// The hit radius of a player of the race: its Race row's hitRadius, or an error when
/// the table has no row for it.
pub fn of_player(
  tables tables: table_store.Tables,
  race_id race_id: RaceId,
) -> Result(Float, Nil) {
  race.get(tables:, id: race_id) |> result.map(fn(row) { row.hit_radius })
}

/// The hit radius of a player in the game: its race has a Race row, which the load
/// checked (`requirements`), so a missing one crashes.
pub fn of_playing(
  tables tables: table_store.Tables,
  race_id race_id: RaceId,
) -> Float {
  let assert Ok(radius) = of_player(tables:, race_id:)
    as "hit_radius.requirements fails the load when a playable race has no Race row"
  radius
}

/// The load's check that every playable race has a Race row, so a client without one
/// fails the server's start.
pub fn requirements() -> List(table_store.Requirement) {
  [
    table_store.Requirement(
      from_table: "the server's playable races",
      column: "Race id",
      to_table: "Race",
      missing: fn(tables) {
        start_place.playable_races()
        |> list.filter(fn(race_id) {
          result.is_error(race.get(tables:, id: race_id))
        })
        |> list.map(fn(race_id) { race_id.value })
      },
    ),
  ]
}
