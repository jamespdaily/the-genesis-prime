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
import genesis_prime/table/id.{Creature2Id, QuestObjectiveId}
import genesis_prime/table/loader/store
import genesis_prime/table/quest_objective
import genesis_prime/table/world_location2
import genesis_prime/world_map/creature_faction
import genesis_prime/world_map/creature_unit_type
import genesis_prime/world_map/objective_spawn.{type Placed}
import genesis_prime/world_map/spawn.{type Row}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/spawn_source
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/set.{type Set}
import gleam/string
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

/// The placement the content load makes, with the kinds migration 0029 leaves: the
/// Sim-Turrets have kinds of their own.
fn placed_by_the_load(
  tables tables: store.Tables,
  stored stored: List(Row),
  factions factions: creature_faction.Factions,
) -> Placed {
  objective_spawn.place(
    tables:,
    stored:,
    factions:,
    kinds: spawn_support.turret_kinds(),
  )
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
    factions: creature_faction.none(),
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
    placed_by_the_load(
      tables:,
      stored: the_world_holds_spawns(tables:),
      factions: creature_faction.none(),
    )
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
  assert row.entity_type == 0
    as "the boss is a NonPlayer unit, entity type 0 (`world_data.entity_type`)"
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
    placed_by_the_load(
      tables:,
      stored: the_world_holds_spawns(tables:),
      factions: creature_faction.none(),
    )
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
    placed_by_the_load(
      tables:,
      stored: the_world_holds_spawns(tables:),
      factions: creature_faction.none(),
    )
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
  let placed =
    placed_by_the_load(tables:, stored: held, factions: creature_faction.none())
  assert of_creatures(placed:, creatures: [boss]) == []
    as "the boss has a spawn in World 3460, where its marker is"
  assert of_creatures(placed:, creatures: [turret]) != []
    as "a creature with no stored spawn is still placed"
}

pub fn a_stored_turret_row_holds_its_objective_creature_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.content_tables()
  // Objective 21288 (quest 10518) is type 2 of Creature2 73494, count 2, markers
  // 51671 and 52753, which sit at the points of world rows 29179 and 29178: the
  // training simulation stores those two as type 13 rows.
  let assert Ok(objective) =
    quest_objective.get(tables:, id: QuestObjectiveId(21_288))
    as "the fixture holds objective 21288"
  assert objective.type_ == 2
    && objective.data == 73_494
    && objective.count == 2
    as "objective 21288 counts 2 of Creature2 73494"
  let held = [
    spawn.Row(
      ..stored(tables:, id: 5, creature_id: 73_494, world_id: world),
      entity_type: 13,
    ),
    ..the_world_holds_spawns(tables:)
  ]
  let placed =
    placed_by_the_load(tables:, stored: held, factions: creature_faction.none())
  assert of_creatures(placed:, creatures: [73_494]) == []
    as "a stored row of the turret, of any unit type, holds the objective's creature in its world"
  let placed =
    placed_by_the_load(
      tables:,
      stored: the_world_holds_spawns(tables:),
      factions: creature_faction.none(),
    )
  assert list.length(of_creatures(placed:, creatures: [73_494])) == 2
    as "with no stored row the two markers place two turrets"
}

pub fn the_dominion_turrets_are_placed_with_faction_1442_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.content_tables()
  // Objective 21316: Creature2 74862, count 2, markers 52902 and 52903. Its Creature2
  // row gives faction 219, Friendly to both player factions; creature_faction
  // 74862 -> 1442 stands it with 1442, Hostile to Dominion (Faction2Relationship
  // 2946: 1442 to 166, level 0).
  let factions = spawn_support.the_turrets_are_given_their_factions(tables:)
  let placed =
    placed_by_the_load(
      tables:,
      stored: the_world_holds_spawns(tables:),
      factions:,
    )
  let assert [first, second] = of_creatures(placed:, creatures: [turret])
    as "one turret for each of the two markers"
  assert first.faction_id == 1442 && first.base_faction_id == 1442
    as "the placed row carries the chosen faction as its faction and its base faction"
  assert second.faction_id == 1442 && second.base_faction_id == 1442
  let selection =
    spawn.select(
      rows: placed.rows,
      tables:,
      formulas: rating_support.formulas(),
      kinds: spawn_support.turret_kinds(),
      vendors: vendor.none(),
      factions:,
    )
  let assert Ok(started) = dict.get(selection.worlds, world)
    as "the selection holds world 3460"
  assert dict.has_key(started.by_id, first.id)
    && dict.has_key(started.by_id, second.id)
    as "both start: with 1442 they are no longer Friendly to both"
  // Creature2 74862 has CreationTypeEnum 13 (Turret), as the training simulation's stored
  // type 13 rows of its kind do (`world_data.entity_type`): a placed row stands as one
  // too, so the creature starts as a Turret that never moves.
  assert first.entity_type == 13 && second.entity_type == 13
    as "the placed rows are entity type 13, as the creature's CreationTypeEnum says"
  let assert Ok(spawn_of_first) = dict.get(started.by_id, first.id)
  assert spawn_of_first.unit_type == creature_unit_type.Turret
    as "a placed turret row starts as a Turret"
  assert spawn_of_first.combat.attack.run_speed == 0.0 as "a turret never runs"
}

