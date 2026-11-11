//// The creatures a kill objective needs and the stored spawn table does not
//// hold: for each kill objective with a marker (QuestObjective types 2, 8 and
//// 16, whose worldLocationsIdIndicator00 to 03 name WorldLocation2 circles) in a
//// world the server holds spawns for (a world one stored row is in), a creature
//// with no stored spawn in the marker's world stands in the circle, as many as
//// the objective counts, so the player sees it, kills it and the objective
//// counts. The rows are placed once at the start, beside the stored
//// ones, and the map starts them as it starts a stored row (`spawn.select`).
////
//// - The client's tables set what is needed: type 2's data is a Creature2 id,
////   types 8 and 16's a TargetGroup whose creatures count (`target_group`), and
////   the marker is the circle the quest pane shows (`WorldLocation2.position0`
////   to 2, `radius`, facing0 to 3 a quaternion read as `start_place` does).
//// - The tutorial's markers show where the client wants the creatures
////   (`WorldLocation2.npe_battle_markers`). The client lifts a unit onto the
////   ground when it is at most 2 units below it and draws it at the height sent
////   above it, and it gives the server no ground height
////   (`unit.ground_lift`, `terrain_height.server_view`), so a creature stands at
////   its marker's height.
//// - Where a creature stands in the circle, and which creature of a group takes
////   which place, are the server's choice. The objective's count is dealt to
////   its markers one at a time in column order; a marker that gets one stands
////   it at its centre with its facing, and one that gets k stands them on the
////   circle of half its radius at the angles 2 pi s / k from the +x axis
////   towards +z, each facing the centre. The creatures of a group are dealt to
////   the places in that order and in the group's order, cycling. An objective
////   whose markers lie in different worlds is placed in each world with its
////   whole count; objectives of the same creatures and markers are placed once
////   with the largest count.
//// - A creature stands with what `spawn.creature_row` gives its Creature2 row:
////   the faction, the first display and outfit of its groups, no stored health
////   and its minLevel.
//// - A placed row takes an id above every stored one, counting up. No saved
////   table keys on a spawn id but `spawn_stat` (its own `spawn_id` column,
////   content that only a stored row has), so a placed row's id is the map's
////   alone, and its creature respawns at its place as a stored row's does.
////
//// A pair that is not placed is reported once at the start (`Skipped`): a
//// creature with no Creature2 row, a group that lists no creature, a marker with
//// no WorldLocation2 row and a marker in a world with no stored spawn. Kill
//// types 15 and 46 and the tutorial's other objective types name no creature to
//// place here.

