//// The creatures the content load places for the kill objectives whose creature
//// has no stored spawn (`genesis_prime/world_map/objective_spawn`). Expected
//// values come from these places.
//// - `WorldLocation2.npe_battle_markers`: the training simulation's markers, read
////   with `gleam run -m genesis_prime/table_rows -- WorldLocation2 51744 51740
////   52902 52903`. 51744 is at (429.29544, -388.88251, 253.77565), radius 27,
////   facing (0, -0.743145, 0, 0.669131), zone 5968; 51740 at (-142.06599,
////   -860.46375, 556.80902), radius 38; 52902 at (80.833504, -864.21387,
////   426.11499), radius 1, facing (0, 0.756012, 0, 0.654558), zone 5967; 52903 at
////   (114.16, -864.21387, 428.62701), facing (0, 0.590195, 0, 0.80726). All are in
////   World 3460.
//// - `QuestObjective` rows (`table_rows -- QuestObjective`): 21290 is type 8 of
////   TargetGroup 14356 (type 1: Creature2 73492 and 73567), count 3, marker
////   51740; 21296 and 21310 are type 2 of Creature2 73499, count 1, marker 51744;
////   1889 is type 2 of Creature2 5006, count 3, marker 15370 in World 625, and
////   the client's Creature2 holds no row 5006; 21316 is type 2 of Creature2
////   74862, count 2, markers 52902 and 52903. (21315 names Creature2 73468, which
////   has no row either, but it is type 5, a talk-or-use objective of the
////   tutorial that this module leaves alone.)
//// - `Creature2` rows: 73499 has factionId 219, display group 26986 (one entry,
////   display 24399) and no outfit group; 73492 has factionId 170, display group
////   28344 (first entry 26479, display 26045) and outfit group 10539 (first entry
////   11305, outfit 9739); 74862 has factionId 219.
//// - `QuaternionToEulerAngles` (`0x1401b2fe0`): a turn of t about y, (0, sin t/2,
////   cos t/2 as w), gives yaw t, so a marker's quaternion (0, y, 0, w) gives
////   yaw 2 atan2(y, w).
//// - `movement_command.kind_14.facing`: yaw 0 faces -z, so a unit of yaw a faces
////   (-sin a, -cos a) in (x, z).
//// - The ring, the slot order and the ids are the design's (issue 602): a count
////   above 1 at a marker puts its slots on the circle of half the marker's
////   radius, the slot i of k at the angle 2 pi i / k from the +x axis towards +z,
////   each facing the centre; the creatures of a group take the slots in the
////   group's order, cycling; a placed row takes an id above every stored one.

import character_tables
import client_tables
import fixture_tables
import genesis_prime/game/target_group
import genesis_prime/game/vendor
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id, WorldId}
import genesis_prime/table/loader/store
import genesis_prime/table/quest_objective
import genesis_prime/table/world
import genesis_prime/table/world_location2
import genesis_prime/world_map/objective_spawn.{type Placed}
import genesis_prime/world_map/spawn.{type Row}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/spawn_source
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam_community/maths
import owned_test
import place_support
import planted_table.{Integer}
import rating_support
import spawn_support
import unitest

const world = 3460

const boss = 73_499

const turret = 74_862

fn close(left: Float, right: Float) -> Bool {
  float.absolute_value(left -. right) <. 0.001
}

/// A row of the creature `creature_id` that a spawn table could hold, with the
/// id and in the world given: what the load's own builder makes of the
/// creature's Creature2 row, used here only as a stored input.
fn stored(
  tables tables: store.Tables,
  id id: Int,
  creature_id creature_id: Int,
  world_id world_id: Int,
) -> Row {
  let assert Ok(creature) = creature2.get(tables, Creature2Id(creature_id))
    as "the fixture holds the creature"
  spawn.creature_row(
    looks: spawn.looks(tables:),
    id: SpawnId(id),
    creature:,
    place: place_support.at(
      world_id:,
      world_zone_id: 5968,
      x: 0.0,
      y: 0.0,
      z: 0.0,
    ),
    level: None,
  )
}

/// The rows placed of these creatures, in the order placed.
fn of_creatures(
  placed placed: Placed,
  creatures creatures: List(Int),
) -> List(Row) {
  list.filter(placed.rows, fn(row: Row) {
    list.contains(creatures, row.creature_id)
  })
}