pub fn a_turret_creature_with_no_kind_is_not_placed_and_is_reported_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.content_tables()
  // Creature2 73494 and 74862 have CreationTypeEnum 13 (Turret); with the default kinds
  // alone (no creature_kind row of their own) no server fight would run them, and a
  // row of type 13 with no kind is a static object (`spawn.select`).
  let placed =
    objective_spawn.place(
      tables:,
      stored: the_world_holds_spawns(tables:),
      factions: creature_faction.none(),
      kinds: spawn_support.kinds(),
    )
  assert of_creatures(placed:, creatures: [73_494, turret]) == []
    as "neither Sim-Turret is placed"
  assert list.contains(
    placed.skipped,
    objective_spawn.Skipped(
      objective_id: 21_288,
      why: objective_spawn.TurretHasNoKind(creature_id: 73_494),
    ),
  )
    as "objective 21288 names Creature2 73494, which is reported"
  assert list.contains(
    placed.skipped,
    objective_spawn.Skipped(
      objective_id: 21_316,
      why: objective_spawn.TurretHasNoKind(creature_id: turret),
    ),
  )
    as "objective 21316 names Creature2 74862, which is reported"
}

pub fn a_stored_row_holds_its_creature_only_when_it_starts_as_a_creature_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.content_tables()
  let turret_row =
    spawn.Row(
      ..stored(tables:, id: 5, creature_id: 73_494, world_id: world),
      entity_type: 13,
    )
  let non_player_row =
    stored(tables:, id: 6, creature_id: boss, world_id: world)
  assert objective_spawn.held_by(
      stored: [turret_row, non_player_row],
      kinds: spawn_support.turret_kinds(),
    )
    == set.from_list([#(world, 73_494), #(world, boss)])
    as "a type 13 row whose creature has a kind starts as a creature, as a non-player row does"
  assert objective_spawn.held_by(
      stored: [turret_row, non_player_row],
      kinds: spawn_support.kinds(),
    )
    == set.from_list([#(world, boss)])
    as "a type 13 row with no kind of its creature is a static object, which stands no creature"
}

pub fn a_marker_in_a_world_with_no_stored_spawn_is_skipped_and_reported_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.content_tables()
  // Rows are stored in World 1387 only; the fixture's markers are in World 3460.
  let elsewhere = [stored(tables:, id: 1, creature_id: filler, world_id: 1387)]
  let placed =
    placed_by_the_load(
      tables:,
      stored: elsewhere,
      factions: creature_faction.none(),
    )
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
    placed_by_the_load(
      tables:,
      stored: the_world_holds_spawns(tables:),
      factions: creature_faction.none(),
    )
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
    placed_by_the_load(
      tables:,
      stored: the_world_holds_spawns(tables:),
      factions: creature_faction.none(),
    )
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
      factions: creature_faction.none(),
    )
  let SpawnId(placed_number) = placed_row.id
  let labelled =
    objective_spawn.labelled(
      refusals: selection.refusals,
      placed: objective_spawn.Placed(
        rows: [placed_row],
        skipped: [],
        click_rows: [],
        click_skipped: [],
      ),
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
    placed_by_the_load(
      tables:,
      stored: the_world_holds_spawns(tables:),
      factions: creature_faction.none(),
    )
  assert list.length(of_creatures(placed:, creatures: [boss])) == 1
  // With objective 21310's count 2 the larger count is placed, not the sum 3.
  use changed <- fixture_tables.changed(
    table: "QuestObjective",
    id: 21_310,
    with: [#("count", Integer(2))],
  )
  let placed =
    placed_by_the_load(
      tables: character_tables.content_over(tables: changed),
      stored: the_world_holds_spawns(tables:),
      factions: creature_faction.none(),
    )
  assert list.length(of_creatures(placed:, creatures: [boss])) == 2
    as "the larger of the counts 1 and 2"
}

pub fn a_target_with_no_creature2_row_is_skipped_and_reported_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.content_tables()
  let placed =
    placed_by_the_load(
      tables:,
      stored: the_world_holds_spawns(tables:),
      factions: creature_faction.none(),
    )
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
  let placed =
    placed_by_the_load(tables:, stored: held, factions: creature_faction.none())
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
  let factions = spawn_support.the_boss_is_given_233(tables:)
  let placed = placed_by_the_load(tables:, stored:, factions:)
  let worlds = set.from_list(list.map(stored, fn(row: Row) { row.world_id }))
  let held =
    objective_spawn.held_by(stored:, kinds: spawn_support.turret_kinds())
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
  assert list.count(pairs, fn(pair) { pair.1 }) == 343
    as "the pairs whose creatures are all stored there"
  assert list.length(placed.rows) == 1762
    as "the rows placed, by the count over the tables"
  let placed_in = fn(world_id) {
    list.count(placed.rows, fn(row: Row) { row.world_id == world_id })
  }
  assert list.map([22, 51, 426, 870, 990, 1061, 1387, 3460], placed_in)
    == [432, 608, 38, 20, 12, 623, 20, 9]
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
      kinds: spawn_support.turret_kinds(),
      vendors: vendor.none(),
      factions:,
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

pub fn the_placed_boss_takes_its_chosen_faction_and_starts_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objectives 21296 and 21310 name Creature2 73499 at marker 51744; its Creature2 row
  // gives faction 219, Friendly to both player factions, and creature_faction
  // 73499 -> 233 stands it with 233, Hostile to both (Faction2Relationship 746).
  let tables = character_tables.content_tables()
  let factions = spawn_support.the_boss_is_given_233(tables:)
  let placed =
    placed_by_the_load(
      tables:,
      stored: the_world_holds_spawns(tables:),
      factions:,
    )
  let assert [row] = of_creatures(placed:, creatures: [boss])
    as "one boss, for two objectives of the same creature and marker"
  assert row.faction_id == 233 && row.base_faction_id == 233
    as "the placed row carries the chosen faction as its faction and its base faction"
  let selection =
    spawn.select(
      rows: placed.rows,
      tables:,
      formulas: rating_support.formulas(),
      kinds: spawn_support.kinds(),
      vendors: vendor.none(),
      factions:,
    )
  let assert Ok(started) = dict.get(selection.worlds, world)
    as "the selection holds world 3460"
  assert dict.has_key(started.by_id, row.id)
    as "the boss starts: with 233 it is no longer Friendly to both"
}

// Click targets: the creatures a type 5 or 32 objective is linked to
// (`objective_link.links`). The tutorial's three mines (Creature2 73463, 73667
// and 73668, CreationTypeEnum 20) are each linked to an Exile objective of quest
// 10518 and a Dominion objective of quest 10524; the markers, read from the
// client's WorldLocation2 rows, all in World 3460, zone 5967, radius 1, facing
// (0, 0, 0, 1) (yaw 0):
// - 51662 at (-70.4453, -868.839, 383.553), objective 21287 (73463, Exile);
// - 51663 at (-87.8594, -868.839, 414.038), objective 21340 (73667, Exile);
// - 51664 at (-119.41, -868.839, 424.962), objective 21318 (73668, Exile);
// - 52899 at (72.9871, -872.0891, 357.634), objective 21313 (73463, Dominion);
// - 52900 at (53.515, -872.0891, 374.479), objective 21314 (73667, Dominion);
// - 52901 at (43.1171, -872.0891, 395.189), objective 21315 (73668, Dominion).
// The world database stores the three Exile mines as entity type 32 rows 29098
// to 29100 (`spawn.tsv`), each 0.25 above its marker. Creature2 12919
// (CreationTypeEnum 8) is linked to the type 32 objective 4813, whose markers
// 9181, 9182 and 9962 are in World 426.

const mine = 73_463

const mine_medium = 73_667

const mine_hard = 73_668

const exile_marker = 51_662

const dominion_marker = 52_899

/// The three mines as the world database stores them, standing at the Exile markers.
fn the_exile_mines_stored(tables tables: store.Tables) -> List(Row) {
  [
    stored_at(tables:, id: 29_098, creature_id: mine, place: #(
      -70.4453,
      -868.5904,
      383.553,
    )),
    stored_at(tables:, id: 29_099, creature_id: mine_medium, place: #(
      -87.8594,
      -868.72217,
      414.038,
    )),
    stored_at(tables:, id: 29_100, creature_id: mine_hard, place: #(
      -119.41,
      -868.8015,
      424.962,
    )),
  ]
}

