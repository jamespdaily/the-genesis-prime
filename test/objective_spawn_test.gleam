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
//// - The scope is the worlds the server holds spawns for: the worlds of the stored
////   rows (issue 602's fix round); a marker in another world is skipped and
////   reported, so these tests store one row in World 3460, where the fixture's
////   markers are, and creature 4064 (in no kill objective) stands in it.
//// - The ring, the slot order and the ids are the design's (issue 602): a count
////   above 1 at a marker puts its slots on the circle of half the marker's
////   radius, the slot i of k at the angle 2 pi i / k from the +x axis towards +z,
////   each facing the centre; the creatures of a group take the slots in the
////   group's order, cycling; a placed row takes an id above every stored one.

import character_tables
import client_tables
import content_support
import database_support
import envoy
import fixture_tables
import genesis_prime/content/refusal
import genesis_prime/content/spawn as content_spawn
import genesis_prime/game/place_objective
import genesis_prime/game/target_group
import genesis_prime/game/vendor
import genesis_prime/import_world_data
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/table/loader/store
import genesis_prime/table/quest_objective
import genesis_prime/table/world_location2
import genesis_prime/world_map/objective_spawn.{type Placed}
import genesis_prime/world_map/spawn.{type Row}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/spawn_source
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/set.{type Set}
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

/// A creature that no kill objective names, which a test stores in World 3460 so
/// that the world is one the server holds spawns for.
const filler = 4064

/// The one stored row that makes World 3460 a world with spawns.
fn the_world_holds_spawns(tables tables: store.Tables) -> List(Row) {
  [stored(tables:, id: 1, creature_id: filler, world_id: world)]
}

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
  let tables = character_tables.content_tables()
  let placed =
    objective_spawn.place(tables:, stored: the_world_holds_spawns(tables:))
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
  let tables = character_tables.content_tables()
  let placed =
    objective_spawn.place(tables:, stored: the_world_holds_spawns(tables:))
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
  let tables = character_tables.content_tables()
  let placed =
    objective_spawn.place(tables:, stored: the_world_holds_spawns(tables:))
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
  let held = [
    stored(tables:, id: 5, creature_id: boss, world_id: world),
    ..the_world_holds_spawns(tables:)
  ]
  let placed = objective_spawn.place(tables:, stored: held)
  assert of_creatures(placed:, creatures: [boss]) == []
    as "the boss has a spawn in World 3460, where its marker is"
  assert of_creatures(placed:, creatures: [turret]) != []
    as "a creature with no stored spawn is still placed"
}

pub fn a_marker_in_a_world_with_no_stored_spawn_is_skipped_and_reported_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.content_tables()
  // Rows are stored in World 1387 only; the fixture's markers are in World 3460.
  let elsewhere = [stored(tables:, id: 1, creature_id: filler, world_id: 1387)]
  let placed = objective_spawn.place(tables:, stored: elsewhere)
  assert placed.rows == []
    as "no marker is in a world the server holds spawns for"
  // Objectives 21296 and 21310 name marker 51744, which is in World 3460.
  assert list.contains(
    placed.skipped,
    objective_spawn.Skipped(
      objective_id: 21_296,
      why: objective_spawn.NoSpawnsInWorld(marker_id: 51_744, world_id: world),
    ),
  )
    as "the report names the objective, the marker and its world"
  // A stored row in World 3460 makes the same marker one the creatures stand at.
  let placed =
    objective_spawn.place(tables:, stored: the_world_holds_spawns(tables:))
  assert of_creatures(placed:, creatures: [boss]) != []
  assert !list.contains(
    placed.skipped,
    objective_spawn.Skipped(
      objective_id: 21_296,
      why: objective_spawn.NoSpawnsInWorld(marker_id: 51_744, world_id: world),
    ),
  )
    as "a world with a stored spawn is no longer reported"
}

