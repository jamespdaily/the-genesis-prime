//// Where a new character starts: one WorldLocation2 row of the client's
//// table, read from the loaded tables. The server's one starting row stands in
//// until a retail record or a recording gives the start of each
//// CharacterCreation row; the row's id is a setting made where the server is
//// wired, so no rule holds a coordinate.

import genesis_prime/character/character.{type Place, Place}
import genesis_prime/map/position.{Position}
import genesis_prime/table/loader/store.{type Tables}
import genesis_prime/table/world
import genesis_prime/table/world_location2

/// The place of a WorldLocation2 row, or an error when the table has no such
/// row: the row's world, its zone and its position (position0, position1 and
/// position2).
pub fn place(
  tables tables: Tables,
  location_id location_id: Int,
) -> Result(Place, Nil) {
  case world_location2.get(tables, location_id) {
    Ok(row) ->
      Ok(Place(
        world_id: row.world_id,
        world_zone_id: row.world_zone_id,
        position: Position(x: row.position0, y: row.position1, z: row.position2),
      ))
    Error(Nil) -> Error(Nil)
  }
}

/// The rows the server requires of the tables so that every new character has
/// a place: the WorldLocation2 row, and the World row it names, because the
/// client fails to load a world with none.
pub fn requirements(location_id location_id: Int) -> List(store.Requirement) {
  [
    store.Requirement(
      from_table: "the server's starting place",
      column: "location",
      to_table: "WorldLocation2",
      missing: fn(tables) {
        case world_location2.get(tables, location_id) {
          Ok(_) -> []
          Error(Nil) -> [location_id]
        }
      },
    ),
    store.Requirement(
      from_table: "WorldLocation2",
      column: "worldId",
      to_table: "World",
      missing: fn(tables) {
        case world_location2.get(tables, location_id) {
          Error(Nil) -> []
          Ok(row) ->
            case world.get(tables, row.world_id) {
              Ok(_) -> []
              Error(Nil) -> [row.world_id]
            }
        }
      },
    ),
  ]
}