/// A stored row of the creature in World 3460 as a static object (entity type 32)
/// standing at (x, y, z).
fn stored_at(
  tables tables: store.Tables,
  id id: Int,
  creature_id creature_id: Int,
  place place: #(Float, Float, Float),
) -> Row {
  in_world_at(tables:, id:, creature_id:, world_id: world, place:)
}

fn in_world_at(
  tables tables: store.Tables,
  id id: Int,
  creature_id creature_id: Int,
  world_id world_id: Int,
  place place: #(Float, Float, Float),
) -> Row {
  spawn.Row(
    ..stored(tables:, id:, creature_id:, world_id:),
    entity_type: 32,
    x: place.0,
    y: place.1,
    z: place.2,
  )
}

/// The click rows placed of these creatures, in the order placed.
fn click_of(
  placed placed: Placed,
  creatures creatures: List(Int),
) -> List(Row) {
  list.filter(placed.click_rows, fn(row: Row) {
    list.contains(creatures, row.creature_id)
  })
}

/// Whether the row stands at the point.
fn stands_at(row row: Row, x x: Float, y y: Float, z z: Float) -> Bool {
  close(row.x, x) && close(row.y, y) && close(row.z, z)
}

fn the_marker_of(
  tables tables: store.Tables,
  marker_id marker_id: Int,
) -> world_location2.WorldLocation2 {
  let assert Ok(marker) =
    world_location2.get(tables:, id: id.WorldLocation2Id(marker_id))
    as "the fixture holds the marker"
  marker
}