pub fn a_refused_placed_row_is_labelled_as_a_placement_not_a_spawn_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.content_tables()
  let placed =
    objective_spawn.place(tables:, stored: the_world_holds_spawns(tables:))
  let assert [first, ..] = of_creatures(placed:, creatures: [boss])
    as "the boss is placed"
  let assert [held] = the_world_holds_spawns(tables:)
  // A row in a world that no World row names is what the selection refuses. A
  // stored row and a placed row are put there, so one refusal is each's.
  let nowhere = 9_999_999
  let placed_row = spawn.Row(..first, world_id: nowhere)
  let stored_row = spawn.Row(..held, world_id: nowhere)
  let selection =
    spawn.select(
      rows: [stored_row, placed_row],
      tables:,
      formulas: rating_support.formulas(),
      kinds: spawn_support.kinds(),
      vendors: vendor.none(),
    )
  let SpawnId(placed_number) = placed_row.id
  let labelled =
    objective_spawn.labelled(
      refusals: selection.refusals,
      placed: objective_spawn.Placed(rows: [placed_row], skipped: []),
    )
  assert list.map(labelled, fn(refusal) { refusal.row })
    == [
      refusal.RowId(id: 1),
      refusal.RowName(
        name: "Creature2 73499 placed in World 9999999 as spawn id "
        <> int.to_string(placed_number),
      ),
    ]
    as "a stored row keeps its id; a placed row is named by what it stands for"
  assert list.map(labelled, fn(refusal) { refusal.table })
    == ["spawn", "kill objective placement"]
    as "the placed row's refusal names the placement, not the spawn table"
  assert list.map(labelled, fn(refusal) { refusal.rule })
    == list.map(selection.refusals, fn(refusal) { refusal.rule })
    as "the rule each broke is the selection's own"
}

pub fn two_objectives_on_one_creature_and_marker_place_once_test() -> Nil {
  use <- owned_test.run(60_000)
  // Both objectives count 1: the boss is placed once, not twice.
  let tables = character_tables.content_tables()
  let placed =
    objective_spawn.place(tables:, stored: the_world_holds_spawns(tables:))
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
      stored: the_world_holds_spawns(tables:),
    )
  assert list.length(of_creatures(placed:, creatures: [boss])) == 2
    as "the larger of the counts 1 and 2"
}

