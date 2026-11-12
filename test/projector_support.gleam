//// What the tests of the projectors share: the rows of the eight landings the migration
//// seeds, the landings they select to over the client's fixture tables, and the
//// landings of no rows, which a connection made for another test is given.

import character_tables
import genesis_prime/game/projector.{type Landings, Row}

/// The eight rows: each projector for each faction, with the objective that asks for it
/// and the WorldLocation2 row it lands at.
pub fn rows() -> List(projector.Row) {
  [
    Row(
      creature_id: 73_735,
      faction_enum: 0,
      objective_id: 21_325,
      world_location2_id: 51_615,
    ),
    Row(
      creature_id: 73_735,
      faction_enum: 1,
      objective_id: 21_356,
      world_location2_id: 51_615,
    ),
    Row(
      creature_id: 73_741,
      faction_enum: 0,
      objective_id: 21_344,
      world_location2_id: 51_617,
    ),
    Row(
      creature_id: 73_741,
      faction_enum: 1,
      objective_id: 21_377,
      world_location2_id: 51_617,
    ),
    Row(
      creature_id: 73_743,
      faction_enum: 0,
      objective_id: 21_373,
      world_location2_id: 51_616,
    ),
    Row(
      creature_id: 73_743,
      faction_enum: 1,
      objective_id: 21_376,
      world_location2_id: 51_616,
    ),
    Row(
      creature_id: 73_745,
      faction_enum: 0,
      objective_id: 21_298,
      world_location2_id: 51_658,
    ),
    Row(
      creature_id: 73_745,
      faction_enum: 1,
      objective_id: 21_311,
      world_location2_id: 51_657,
    ),
  ]
}

/// The landings of those rows over the client's fixture tables.
pub fn landings() -> Landings {
  let assert Ok(landings) =
    projector.select(rows: rows(), tables: character_tables.content_tables())
    as "each row names a creature, a landing in world 3460 and an objective the fixture tables hold"
  landings
}

/// The landings of no rows: no creature is a projector.
pub fn none() -> Landings {
  let assert Ok(none) =
    projector.select(rows: [], tables: character_tables.content_tables())
    as "no rows select"
  none
}