import genesis_prime/content/refusal.{type Refusal}
import genesis_prime/game/place_objective
import genesis_prime/game/start_place.{type Place, Facing}
import genesis_prime/game/target_group
import genesis_prime/message/float32
import genesis_prime/table/creature2.{type Creature2}
import genesis_prime/table/id.{Creature2Id, WorldLocation2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest_objective.{type QuestObjective}
import genesis_prime/table/world_location2.{type WorldLocation2}
import genesis_prime/world_map/creature_faction.{type Factions}
import genesis_prime/world_map/spawn.{type Row}
import genesis_prime/world_map/spawn_id.{SpawnId}
import gleam/bool
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/set.{type Set}
import gleam_community/maths

/// The rows placed, in the order of the objectives that need them, and the pairs
/// that were not.
pub type Placed {
  Placed(rows: List(Row), skipped: List(Skipped))
}

/// An objective's creature or marker that was left out, and why.
pub type Skipped {
  Skipped(objective_id: Int, why: Why)
}

/// Why a creature or a marker was left out.
pub type Why {
  /// The creature has no Creature2 row.
  NoCreatureRow(creature_id: Int)
  /// The objective's TargetGroup has no row or lists no creature.
  NamesNoCreature(group_id: Int)
  /// The marker has no WorldLocation2 row.
  NoMarkerRow(marker_id: Int)
  /// The marker is in a world the server holds no stored spawn for.
  NoSpawnsInWorld(marker_id: Int, world_id: Int)
}

/// The objective types of a kill that names a creature or a group of them, with
/// a marker: 2 names a Creature2 id, 8 and 16 a TargetGroup.
fn is_placed_kind(objective objective: QuestObjective) -> Bool {
  objective.type_ == 2 || objective.type_ == 8 || objective.type_ == 16
}

/// A marker of an objective: its row and the place its centre is.
type Marker {
  Marker(row: WorldLocation2, place: Place)
}

/// What one objective asks for, as far as the tables let it: the creatures with
/// a Creature2 row, the markers with a row in a world with a stored spawn, and its
/// count.
/// `key` is the creature ids and the marker ids it names, each sorted, which two
/// objectives that ask the same thing share.
type Job {
  Job(
    key: #(List(Int), List(Int)),
    creatures: List(Creature2),
    markers: List(Marker),
    count: Int,
  )
}

/// The rows to stand for the kill objectives, given the rows the stored spawn
/// table holds: only a marker in a world one of them is in gets creatures, and a
/// creature with a stored non-player spawn in a marker's world is left to it.
/// A creature stands with its chosen faction when it has one (`factions`).
/// Pure: the tables, the chosen factions and the stored rows are all it reads.
pub fn place(
  tables tables: table_store.Tables,
  stored stored: List(Row),
  factions factions: Factions,
) -> Placed {
  let objectives =
    quest_objective.all(tables)
    |> list.filter(fn(objective) { is_placed_kind(objective:) })
  let worlds = set.from_list(list.map(stored, fn(row) { row.world_id }))
  let planned =
    list.map(objectives, fn(objective) { plan(tables:, worlds:, objective:) })
  let skipped =
    planned
    |> list.flat_map(fn(pair) { pair.1 })
    |> list.unique
  let jobs =
    planned
    |> list.filter_map(fn(pair) { option.to_result(pair.0, Nil) })
    |> merged
  let held = held_by(stored:)
  let looks = spawn.looks(tables:)
  let rows =
    list.flat_map(jobs, fn(job) { rows_of(job:, held:, looks:, factions:) })
  let first = highest_id(stored:) + 1
  let rows =
    list.index_map(rows, fn(row, index) {
      spawn.Row(..row, id: SpawnId(first + index))
    })
  Placed(rows:, skipped:)
}

/// What the objective asks for and what is wrong with it. An objective with no
/// marker asks for nothing and is not reported: it is no pair.
fn plan(
  tables tables: table_store.Tables,
  worlds worlds: Set(Int),
  objective objective: QuestObjective,
) -> #(option.Option(Job), List(Skipped)) {
  let marker_ids = place_objective.marker_ids(objective:)
  case marker_ids {
    [] -> #(None, [])
    _ -> {
      let creature_ids = case objective.type_ {
        2 -> [objective.data]
        _ -> target_group.listed_creatures(tables:, group: objective.data)
      }
      let no_group = case creature_ids {
        [] -> [Skipped(objective.id, NamesNoCreature(group_id: objective.data))]
        _ -> []
      }
      let #(rows, rowless) =
        list.map(creature_ids, fn(creature_id) {
          creature2.get(tables, Creature2Id(creature_id))
          |> result.replace_error(creature_id)
        })
        |> partitioned
      let no_rows =
        list.map(rowless, fn(creature_id) {
          Skipped(objective.id, NoCreatureRow(creature_id:))
        })
      let #(markers, marker_skips) =
        list.map(marker_ids, fn(marker_id) {
          marker_of(tables:, worlds:, marker_id:)
          |> result.map_error(fn(why) { Skipped(objective.id, why) })
        })
        |> partitioned
      let job = case rows, markers {
        [], _ | _, [] -> None
        _, _ ->
          option.Some(Job(
            key: #(
              list.sort(creature_ids, int.compare),
              list.sort(marker_ids, int.compare),
            ),
            creatures: rows,
            markers:,
            count: objective.count,
          ))
      }
      #(job, list.flatten([no_group, no_rows, marker_skips]))
    }
  }
}