/// The click placement over the changed tables, with World 3460 held by one row
/// of a creature no objective names.
fn click_placed_in_world(tables tables: store.Tables) -> Placed {
  let content = character_tables.content_over(tables:)
  placed_by_the_load(
    tables: content,
    stored: the_world_holds_spawns(tables: content),
    factions: creature_faction.none(),
  )
}

pub fn the_dominion_mines_stand_at_their_markers_when_the_exile_mines_are_stored_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.content_tables()
  let placed =
    placed_by_the_load(
      tables:,
      stored: the_exile_mines_stored(tables:),
      factions: creature_faction.none(),
    )
  let assert [first, second, third] = placed.click_rows
    as "exactly the three Dominion mines, none at the Exile markers"
  assert list.map([first, second, third], fn(row) { row.creature_id })
    == [mine, mine_medium, mine_hard]
  assert stands_at(first, x: 72.9871, y: -872.0891, z: 357.634)
    as "73463 at marker 52899"
  assert stands_at(second, x: 53.515, y: -872.0891, z: 374.479)
    as "73667 at marker 52900"
  assert stands_at(third, x: 43.1171, y: -872.0891, z: 395.189)
    as "73668 at marker 52901"
  list.each([first, second, third], fn(row) {
    assert row.world_id == world && row.area_id == 5967
      as "the marker's world and zone"
    assert close(row.rotation_x, 0.0)
      && close(row.rotation_y, 0.0)
      && close(row.rotation_z, 0.0)
      as "the marker's facing, yaw 0"
    assert row.entity_type == 32
      as "CreationTypeEnum 20 pairs with unit type 32"
    assert row.health == None && row.level == None
      as "no health or level of its own"
  })
}

pub fn a_stored_row_of_a_static_unit_type_serves_its_marker_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.content_tables()
  // Row 29098 alone, entity type 32, 0.25 above marker 51662.
  let placed =
    placed_by_the_load(
      tables:,
      stored: [
        stored_at(tables:, id: 29_098, creature_id: mine, place: #(
          -70.4453,
          -868.5904,
          383.553,
        )),
      ],
      factions: creature_faction.none(),
    )
  let assert [row] = click_of(placed:, creatures: [mine])
    as "one row of the mine: the Dominion marker has none"
  assert stands_at(row, x: 72.9871, y: -872.0891, z: 357.634)
    as "placed at 52899, not at 51662, which the stored static row serves"
}

pub fn a_marker_a_stored_spawn_stands_nearest_gets_none_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.content_tables()
  let placed =
    placed_by_the_load(
      tables:,
      stored: [
        stored_at(tables:, id: 5, creature_id: mine, place: #(
          72.9871,
          -872.0891,
          357.634,
        )),
      ],
      factions: creature_faction.none(),
    )
  let assert [row] = click_of(placed:, creatures: [mine])
    as "one row of the mine"
  assert stands_at(row, x: -70.4453, y: -868.839, z: 383.553)
    as "placed at 51662, the marker no stored row stands nearest in"
}

/// The point the fraction `along` of the way from marker 51662 to marker 52899 in
/// x and z, at the height of 51662.
fn along_the_way(
  tables tables: store.Tables,
  along along: Float,
) -> #(Float, Float, Float) {
  let from = the_marker_of(tables:, marker_id: exile_marker)
  let to = the_marker_of(tables:, marker_id: dominion_marker)
  #(
    from.position0 +. along *. { to.position0 -. from.position0 },
    from.position1,
    from.position2 +. along *. { to.position2 -. from.position2 },
  )
}

pub fn a_stored_spawn_serves_one_marker_only_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.content_tables()
  let near_exile =
    placed_by_the_load(
      tables:,
      stored: [
        stored_at(
          tables:,
          id: 5,
          creature_id: mine,
          place: along_the_way(tables:, along: 0.3),
        ),
      ],
      factions: creature_faction.none(),
    )
  let assert [row] = click_of(placed: near_exile, creatures: [mine])
    as "one row of the mine"
  assert stands_at(row, x: 72.9871, y: -872.0891, z: 357.634)
    as "a row nearer 51662 serves 51662 only: placed at 52899"
  let near_dominion =
    placed_by_the_load(
      tables:,
      stored: [
        stored_at(
          tables:,
          id: 5,
          creature_id: mine,
          place: along_the_way(tables:, along: 0.7),
        ),
      ],
      factions: creature_faction.none(),
    )
  let assert [row] = click_of(placed: near_dominion, creatures: [mine])
    as "one row of the mine"
  assert stands_at(row, x: -70.4453, y: -868.839, z: 383.553)
    as "a row nearer 52899 serves 52899 only: placed at 51662"
}

