//// Where a new character starts: WorldLocation2 row 50177, read from the
//// client's table when the server starts (Jim's decision on the world issue:
//// a stand-in until a retail record or a recording gives the start of each
//// CharacterCreation row). The row is world 3400, `Map\PreTutorialExile`,
//// at the position -5, -7.8, 0; the server stops at start when the row, or the
//// World row it names, is missing. The tests read the client's own files, so
//// they skip where `GENESIS_NO_CLIENT=1`.

import client_tables
import environment
import genesis_prime/character/starting_place
import genesis_prime/map/position.{Position}
import genesis_prime/table/loader/store.{RowMissing}
import genesis_prime/table/world
import genesis_prime/table/world_location2
import gleam/erlang/reference
import gleam/float
import owned_test
import unitest

/// The row every new character starts at.
const starting_location = 50_177

fn load(
  requirements requirements: List(store.Requirement),
) -> Result(store.Tables, store.LoadError) {
  store.load(
    under: reference.new(),
    from: client_tables.folder(),
    entries: [world.entry(), world_location2.entry()],
    requirements:,
  )
}

pub fn a_new_character_starts_at_world_location_50177_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  let assert Ok(tables) = load(requirements: [])
    as "the client's tables did not load"
  let assert Ok(row) = world_location2.get(tables, starting_location)
    as "WorldLocation2.tbl holds row 50177"
  let assert Ok(place) =
    starting_place.place(tables:, location_id: starting_location)
    as "the row gives a place"
  assert place.world_id == 3400
    as "WorldLocation2 row 50177: worldId 3400, which the World table names Map\\PreTutorialExile"
  assert place.world_zone_id == row.world_zone_id
    as "WorldLocation2 row 50177: the zone is the row's worldZoneId"
  assert place.position
    == Position(x: row.position0, y: row.position1, z: row.position2)
    as "WorldLocation2 row 50177: the position is the row's position0, position1 and position2"
  assert float.absolute_value(place.position.x -. -5.0) <. 0.05
    && float.absolute_value(place.position.y -. -7.8) <. 0.05
    && place.position.z == 0.0
    as "WorldLocation2 row 50177: the position is about -5, -7.8, 0 (the row holds -5.0278, -7.7771, 0)"
  let assert Ok(start_world) = world.get(tables, place.world_id)
    as "the World table holds the world the row names"
  assert start_world.asset_path == "Map\\PreTutorialExile"
    as "World row 3400 is Map\\PreTutorialExile"
}

pub fn a_location_the_table_does_not_hold_gives_no_place_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  let assert Ok(tables) = load(requirements: [])
    as "the client's tables did not load"
  assert starting_place.place(tables:, location_id: -1) == Error(Nil)
    as "a row the table does not hold is no place"
}

pub fn the_load_fails_when_the_starting_row_is_missing_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  let assert Error(RowMissing(
    from_table: _,
    column: _,
    to_table: "WorldLocation2",
    id: -1,
  )) = load(requirements: starting_place.requirements(location_id: -1))
    as "CLAUDE.md: game tables load once at start into named records; a missing row fails the load"
  Nil
}

pub fn the_load_passes_with_the_starting_row_the_table_holds_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  let assert Ok(_) =
    load(requirements: starting_place.requirements(
      location_id: starting_location,
    ))
    as "row 50177 and the World row it names are in the client's tables"
  Nil
}
