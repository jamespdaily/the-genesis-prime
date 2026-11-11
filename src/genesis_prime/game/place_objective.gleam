//// Where a quest objective is done by the player's position: the arrival test of the
//// client's place check, the places of a type 22 objective and of a checklist of
//// Primal-Manifestation kind, and the unit a place counts.
////
//// - A type 22 objective's marker is the WorldLocation2 rows its
////   worldLocationsIdIndicator00 to 03 name, any one of them (`QuestObjective.type.22`).
////   The client sends nothing for it and the server tells the objective's progress
////   (`opcode.0x361`), so the position decides here.
//// - A type 14 objective whose TargetGroup holds only creatures the client never
////   offers (no activate spell, no prerequisite on one, no questAnimStateId and no
////   prerequisiteIdAnimState on their Creature2 row) and whose questDirectionId is not 0
////   is counted by presence: the places of its QuestDirection are the rows its
////   QuestDirectionEntry rows name, and the unit that stands in a place the player
////   reached is the one counted (`QuestObjective.21294.places`).
////
//// Rules over the client's tables and the units the player is shown; the tests are
//// `objective_place_test` and `place_objective_test`.

import genesis_prime/game/activate
import genesis_prime/game/objective_link
import genesis_prime/game/shown
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/target_group
import genesis_prime/table/creature2
import genesis_prime/table/id.{
  Faction2Id, QuestDirectionEntryId, QuestDirectionId, QuestObjectiveId,
  WorldLocation2Id,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest_direction
import genesis_prime/table/quest_direction_entry
import genesis_prime/table/quest_objective.{type QuestObjective}
import genesis_prime/table/world_location2.{type WorldLocation2}
import genesis_prime/world_map/spawn
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/list
import gleam/result

/// The objective type of a place.
const place_type = 22

/// The objective type of a checklist use.
const checklist_use_type = 14

/// Whether the place the player stands at is at the WorldLocation2 row.
///
/// The client's test `IsPlayerAtWorldLocation` (`0x140485fa0`): a place is reached when
/// the height is within the row's maxVerticalDistance of the row's position1 (a limit of
/// 0 or less tests no height) and the horizontal distance, x and z, is at most the row's
/// radius. The client's test does not look at the row's world; the row names one
/// (WorldLocation2.worldId), and a place of another world is not the row's place, so
/// that is the first test here. The client computes in f32 and the server in f64, so
/// the two differ only for a position at the exact edge of the radius or the limit.
fn reached(location location: WorldLocation2, place place: Place) -> Bool {
  location.world_id == start_place.world_id(place)
  && arrival(
    location:,
    x: start_place.x(place),
    y: start_place.y(place),
    z: start_place.z(place),
  )
}

/// The client's arrival test on a point (`0x140485fa0`; `reached` says what it reads).
fn arrival(
  location location: WorldLocation2,
  x x: Float,
  y y: Float,
  z z: Float,
) -> Bool {
  let limit = location.max_vertical_distance
  case limit >. 0.0 && float.absolute_value(y -. location.position1) >. limit {
    True -> False
    False ->
      horizontal_distance_squared(location:, x:, z:)
      <=. squared(location.radius)
  }
}

fn horizontal_distance_squared(
  location location: WorldLocation2,
  x x: Float,
  z z: Float,
) -> Float {
  squared(x -. location.position0) +. squared(z -. location.position2)
}

fn squared(value: Float) -> Float {
  value *. value
}

/// The WorldLocation2 ids of the objective's marker: its worldLocationsIdIndicator00
/// to 03, in column order, an id of 0 naming none and so left out.
pub fn marker_ids(objective objective: QuestObjective) -> List(Int) {
  [
    objective.world_locations_id_indicator00,
    objective.world_locations_id_indicator01,
    objective.world_locations_id_indicator02,
    objective.world_locations_id_indicator03,
  ]
  |> list.filter(fn(marker_id) { marker_id != 0 })
}

/// The WorldLocation2 rows of the objective's marker, the rows `marker_ids` names
/// that the table holds.
pub fn markers(
  tables tables: table_store.Tables,
  objective objective: QuestObjective,
) -> List(WorldLocation2) {
  marker_ids(objective:) |> locations(tables:)
}

/// The objectives of type 22 with no marker row: nothing tells where they are done.
pub fn unmarked(tables tables: table_store.Tables) -> List(QuestObjective) {
  quest_objective.all(tables)
  |> list.filter(fn(row) {
    row.type_ == place_type && markers(tables:, objective: row) == []
  })
}

/// The objectives of type 22 with a marker and a count above 1 (the unmarked ones are in
/// `unmarked`): how many visits they take is not known, so the server does not count them.
pub fn repeated(tables tables: table_store.Tables) -> List(QuestObjective) {
  quest_objective.all(tables)
  |> list.filter(fn(row) {
    row.type_ == place_type
    && row.count > 1
    && markers(tables:, objective: row) != []
  })
}

/// Whether the position is at a marker of the type 22 objective of this
/// QuestObjective id.
pub fn at_marker(
  tables tables: table_store.Tables,
  objective_id objective_id: Int,
  place place: Place,
) -> Bool {
  case quest_objective.get(tables:, id: QuestObjectiveId(objective_id)) {
    Ok(row) ->
      row.type_ == place_type
      && list.any(markers(tables:, objective: row), fn(location) {
        reached(location:, place:)
      })
    Error(Nil) -> False
  }
}

/// The objectives a unit standing in a place counts: type 14, with a questDirectionId,
/// over a TargetGroup of creature ids that the client never offers.
pub fn place_counted(
  tables tables: table_store.Tables,
) -> List(QuestObjective) {
  quest_objective.all(tables)
  |> list.filter(fn(row) { is_place_counted(tables:, objective: row) })
}

fn is_place_counted(
  tables tables: table_store.Tables,
  objective objective: QuestObjective,
) -> Bool {
  use <- bool.guard(
    objective.type_ != checklist_use_type || objective.quest_direction_id == 0,
    False,
  )
  case target_group.creatures_of(tables:, group: objective.data) {
    [] -> False
    creatures ->
      list.all(creatures, fn(creature_id) {
        case creature2.get(tables:, id: creature_id) {
          Ok(row) -> never_offered(row:)
          Error(Nil) -> False
        }
      })
  }
}

/// Whether nothing of the creature's row makes the client offer a use of it: no
/// activate spell, no prerequisite on one, no quest animation state and no prerequisite
/// on an animation state.
fn never_offered(row row: creature2.Creature2) -> Bool {
  list.all(activate.creature_of(row).columns, fn(column) {
    column.spell4_id == 0 && column.prerequisite_id == 0
  })
  && !objective_link.has_link(row:)
}

/// The places of a place-counted objective: the WorldLocation2 rows of its
/// QuestDirection's entries (the entries' inactive rows are not places).
fn places(
  tables tables: table_store.Tables,
  objective objective: QuestObjective,
) -> List(WorldLocation2) {
  case
    quest_direction.get(
      tables:,
      id: QuestDirectionId(objective.quest_direction_id),
    )
  {
    Ok(direction) ->
      [
        direction.quest_direction_entry_id00,
        direction.quest_direction_entry_id01,
        direction.quest_direction_entry_id02,
        direction.quest_direction_entry_id03,
        direction.quest_direction_entry_id04,
        direction.quest_direction_entry_id05,
        direction.quest_direction_entry_id06,
        direction.quest_direction_entry_id07,
        direction.quest_direction_entry_id08,
        direction.quest_direction_entry_id09,
        direction.quest_direction_entry_id10,
        direction.quest_direction_entry_id11,
        direction.quest_direction_entry_id12,
        direction.quest_direction_entry_id13,
        direction.quest_direction_entry_id14,
        direction.quest_direction_entry_id15,
      ]
      |> list.filter_map(fn(entry_id) {
        quest_direction_entry.get(tables:, id: QuestDirectionEntryId(entry_id))
      })
      |> list.map(fn(entry) { entry.world_location2_id })
      |> locations(tables:)
    Error(Nil) -> []
  }
}

/// The WorldLocation2 rows the ids name that the table holds, an id of 0 naming none.
fn locations(
  ids ids: List(Int),
  tables tables: table_store.Tables,
) -> List(WorldLocation2) {
  list.filter(ids, fn(location_id) { location_id != 0 })
  |> list.filter_map(fn(location_id) {
    world_location2.get(tables:, id: WorldLocation2Id(location_id))
  })
}

/// The checklist indexes a position counts for the place-counted objective of this
/// QuestObjective id: for each of its places the position is at, the index of the shown
/// unit of the objective's TargetGroup that stands within the place's radius
/// horizontally (in the place's world), the one nearest the place's centre when several
/// stand there. A place with no such unit counts nothing, and neither does an objective
/// that is not place-counted.
pub fn indexes_counted(
  tables tables: table_store.Tables,
  objective_id objective_id: Int,
  place place: Place,
  shown shown: shown.Picture,
  now_ms now_ms: Int,
) -> List(Int) {
  case quest_objective.get(tables:, id: QuestObjectiveId(objective_id)) {
    Ok(row) ->
      case is_place_counted(tables:, objective: row) {
        False -> []
        True -> counted_under_places(tables:, row:, place:, shown:, now_ms:)
      }
    Error(Nil) -> []
  }
}

/// The checklist index of the group's unit under each place of the objective that the
/// player has reached; the units are not looked at when the player is in none.
fn counted_under_places(
  tables tables: table_store.Tables,
  row row: QuestObjective,
  place place: Place,
  shown shown: shown.Picture,
  now_ms now_ms: Int,
) -> List(Int) {
  let reached_places =
    places(tables:, objective: row)
    |> list.filter(fn(location) { reached(location:, place:) })
  use <- bool.guard(when: reached_places == [], return: [])
  let standing =
    shown.standing(tables:, picture: shown, now_ms:)
    |> list.filter(fn(stand) {
      target_group.contains(tables:, group: row.data, unit: stand.unit)
    })
  list.filter_map(reached_places, fn(location) { nearest(location:, standing:) })
}

/// The checklist index of the unit nearest the centre of the place among those that
/// stand within its radius horizontally in its world, the first of them in the
/// picture's order when two are as near.
fn nearest(
  location location: WorldLocation2,
  standing standing: List(shown.Standing),
) -> Result(Int, Nil) {
  standing
  |> list.filter(fn(stand) { stand.world_id == location.world_id })
  |> list.map(fn(stand) {
    #(stand, horizontal_distance_squared(location:, x: stand.x, z: stand.z))
  })
  |> list.filter(fn(found) { found.1 <=. squared(location.radius) })
  |> list.sort(fn(first, second) { float.compare(first.1, second.1) })
  |> list.first
  |> result.map(fn(found) { { found.0 }.checklist_index })
}

/// For each place-counted objective with a place that no spawn of its group stands in,
/// its id and the ids of those places, in id order: the places where reaching counts
/// nothing, from the spawns the world's maps hold (the creatures and the static objects
/// of every world).
pub fn places_without_unit(
  tables tables: table_store.Tables,
  worlds worlds: Dict(Int, spawn.WorldSpawns),
) -> List(#(Int, List(Int))) {
  let spawned = spawned_units(tables:, worlds:)
  list.filter_map(place_counted(tables:), fn(objective) {
    let empty =
      places(tables:, objective:)
      |> list.filter(fn(location) {
        !list.any(spawned, fn(stand) {
          stand.world_id == location.world_id
          && target_group.contains(
            tables:,
            group: objective.data,
            unit: stand.unit,
          )
          && horizontal_distance_squared(location:, x: stand.x, z: stand.z)
          <=. squared(location.radius)
        })
      })
      |> list.map(fn(location) { location.id })
    case empty {
      [] -> Error(Nil)
      _ -> Ok(#(objective.id, empty))
    }
  })
}

/// Every creature and static object the worlds' maps hold, as it would stand in a
/// picture.
fn spawned_units(
  tables tables: table_store.Tables,
  worlds worlds: Dict(Int, spawn.WorldSpawns),
) -> List(shown.Standing) {
  dict.values(worlds)
  |> list.flat_map(fn(world) {
    list.append(
      list.map(dict.values(world.by_id), fn(found) {
        #(
          found.creature_id,
          found.faction_id,
          found.checklist_index,
          found.place,
        )
      }),
      list.map(dict.values(world.objects), fn(found) {
        #(
          found.creature_id,
          found.faction_id,
          found.checklist_index,
          found.place,
        )
      }),
    )
  })
  |> list.filter_map(fn(found) {
    let #(creature_id, faction_id, checklist_index, place) = found
    use row <- result.map(creature2.get(tables:, id: creature_id))
    shown.Standing(
      unit: target_group.Unit(
        creature_id:,
        faction_id: Faction2Id(faction_id),
        unit_race_id: creature2.unit_race_id(row),
      ),
      checklist_index:,
      world_id: start_place.world_id(place),
      x: start_place.x(place),
      z: start_place.z(place),
    )
  })
}