pub fn a_tie_goes_to_the_lower_marker_id_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.content_tables()
  let exile = the_marker_of(tables:, marker_id: exile_marker)
  // Marker 52899 moves to 2 above 51662 in z, and the row stands 1 above 51662,
  // so both markers are exactly 1 away in (x, z).
  use changed <- fixture_tables.changed(
    table: "WorldLocation2",
    id: dominion_marker,
    with: [
      #("position0", planted_table.Float(exile.position0)),
      #("position2", planted_table.Float(exile.position2 +. 2.0)),
    ],
  )
  let placed =
    placed_by_the_load(
      tables: character_tables.content_over(tables: changed),
      stored: [
        stored_at(tables:, id: 5, creature_id: mine, place: #(
          exile.position0,
          exile.position1,
          exile.position2 +. 1.0,
        )),
      ],
      factions: creature_faction.none(),
    )
  let assert [row] = click_of(placed:, creatures: [mine])
    as "one row of the mine: the tie serves 51662, so 52899 is the one placed"
  assert close(row.x, exile.position0) && close(row.z, exile.position2 +. 2.0)
    as "placed at the moved marker 52899"
}

pub fn a_stored_row_in_another_world_serves_no_marker_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.content_tables()
  // 73463's only stored row is in World 1387, and a row of another creature holds
  // World 3460 (both markers' world).
  let placed =
    placed_by_the_load(
      tables:,
      stored: [
        in_world_at(tables:, id: 5, creature_id: mine, world_id: 1387, place: #(
          -70.4453,
          -868.5904,
          383.553,
        )),
        ..the_world_holds_spawns(tables:)
      ],
      factions: creature_faction.none(),
    )
  let assert [first, second] = click_of(placed:, creatures: [mine])
    as "one row at each marker"
  assert stands_at(first, x: -70.4453, y: -868.839, z: 383.553) as "51662 first"
  assert stands_at(second, x: 72.9871, y: -872.0891, z: 357.634) as "then 52899"
}

