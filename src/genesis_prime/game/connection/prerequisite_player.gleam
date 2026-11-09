//// The player a prerequisite check reads, from what the connection keeps of the
//// entered character. Each part comes from here.
//// - The character's own row: its race, class, path and gender, and the World
////   it entered (`Prerequisite.prerequisiteTypeId.2`, `.3`, `.52`, `.10`, `.109`).
//// - The level is the one the client's formulas read, which `GetUnitFormulaLevel`
////   (0x1403b5030) takes from the unit's stat 11 when that is not 0, else from
////   its stat 10; a unit created with neither is level 1 (0x1404543c1).
//// - The zones are the one the movement last reported and each parent above it
////   in the WorldZone table, which is the walk the client's zone check makes
////   (0x1403c92e0, `Prerequisite.prerequisiteTypeId.26`). A zone with no row has
////   no parent to walk to, so it is the one zone the player is in.

import genesis_prime/game/connection/state as connection_state
import genesis_prime/game/movement
import genesis_prime/game/prerequisite.{type Player, Player}
import genesis_prime/game/start_place
import genesis_prime/game/top_zone
import genesis_prime/game/world_entry
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/unit_fields

/// The player the entered character is.
pub fn of(
  tables tables: table_store.Tables,
  entered entered: world_entry.Entered,
) -> Player {
  let character = entered.character
  let zone = start_place.world_zone_id(movement.place(state: entered.movement))
  Player(
    race_id: character.race_id.value,
    class_id: character.class_id.value,
    level: formula_level(entered:),
    path: character.path,
    gender: character.gender,
    world_id: entered.map.world_id,
    zones: case top_zone.chain(tables:, world_zone_id: zone) {
      [] -> [zone]
      chain -> chain
    },
  )
}

/// The level the client's formulas read for the unit.
fn formula_level(entered entered: world_entry.Entered) -> Int {
  case
    unit_fields.stat(
      tail: entered.unit.tail,
      stat_id: unit_fields.level_override_stat,
    )
  {
    Ok(level) if level != 0 -> level
    Ok(_) | Error(Nil) -> connection_state.level_of(entered:)
  }
}