/// The values and the errors of the results, each in the order given
/// (`result.partition` reverses them).
fn partitioned(results results: List(Result(a, e))) -> #(List(a), List(e)) {
  let #(values, errors) = result.partition(results)
  #(list.reverse(values), list.reverse(errors))
}

/// The marker, or why it cannot hold a creature: no row, or a world no stored
/// spawn is in (a row in world 0 is none either, and no stored spawn is in it).
fn marker_of(
  tables tables: table_store.Tables,
  worlds worlds: Set(Int),
  marker_id marker_id: Int,
) -> Result(Marker, Why) {
  use row <- result.try(
    world_location2.get(tables:, id: WorldLocation2Id(marker_id))
    |> result.replace_error(NoMarkerRow(marker_id:)),
  )
  let no_spawns = NoSpawnsInWorld(marker_id:, world_id: row.world_id)
  use <- bool.guard(
    when: !set.contains(worlds, row.world_id),
    return: Error(no_spawns),
  )
  use place <- result.try(
    start_place.of_row(row:) |> result.replace_error(no_spawns),
  )
  Ok(Marker(row:, place:))
}

/// The jobs with those that ask the same thing made one, the largest count kept,
/// in the order of the first.
fn merged(jobs jobs: List(Job)) -> List(Job) {
  list.fold(jobs, [], fn(kept: List(Job), job: Job) {
    case list.any(kept, fn(other: Job) { other.key == job.key }) {
      True ->
        list.map(kept, fn(other: Job) {
          case other.key == job.key {
            True -> Job(..other, count: int.max(other.count, job.count))
            False -> other
          }
        })
      False -> [job, ..kept]
    }
  })
  |> list.reverse
}