pub fn a_placed_target_takes_the_unit_type_of_its_creation_type_test() -> Nil {
  use <- owned_test.run(60_000)
  // 73667 becomes a CreationTypeEnum 0 creature; 73463 stays 20 and 12919 is 8.
  use changed <- fixture_tables.changed(
    table: "Creature2",
    id: mine_medium,
    with: [#("CreationTypeEnum", Integer(0))],
  )
  let tables = character_tables.content_over(tables: changed)
  let fillers = [
    stored(tables:, id: 1, creature_id: filler, world_id: world),
    stored(tables:, id: 2, creature_id: filler, world_id: 426),
  ]
  let placed =
    placed_by_the_load(
      tables:,
      stored: fillers,
      factions: creature_faction.none(),
    )
  let mines = click_of(placed:, creatures: [mine])
  assert list.length(mines) == 2
    && list.all(mines, fn(row) { row.entity_type == 32 })
    as "CreationTypeEnum 20 is placed as unit type 32, at both its markers"
  let collectible = click_of(placed:, creatures: [12_919])
  assert list.length(collectible) == 3
    && list.all(collectible, fn(row) {
      row.entity_type == 8 && row.world_id == 426
    })
    as "CreationTypeEnum 8 is placed as unit type 8 at 9181, 9182 and 9962"
  let plain = click_of(placed:, creatures: [mine_medium])
  assert list.length(plain) == 2
    && list.all(plain, fn(row) { row.entity_type == 0 })
    as "CreationTypeEnum 0 is placed as unit type 0"
}

pub fn a_target_whose_unit_type_the_server_does_not_start_is_skipped_and_reported_test() -> Nil {
  use <- owned_test.run(60_000)
  // CreationTypeEnum 3 and 9 are their own unit types; 18 pairs with 19, BindPoint.
  list.each([#(3, 3), #(9, 9), #(18, 19)], fn(pair) {
    let #(creation_type, unit_type) = pair
    use changed <- fixture_tables.changed(table: "Creature2", id: mine, with: [
      #("CreationTypeEnum", Integer(creation_type)),
    ])
    let tables = character_tables.content_over(tables: changed)
    let placed =
      placed_by_the_load(
        tables:,
        stored: the_world_holds_spawns(tables:),
        factions: creature_faction.none(),
      )
    assert click_of(placed:, creatures: [mine]) == []
      as "a unit the server does not start is not placed"
    let not_started = fn(objective_id) {
      objective_spawn.Skipped(
        objective_id:,
        why: objective_spawn.NotStarted(creature_id: mine, unit_type:),
      )
    }
    assert list.contains(placed.click_skipped, not_started(21_287))
      && list.contains(placed.click_skipped, not_started(21_313))
      as "both of the mine's objectives are reported with its unit type"
    assert list.any(objective_spawn.report(placed:), fn(line) {
      string.contains(line, "click objective 21287")
      && string.contains(line, "Creature2 73463")
      && string.contains(line, "unit type " <> int.to_string(unit_type))
    })
      as "the report names the objective, the creature and the unit type"
  })
}

pub fn an_objective_of_another_type_places_no_click_target_test() -> Nil {
  use <- owned_test.run(60_000)
  use changed <- fixture_tables.changed(
    table: "QuestObjective",
    id: 21_313,
    with: [#("type", Integer(12))],
  )
  let placed = click_placed_in_world(tables: changed)
  let rows = click_of(placed:, creatures: [mine])
  assert list.length(rows) == 1
    && list.all(rows, fn(row) { close(row.x, -70.4453) })
    as "73463 is placed at 51662 only: objective 21313 is no longer a use"
  assert list.filter(placed.click_skipped, fn(skipped) {
      skipped.objective_id == 21_313
    })
    == []
    as "an objective of another type is no pair"
}

pub fn two_click_objectives_on_one_creature_and_marker_place_once_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objective 21287, the mine's Exile one, now names marker 52899 as 21313 does.
  use changed <- fixture_tables.changed(
    table: "QuestObjective",
    id: 21_287,
    with: [#("worldLocationsIdIndicator00", Integer(dominion_marker))],
  )
  let placed = click_placed_in_world(tables: changed)
  let assert [row] = click_of(placed:, creatures: [mine])
    as "one row of the mine, for two objectives of the same marker"
  assert stands_at(row, x: 72.9871, y: -872.0891, z: 357.634)
}

pub fn two_creatures_at_one_marker_stand_on_its_ring_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objective 21314, 73667's Dominion objective, now names marker 52899, which
  // is 73463's: two creatures stand at it.
  use changed <- fixture_tables.changed(
    table: "QuestObjective",
    id: 21_314,
    with: [#("worldLocationsIdIndicator00", Integer(dominion_marker))],
  )
  let placed = click_placed_in_world(tables: changed)
  let assert [first, second] =
    click_of(placed:, creatures: [mine, mine_medium])
    |> list.filter(fn(row) { close(row.z, 357.634) })
    as "two rows at 52899, 73463 first"
  assert first.creature_id == mine && second.creature_id == mine_medium
  // The ring of half the marker's radius, 0.5: slot 0 of 2 at angle 0, slot 1 at pi.
  assert close(first.x, 72.9871 +. 0.5) as "slot 0 of 2 at angle 0"
  assert close(second.x, 72.9871 -. 0.5) as "slot 1 of 2 at angle pi"
  assert faces(row: first, to_x: 72.9871, to_z: 357.634)
    && faces(row: second, to_x: 72.9871, to_z: 357.634)
    as "each faces the centre"
  assert close(first.y, -872.0891) && close(second.y, -872.0891)
    as "the marker's height"
}

pub fn a_linked_objective_with_no_marker_places_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  use changed <- fixture_tables.changed(
    table: "QuestObjective",
    id: 21_313,
    with: [#("worldLocationsIdIndicator00", Integer(0))],
  )
  let placed = click_placed_in_world(tables: changed)
  let assert [row] = click_of(placed:, creatures: [mine])
    as "73463 is placed at its Exile marker only"
  assert close(row.x, -70.4453)
  assert list.filter(placed.click_skipped, fn(skipped) {
      skipped.objective_id == 21_313
    })
    == []
    as "an objective with no marker is no pair, so it is not reported"
}

pub fn a_marker_with_no_worldlocation2_row_is_skipped_and_reported_test() -> Nil {
  use <- owned_test.run(60_000)
  let no_row = 9_999_999
  use changed <- fixture_tables.changed(
    table: "QuestObjective",
    id: 21_313,
    with: [#("worldLocationsIdIndicator00", Integer(no_row))],
  )
  let placed = click_placed_in_world(tables: changed)
  let assert [row] = click_of(placed:, creatures: [mine])
    as "73463 is placed at its Exile marker only"
  assert close(row.x, -70.4453)
  assert list.contains(
    placed.click_skipped,
    objective_spawn.Skipped(
      objective_id: 21_313,
      why: objective_spawn.NoMarkerRow(marker_id: no_row),
    ),
  )
    as "skipped as having no marker row"
  assert list.any(objective_spawn.report(placed:), fn(line) {
    string.contains(line, "click objective 21313")
    && string.contains(line, "9999999")
  })
    as "the report names the objective and the marker"
}

pub fn a_click_marker_in_a_world_with_no_stored_spawn_is_skipped_and_reported_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.content_tables()
  let elsewhere = [stored(tables:, id: 1, creature_id: filler, world_id: 1387)]
  let placed =
    placed_by_the_load(
      tables:,
      stored: elsewhere,
      factions: creature_faction.none(),
    )
  assert click_of(placed:, creatures: [mine, mine_medium, mine_hard]) == []
    as "no marker of the mines is in a world the server holds spawns for"
  list.each(
    [
      #(21_287, 51_662),
      #(21_340, 51_663),
      #(21_318, 51_664),
      #(21_313, 52_899),
      #(21_314, 52_900),
      #(21_315, 52_901),
    ],
    fn(pair) {
      assert list.contains(
        placed.click_skipped,
        objective_spawn.Skipped(
          objective_id: pair.0,
          why: objective_spawn.NoSpawnsInWorld(
            marker_id: pair.1,
            world_id: world,
          ),
        ),
      )
        as "each pair is skipped with the marker and its world"
    },
  )
  assert list.any(objective_spawn.report(placed:), fn(line) {
    string.contains(line, "click objective 21313")
    && string.contains(line, "World 3460")
  })
    as "the report names the objective and the marker's world"
}

pub fn click_placement_ids_continue_above_stored_and_kill_placed_ids_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.content_tables()
  let held = [
    stored(tables:, id: 70_880, creature_id: filler, world_id: world),
  ]
  let placed =
    placed_by_the_load(tables:, stored: held, factions: creature_faction.none())
  assert of_creatures(placed:, creatures: [boss]) != []
    as "the boss is placed by the kill path"
  assert click_of(placed:, creatures: [mine, mine_medium, mine_hard]) != []
    as "the mines are placed by the click path"
  let numbers_of = fn(rows: List(Row)) {
    list.map(rows, fn(row: Row) {
      let SpawnId(number) = row.id
      number
    })
  }
  let highest_kill = list.fold(numbers_of(placed.rows), 70_880, int.max)
  let clicks = numbers_of(placed.click_rows)
  assert list.all(clicks, fn(number) { number > highest_kill })
    as "above every stored id and every kill-placed id"
  assert list.all(clicks, fn(number) {
    !spawn_source.is_run_only_id(SpawnId(number))
  })
  assert list.length(list.unique(clicks)) == list.length(clicks)
    as "each id is once"
  assert clicks == list.sort(clicks, int.compare) as "counting up"
}

pub fn a_refused_click_row_is_labelled_as_a_click_placement_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.content_tables()
  let placed =
    placed_by_the_load(
      tables:,
      stored: the_world_holds_spawns(tables:),
      factions: creature_faction.none(),
    )
  let assert [kill_row, ..] = of_creatures(placed:, creatures: [boss])
    as "the boss is placed"
  let assert [click_row, ..] = click_of(placed:, creatures: [mine])
    as "the mine is placed"
  let assert [held] = the_world_holds_spawns(tables:)
  let nowhere = 9_999_999
  let kill_row = spawn.Row(..kill_row, world_id: nowhere)
  let click_row = spawn.Row(..click_row, world_id: nowhere)
  let selection =
    spawn.select(
      rows: [spawn.Row(..held, world_id: nowhere), kill_row, click_row],
      tables:,
      formulas: rating_support.formulas(),
      kinds: spawn_support.kinds(),
      vendors: vendor.none(),
      factions: creature_faction.none(),
    )
  let SpawnId(click_number) = click_row.id
  let labelled =
    objective_spawn.labelled(
      refusals: selection.refusals,
      placed: objective_spawn.Placed(
        rows: [kill_row],
        skipped: [],
        click_rows: [click_row],
        click_skipped: [],
      ),
    )
  assert list.map(labelled, fn(refusal) { refusal.table })
    == ["spawn", "kill objective placement", "click target placement"]
    as "each placed row's refusal names its placement; a kill-placed one keeps its name"
  let assert Ok(last) = list.last(labelled)
  assert last.row
    == refusal.RowName(
      name: "Creature2 73463 placed in World 9999999 as spawn id "
      <> int.to_string(click_number),
    )
  assert list.map(labelled, fn(refusal) { refusal.rule })
    == list.map(selection.refusals, fn(refusal) { refusal.rule })
    as "the rule each broke is the selection's own"
}