pub fn a_target_with_no_creature2_row_is_skipped_and_reported_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.content_tables()
  let placed =
    objective_spawn.place(tables:, stored: the_world_holds_spawns(tables:))
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
  // Stored rows of another world hide no placement, and the one in World 3460
  // makes it a world with spawns.
  let held = [
    stored(tables:, id: 1, creature_id: boss, world_id: 1387),
    stored(tables:, id: 70_880, creature_id: boss, world_id: 1387),
    stored(tables:, id: 2, creature_id: filler, world_id: world),
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

/// Over the client's real tables and the world database's stored rows (with
/// migration 0008's), what the placement does for every kill objective with a
/// marker. The expected totals are counts over the same tables and rows made
/// apart from the server's code, by a scratch Python script that reads the
/// QuestObjective, TargetGroup, WorldLocation2 and Creature2 rows
/// (`table_rows` dumps) and `spawn.tsv`:
/// - 555 distinct jobs (a creature list and a marker list that objectives share)
///   and 614 pairs of a kill objective and a stored world one of its markers is
///   in, for an objective with a creature that has a Creature2 row;
/// - 342 of those pairs have a stored spawn of every creature of the objective in
///   the world, so nothing is placed for them, and the rest are placed the
///   objective's count at its markers there;
/// - 1,764 placed rows in all, by world 22: 432, 51: 608, 426: 38, 870: 20, 990:
///   12, 1061: 623, 1387: 20 and 3460: 11.
pub fn every_kill_objective_with_a_marker_places_or_has_a_spawn_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("world_data")
  use <- unitest.guard(client_tables.present())
  use <- unitest.guard(envoy.get("GENESIS_WORLD_DATA") != Error(Nil))
  let assert Ok(folder) = envoy.get("GENESIS_WORLD_DATA")
    as "the guard saw the variable"
  let database = database_support.new_database(on: database_support.shared())
  let assert Ok(_) =
    import_world_data.import_spawns(
      db: content_support.connect(database:),
      folder:,
    )
    as "the world database imports"
  let assert Ok(stored) =
    content_spawn.rows(db: content_support.connect(database:))
    as "the stored spawn rows read back"
  let tables = client_tables.with_content_tables()
  let placed = objective_spawn.place(tables:, stored:)
  let worlds = set.from_list(list.map(stored, fn(row: Row) { row.world_id }))
  let held =
    list.filter_map(stored, fn(row: Row) {
      case row.entity_type == spawn.non_player {
        True -> Ok(#(row.world_id, row.creature_id))
        False -> Error(Nil)
      }
    })
    |> set.from_list
  let kill_objectives =
    list.filter(quest_objective.all(tables), fn(objective) {
      list.contains([2, 8, 16], objective.type_)
      && place_objective.marker_ids(objective:) != []
    })
  // Each pair of an objective and a stored world one of its markers is in has a
  // stored spawn of every creature there or the objective's count of its own
  // placed creatures standing in its own markers' circles; what is left out is
  // named in the report.
  let pairs =
    list.flat_map(kill_objectives, fn(objective) {
      one_objective(tables:, placed:, worlds:, held:, objective:)
    })
  assert list.length(pairs) == 614
    as "the pairs of a kill objective and a stored world its markers are in"
  assert list.count(pairs, fn(pair) { pair.1 }) == 342
    as "the pairs whose creatures are all stored there"
  assert list.length(placed.rows) == 1764
    as "the rows placed, by the count over the tables"
  let placed_in = fn(world_id) {
    list.count(placed.rows, fn(row: Row) { row.world_id == world_id })
  }
  assert list.map([22, 51, 426, 870, 990, 1061, 1387, 3460], placed_in)
    == [432, 608, 38, 20, 12, 623, 20, 11]
    as "the rows placed in each world with spawns that has any"
  assert list.all(placed.rows, fn(row: Row) {
    set.contains(worlds, row.world_id)
  })
    as "no row is placed in a world the server holds no spawns for"
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

/// The pairs of one kill objective and a stored world one of its markers is in,
/// each with whether every creature of the objective has a stored spawn there; the
/// checks of the objective are asserted.
fn one_objective(
  tables tables: store.Tables,
  placed placed: Placed,
  worlds worlds: Set(Int),
  held held: Set(#(Int, Int)),
  objective objective: quest_objective.QuestObjective,
) -> List(#(Int, Bool)) {
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
  let marker_worlds =
    place_objective.marker_ids(objective:)
    |> list.filter_map(fn(marker_id) {
      marker_world(
        tables:,
        placed:,
        worlds:,
        objective_id: objective.id,
        marker_id:,
      )
    })
    |> list.unique
  case with_rows {
    [] -> []
    _ ->
      list.map(marker_worlds, fn(world_id) {
        let free =
          list.filter(with_rows, fn(creature_id) {
            !set.contains(held, #(world_id, creature_id))
          })
        let own_circles =
          place_objective.markers(tables:, objective:)
          |> list.filter(fn(marker) { marker.world_id == world_id })
        let own_rows =
          list.count(placed.rows, fn(row: Row) {
            row.world_id == world_id
            && list.contains(free, row.creature_id)
            && list.any(own_circles, fn(marker) { stands_in(row:, marker:) })
          })
        assert free == [] || own_rows >= objective.count
          as {
            "objective "
            <> int.to_string(objective.id)
            <> " counts "
            <> int.to_string(objective.count)
            <> " and "
            <> int.to_string(own_rows)
            <> " of its creatures stand in its markers in World "
            <> int.to_string(world_id)
            <> ", where it has no stored spawn of "
            <> int.to_string(list.length(free))
            <> " of them"
          }
        #(world_id, free == [])
      })
  }
}

/// The world of a marker that the server holds spawns for; a marker with no row,
/// and one in a world with no stored spawn, are reported with that reason.
fn marker_world(
  tables tables: store.Tables,
  placed placed: Placed,
  worlds worlds: Set(Int),
  objective_id objective_id: Int,
  marker_id marker_id: Int,
) -> Result(Int, Nil) {
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
      Error(Nil)
    }
    Ok(marker) ->
      case set.contains(worlds, marker.world_id) {
        True -> Ok(marker.world_id)
        False -> {
          assert list.contains(
            placed.skipped,
            objective_spawn.Skipped(
              objective_id:,
              why: objective_spawn.NoSpawnsInWorld(
                marker_id:,
                world_id: marker.world_id,
              ),
            ),
          )
            as "a marker in a world with no stored spawn is reported"
          Error(Nil)
        }
      }
  }
}

/// Whether the row stands within the marker's circle, horizontally.
fn stands_in(
  row row: Row,
  marker marker: world_location2.WorldLocation2,
) -> Bool {
  let dx = row.x -. marker.position0
  let dz = row.z -. marker.position2
  dx *. dx +. dz *. dz
  <=. { marker.radius +. 0.01 } *. { marker.radius +. 0.01 }
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