/// The (world, creature) pairs a stored spawn of any unit type stands: a turret
/// row stands its creature as a non-player row does.
fn held_by(stored stored: List(Row)) -> Set(#(Int, Int)) {
  list.map(stored, fn(row) { #(row.world_id, row.creature_id) })
  |> set.from_list
}

/// The highest stored id, 0 when none is stored.
fn highest_id(stored stored: List(Row)) -> Int {
  list.fold(stored, 0, fn(highest, row) {
    let SpawnId(number) = row.id
    int.max(highest, number)
  })
}

/// The rows of one job, world by world in the order its markers first show them.
fn rows_of(
  job job: Job,
  held held: Set(#(Int, Int)),
  looks looks: spawn.Looks,
  factions factions: Factions,
) -> List(Row) {
  job.markers
  |> list.map(fn(marker) { marker.row.world_id })
  |> list.unique
  |> list.flat_map(fn(world_id) {
    let creatures =
      list.filter(job.creatures, fn(creature) {
        !set.contains(held, #(world_id, creature.id))
      })
    let markers =
      list.filter(job.markers, fn(marker) { marker.row.world_id == world_id })
    rows_in_world(creatures:, markers:, count: job.count, looks:, factions:)
  })
}

/// The rows of one world: the count dealt to the markers one at a time, and the
/// creatures to the places in that order, cycling.
fn rows_in_world(
  creatures creatures: List(Creature2),
  markers markers: List(Marker),
  count count: Int,
  looks looks: spawn.Looks,
  factions factions: Factions,
) -> List(Row) {
  let creature_count = list.length(creatures)
  let marker_count = list.length(markers)
  let by_turn =
    dict.from_list(
      list.index_map(creatures, fn(creature, turn) { #(turn, creature) }),
    )
  case creature_count, marker_count {
    0, _ | _, 0 -> []
    _, _ ->
      list.index_map(markers, fn(marker, index) {
        let slots =
          count
          / marker_count
          + case index < count % marker_count {
            True -> 1
            False -> 0
          }
        list.repeat(Nil, slots)
        |> list.index_map(fn(_, slot) { slot })
        |> list.filter_map(fn(slot) {
          // The place the count's dealing gives this slot: marker `index` is
          // dealt places index, index + markers, index + 2 markers, ...
          let turn = index + slot * marker_count
          use creature <- result.map(dict.get(by_turn, turn % creature_count))
          spawn.creature_row(
            looks:,
            factions:,
            id: SpawnId(0),
            creature:,
            place: slot_place(marker:, slot:, slots:),
            level: None,
          )
        })
      })
      |> list.flatten
  }
}

/// The place of slot `slot` of the `slots` a marker holds: the marker's own
/// place for one, else a point of the circle of half its radius, facing the
/// centre. Positions and the facing are 32-bit floats, as a row's are.
fn slot_place(
  marker marker: Marker,
  slot slot: Int,
  slots slots: Int,
) -> Place {
  case slots {
    1 -> marker.place
    _ -> {
      let angle = 2.0 *. maths.pi() *. int.to_float(slot) /. int.to_float(slots)
      let reach = marker.row.radius /. 2.0
      let centre = marker.place
      start_place.moved(
        place: centre,
        x: float32.rounded(start_place.x(centre) +. reach *. maths.cos(angle)),
        y: start_place.y(centre),
        z: float32.rounded(start_place.z(centre) +. reach *. maths.sin(angle)),
      )
      |> start_place.turned(
        // The unit faces (-sin yaw, -cos yaw) in (x, z): towards the centre, from
        // the circle's point at `angle`, that is (-cos angle, -sin angle).
        facing: Facing(
          yaw: float32.rounded(maths.atan2(maths.cos(angle), maths.sin(angle))),
          pitch: 0.0,
          roll: 0.0,
        ),
      )
    }
  }
}

/// The sentence for the log that says what a skipped pair lacked.
fn describe(skipped skipped: Skipped) -> String {
  let objective = "kill objective " <> int.to_string(skipped.objective_id)
  case skipped.why {
    NoCreatureRow(creature_id:) ->
      objective
      <> " names Creature2 "
      <> int.to_string(creature_id)
      <> ", which the client's table has no row of"
    NamesNoCreature(group_id:) ->
      objective
      <> "'s TargetGroup "
      <> int.to_string(group_id)
      <> " lists no creature"
    NoMarkerRow(marker_id:) ->
      objective
      <> "'s marker "
      <> int.to_string(marker_id)
      <> " has no WorldLocation2 row"
    NoSpawnsInWorld(marker_id:, world_id:) ->
      objective
      <> "'s marker "
      <> int.to_string(marker_id)
      <> " is in World "
      <> int.to_string(world_id)
      <> ", where the server holds no stored spawn"
  }
}

/// The lines the start logs of a placement: how many creatures it placed, then
/// each pair it skipped.
pub fn report(placed placed: Placed) -> List(String) {
  [
    "kill objectives: placed "
      <> int.to_string(list.length(placed.rows))
      <> " creatures with no stored spawn in their marker's world, skipped "
      <> int.to_string(list.length(placed.skipped))
      <> " pairs",
    ..list.map(placed.skipped, fn(skipped) { describe(skipped:) })
  ]
}

/// The selection's refusals with those of placed rows named as such: a refusal
/// of a row whose id is one this placement gave names the table
/// "kill objective placement" and the creature, the world and the id, since no
/// database holds a placed row's id. The others are kept. Pass only the
/// selection's own refusals, whose numbered rows are the spawn rows.
pub fn labelled(
  refusals refusals: List(Refusal),
  placed placed: Placed,
) -> List(Refusal) {
  let by_number =
    list.map(placed.rows, fn(row) {
      let SpawnId(number) = row.id
      #(number, row)
    })
    |> dict.from_list
  list.map(refusals, fn(refused) {
    case refused.row {
      refusal.RowId(id:) ->
        case dict.get(by_number, id) {
          Ok(row) ->
            refusal.Refusal(
              ..refused,
              table: "kill objective placement",
              row: refusal.RowName(
                name: "Creature2 "
                <> int.to_string(row.creature_id)
                <> " placed in World "
                <> int.to_string(row.world_id)
                <> " as spawn id "
                <> int.to_string(id),
              ),
            )
          Error(Nil) -> refused
        }
      refusal.RowName(..) -> refused
    }
  })
}