pub fn the_report_counts_click_targets_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.content_tables()
  let placed =
    placed_by_the_load(
      tables:,
      stored: the_exile_mines_stored(tables:),
      factions: creature_faction.none(),
    )
  assert list.length(placed.click_rows) == 3
    as "the three Dominion mines are placed"
  let skip =
    objective_spawn.Skipped(
      objective_id: 4813,
      why: objective_spawn.NoMarkerRow(marker_id: 9_999_999),
    )
  let lines =
    objective_spawn.report(
      placed: objective_spawn.Placed(
        ..placed,
        rows: [],
        skipped: [],
        click_skipped: [skip],
      ),
    )
  let from_click =
    list.drop_while(lines, fn(line) {
      !string.starts_with(line, "click objectives:")
    })
  let assert [click_line, skip_line] = from_click
    as "the click line, then the skip"
  assert click_line
    == "click objectives: placed 3 creatures with no stored spawn at their marker, skipped 1 pairs"
  assert string.starts_with(skip_line, "click objective 4813")
    && string.contains(skip_line, "9999999")
}

/// With the world database's spawn rows and the client's real tables, what the
/// placement does for the click objectives. The expected totals are counts over
/// the same tables and rows made apart from the server's code, by a scratch
/// Python script that reads the Creature2, Prerequisite, Quest2, QuestObjective and
/// WorldLocation2 rows (`table_rows` dumps) and `spawn.tsv`: it follows each
/// creature's questAnim and prerequisite links (type 43 conditions of comparison
/// 1, nested through type 11) to an objective of type 5 or 32 with a marker, serves
/// each stored row of the creature to the marker it stands nearest in its own
/// world, and places the creature at each marker no row serves, in a world holding
/// a stored row, as the unit type its CreationTypeEnum pairs with:
/// - 831 pairs of an objective and a linked creature, over 739 creatures;
/// - 344 rows placed, by world 22: 111, 51: 114, 426: 5, 990: 2, 1061: 106, 1387:
///   3 and 3460: 3, and by unit type 0: 109, 8: 135, 10: 71, 11: 4, 14: 2 and 32: 23;
/// - 3 unplaced pairs of a unit type the server does not start.
pub fn every_click_objective_with_a_marker_places_or_has_a_spawn_test() -> Nil {
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
  let factions = spawn_support.the_boss_is_given_233(tables:)
  let placed = placed_by_the_load(tables:, stored:, factions:)
  assert list.length(placed.click_rows) == 344
    as "the rows placed, by the count over the tables"
  let placed_in = fn(world_id) {
    list.count(placed.click_rows, fn(row: Row) { row.world_id == world_id })
  }
  assert list.map([22, 51, 426, 990, 1061, 1387, 3460], placed_in)
    == [111, 114, 5, 2, 106, 3, 3]
    as "the rows placed in each world"
  let placed_as = fn(entity_type) {
    list.count(placed.click_rows, fn(row: Row) {
      row.entity_type == entity_type
    })
  }
  assert list.map([0, 8, 10, 11, 14, 32], placed_as) == [109, 135, 71, 4, 2, 23]
    as "the rows placed as each unit type"
  let worlds = set.from_list(list.map(stored, fn(row: Row) { row.world_id }))
  assert list.all(placed.click_rows, fn(row: Row) {
    set.contains(worlds, row.world_id)
  })
    as "no row is placed in a world the server holds no spawns for"
  assert list.count(placed.click_skipped, fn(skipped) {
      case skipped.why {
        objective_spawn.NotStarted(..) -> True
        _ -> False
      }
    })
    == 3
    as "the pairs whose unit type the server does not start"
  let skipped_for = fn(is_that) {
    list.count(placed.click_skipped, fn(skipped) { is_that(skipped.why) })
  }
  assert skipped_for(fn(why) {
      case why {
        objective_spawn.NoMarkerRow(..) -> True
        _ -> False
      }
    })
    == 5
    as "the markers the client has no row of"
  assert skipped_for(fn(why) {
      case why {
        objective_spawn.NoSpawnsInWorld(..) -> True
        _ -> False
      }
    })
    == 162
    as "the (objective, marker) pairs in a world with no stored spawn"
  // Creature2 12919 is served at all three of objective 4813's markers by stored
  // rows, so none of them is placed.
  assert click_of(placed:, creatures: [12_919]) == []
    as "a creature with stored rows near each marker places none"
  // The load's checks refuse none of the placed rows, which would stop the start,
  // and leave none out.
  let selection =
    spawn.select(
      rows: placed.click_rows,
      tables:,
      formulas: rating_support.formulas(),
      kinds: spawn_support.turret_kinds(),
      vendors: vendor.none(),
      factions:,
    )
  assert selection.refusals == []
    as "a placed row that the checks refuse would stop the server's start"
  // Creature2 13133 (Protostar X-97 Gravity Defiance System, factionId 0 in the
  // client's table, no chosen faction) is the one placed creature the checks leave
  // out: a unit with no faction is not created (`LeftOut.NoFaction`).
  let left_out =
    list.flat_map(selection.coverage, fn(coverage) {
      list.filter_map(coverage.left_out, fn(pair) {
        case pair.1 {
          0 -> Error(Nil)
          count -> Ok(#(coverage.world_id, pair.0, count))
        }
      })
    })
  assert left_out == [#(22, spawn.NoFaction, 1)]
    as "the placed creatures the checks leave out, by world and reason"
  assert list.all(selection.coverage, fn(coverage) {
    coverage.objects_dead == 0
  })
    as "no placed static object is created dead"
  let sent =
    list.fold(selection.coverage, 0, fn(total, coverage) {
      total
      + coverage.started
      + list.fold(coverage.objects_sent, 0, fn(count, pair) { count + pair.1 })
      + list.fold(coverage.other_types, 0, fn(count, pair) { count + pair.1 })
    })
  assert sent + 1 == 344 as "every placed row but the one left out starts"
}