/// Whether the unit of the row faces the point (to_x, to_z): a yaw of a faces
/// (-sin a, -cos a) in (x, z) (`movement_command.kind_14.facing`), so the
/// direction to the point has no part across it and one along it.
fn faces(row row: Row, to_x to_x: Float, to_z to_z: Float) -> Bool {
  let dx = to_x -. row.x
  let dz = to_z -. row.z
  let along_x = float.negate(maths.sin(row.rotation_x))
  let along_z = float.negate(maths.cos(row.rotation_x))
  close(dx *. along_z -. dz *. along_x, 0.0)
  && dx *. along_x +. dz *. along_z >. 0.0
}

pub fn a_lone_target_stands_at_the_marker_centre_with_its_facing_test() -> Nil {
  use <- owned_test.run(60_000)
  let placed =
    objective_spawn.place(tables: character_tables.content_tables(), stored: [])
  // Objectives 21296 and 21310 name the boss at marker 51744, count 1.
  let assert [row] = of_creatures(placed:, creatures: [boss])
    as "one boss, for two objectives of the same creature and marker"
  assert row.world_id == world && row.area_id == 5968
    as "the marker's world and zone"
  assert close(row.x, 429.29544)
    && close(row.y, -388.88251)
    && close(row.z, 253.77565)
    as "the marker's position, height included"
  assert close(row.rotation_x, 2.0 *. maths.atan2(-0.743145, 0.669131))
    as "the yaw of the marker's quaternion"
  assert close(row.rotation_y, 0.0) && close(row.rotation_z, 0.0)
  assert row.entity_type == spawn.non_player
  assert row.faction_id == 219 && row.base_faction_id == 219
    as "the boss keeps the faction of its Creature2 row"
  assert row.display_info_id == 24_399 && row.outfit_info_id == 0
    as "the first entry of the creature's display group, and no outfit"
  assert row.level == None && row.health == None
    as "a creature stands at its minLevel with its Base Health"
}

pub fn a_count_spread_over_two_markers_gives_one_each_test() -> Nil {
  use <- owned_test.run(60_000)
  let placed =
    objective_spawn.place(tables: character_tables.content_tables(), stored: [])
  // Objective 21316: Creature2 74862, count 2, markers 52902 and 52903.
  let assert [first, second] = of_creatures(placed:, creatures: [turret])
    as "one turret for each of the two markers"
  assert close(first.x, 80.833504)
    && close(first.y, -864.21387)
    && close(first.z, 426.11499)
    as "marker 52902's centre"
  assert close(first.rotation_x, 2.0 *. maths.atan2(0.756012, 0.654558))
    as "marker 52902's facing"
  assert close(second.x, 114.16)
    && close(second.y, -864.21387)
    && close(second.z, 428.62701)
    as "marker 52903's centre"
  assert close(second.rotation_x, 2.0 *. maths.atan2(0.590195, 0.80726))
    as "marker 52903's facing"
  assert first.area_id == 5967 && second.area_id == 5967
}

pub fn a_group_target_alternates_its_creatures_on_the_ring_test() -> Nil {
  use <- owned_test.run(60_000)
  let placed =
    objective_spawn.place(tables: character_tables.content_tables(), stored: [])
  // Objective 21290: TargetGroup 14356 lists 73492 then 73567, count 3, marker
  // 51740 of radius 38 at (-142.06599, -860.46375, 556.80902).
  let assert [one, two, three] =
    of_creatures(placed:, creatures: [73_492, 73_567])
    as "three creatures, as many as the objective counts"
  assert list.map([one, two, three], fn(row) { row.creature_id })
    == [73_492, 73_567, 73_492]
    as "the group's creatures take the slots in order, cycling"
  let centre_x = -142.06599
  let centre_z = 556.80902
  let radius = 19.0
  list.index_map([one, two, three], fn(row, index) {
    let angle = 2.0 *. maths.pi() *. int.to_float(index) /. 3.0
    assert close(row.x, centre_x +. radius *. maths.cos(angle))
      && close(row.z, centre_z +. radius *. maths.sin(angle))
      as "the slot is on the circle of half the marker's radius at 2 pi i / 3"
    assert close(row.y, -860.46375) as "the marker's height"
    assert faces(row:, to_x: centre_x, to_z: centre_z)
      as "each faces the marker's centre"
    assert row.world_id == world && row.area_id == 5967
  })
  assert one.display_info_id == 26_045 && one.outfit_info_id == 9739
    as "the first entries of Creature2 73492's display and outfit groups"
  assert one.faction_id == 170
  Nil
}

pub fn a_creature_with_a_stored_spawn_in_the_world_gets_none_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.content_tables()
  let held = [stored(tables:, id: 5, creature_id: boss, world_id: world)]
  let placed = objective_spawn.place(tables:, stored: held)
  assert of_creatures(placed:, creatures: [boss]) == []
    as "the boss has a spawn in World 3460, where its marker is"
  assert of_creatures(placed:, creatures: [turret]) != []
    as "a creature with no stored spawn is still placed"
}

pub fn two_objectives_on_one_creature_and_marker_place_once_test() -> Nil {
  use <- owned_test.run(60_000)
  // Both objectives count 1: the boss is placed once, not twice.
  let placed =
    objective_spawn.place(tables: character_tables.content_tables(), stored: [])
  assert list.length(of_creatures(placed:, creatures: [boss])) == 1
  // With objective 21310's count 2 the larger count is placed, not the sum 3.
  use changed <- fixture_tables.changed(
    table: "QuestObjective",
    id: 21_310,
    with: [#("count", Integer(2))],
  )
  let placed =
    objective_spawn.place(
      tables: character_tables.content_over(tables: changed),
      stored: [],
    )
  assert list.length(of_creatures(placed:, creatures: [boss])) == 2
    as "the larger of the counts 1 and 2"
}

pub fn a_target_with_no_creature2_row_is_skipped_and_reported_test() -> Nil {
  use <- owned_test.run(60_000)
  let placed =
    objective_spawn.place(tables: character_tables.content_tables(), stored: [])
  // Objective 1889 is type 2 of Creature2 5006, which the client's table lacks.
  assert of_creatures(placed:, creatures: [5006]) == []
  assert list.contains(
    placed.skipped,
    objective_spawn.Skipped(
      objective_id: 1889,
      why: objective_spawn.NoCreatureRow(creature_id: 5006),
    ),
  )
    as "the report names the objective and the creature"
}

pub fn placement_ids_take_no_stored_or_run_only_id_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.content_tables()
  // Stored rows of another world, so they hide no placement.
  let held = [
    stored(tables:, id: 1, creature_id: boss, world_id: 1387),
    stored(tables:, id: 70_880, creature_id: boss, world_id: 1387),
  ]
  let placed = objective_spawn.place(tables:, stored: held)
  assert placed.rows != []
  let numbers =
    list.map(placed.rows, fn(row: Row) {
      let SpawnId(number) = row.id
      number
    })
  assert list.all(numbers, fn(number) { number > 70_880 })
    as "above every stored id, which is neither a stored one nor a run-only one"
  assert list.all(numbers, fn(number) {
    !spawn_source.is_run_only_id(SpawnId(number))
  })
  assert list.length(list.unique(numbers)) == list.length(numbers)
    as "each id is once"
  assert numbers == list.sort(numbers, int.compare) as "counting up"
}

pub fn every_kill_objective_with_a_marker_places_or_has_a_spawn_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.with_content_tables()
  let placed = objective_spawn.place(tables:, stored: [])
  let kill_objectives =
    list.filter(quest_objective.all(tables), fn(objective) {
      list.contains([2, 8, 16], objective.type_) && markers_of(objective:) != []
    })
  // With no stored spawn, each kill objective with a marker is placed or reported:
  // in each world its markers are in and the server holds a map for, as many of
  // its creatures stand as it counts, and what is left out is named in the report.
  list.each(kill_objectives, fn(objective) {
    let creatures = creatures_of(tables:, objective:)
    let with_rows =
      list.filter(creatures, fn(creature_id) {
        creature2.get(tables, Creature2Id(creature_id)) |> result_ok
      })
    list.each(creatures, fn(creature_id) {
      assert list.contains(with_rows, creature_id)
        || list.contains(
          placed.skipped,
          objective_spawn.Skipped(
            objective_id: objective.id,
            why: objective_spawn.NoCreatureRow(creature_id:),
          ),
        )
        as {
          "objective "
          <> int.to_string(objective.id)
          <> " names creature "
          <> int.to_string(creature_id)
          <> ", which has no row and is not reported"
        }
    })
    assert objective.type_ == 2
      || creatures != []
      || list.contains(
        placed.skipped,
        objective_spawn.Skipped(
          objective_id: objective.id,
          why: objective_spawn.NamesNoCreature(group_id: objective.data),
        ),
      )
      as {
        "objective "
        <> int.to_string(objective.id)
        <> "'s group lists no creature and is not reported"
      }
    list.each(worlds_of_markers(tables:, objective:), fn(world_id) {
      let here =
        list.count(placed.rows, fn(row: Row) {
          row.world_id == world_id && list.contains(with_rows, row.creature_id)
        })
      assert with_rows == [] || here >= objective.count
        as {
          "objective "
          <> int.to_string(objective.id)
          <> " counts "
          <> int.to_string(objective.count)
          <> " and "
          <> int.to_string(here)
          <> " creatures are placed in World "
          <> int.to_string(world_id)
        }
    })
    list.each(markers_of(objective:), fn(marker_id) {
      marker_is_placed_or_reported(
        tables:,
        placed:,
        objective_id: objective.id,
        marker_id:,
      )
    })
  })
  assert placed.rows != []
  // The load's checks refuse none of the placed rows, which would stop the start.
  let selection =
    spawn.select(
      rows: placed.rows,
      tables:,
      formulas: rating_support.formulas(),
      kinds: spawn_support.kinds(),
      vendors: vendor.none(),
    )
  assert selection.refusals == []
    as "a placed row that the checks refuse would stop the server's start"
}

/// A marker with no row is reported as such, and one in a world the server holds no map
/// for is reported with that world; a marker with both is the one the rows stand in.
fn marker_is_placed_or_reported(
  tables tables: store.Tables,
  placed placed: Placed,
  objective_id objective_id: Int,
  marker_id marker_id: Int,
) -> Nil {
  case world_location2.get(tables:, id: id.WorldLocation2Id(marker_id)) {
    Error(Nil) -> {
      assert list.contains(
        placed.skipped,
        objective_spawn.Skipped(
          objective_id:,
          why: objective_spawn.NoMarkerRow(marker_id:),
        ),
      )
        as "a marker with no row is reported"
      Nil
    }
    Ok(marker) ->
      case world.get(tables:, id: WorldId(marker.world_id)) {
        Ok(_) -> Nil
        Error(Nil) -> {
          assert list.contains(
            placed.skipped,
            objective_spawn.Skipped(
              objective_id:,
              why: objective_spawn.NoMap(marker_id:, world_id: marker.world_id),
            ),
          )
            as "a marker in a world with no map is reported"
          Nil
        }
      }
  }
}

fn result_ok(found: Result(a, Nil)) -> Bool {
  case found {
    Ok(_) -> True
    Error(Nil) -> False
  }
}

/// The creature ids the objective names: type 2's data, or the creatures its
/// group lists.
fn creatures_of(
  tables tables: store.Tables,
  objective objective: quest_objective.QuestObjective,
) -> List(Int) {
  case objective.type_ {
    2 -> [objective.data]
    _ -> target_group.listed_creatures(tables:, group: objective.data)
  }
}

/// The marker ids the objective names.
fn markers_of(
  objective objective: quest_objective.QuestObjective,
) -> List(Int) {
  [
    objective.world_locations_id_indicator00,
    objective.world_locations_id_indicator01,
    objective.world_locations_id_indicator02,
    objective.world_locations_id_indicator03,
  ]
  |> list.filter(fn(marker_id) { marker_id != 0 })
}

/// The World ids of the objective's markers that have a row and a map, each once.
fn worlds_of_markers(
  tables tables: store.Tables,
  objective objective: quest_objective.QuestObjective,
) -> List(Int) {
  markers_of(objective:)
  |> list.filter_map(fn(marker_id) {
    case world_location2.get(tables:, id: id.WorldLocation2Id(marker_id)) {
      Ok(marker) ->
        case world.get(tables:, id: WorldId(marker.world_id)) {
          Ok(_) -> Ok(marker.world_id)
          Error(Nil) -> Error(Nil)
        }
      Error(Nil) -> Error(Nil)
    }
  })
  |> list.unique
}
