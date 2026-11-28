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
////   group's order, cycling; a placed row takes the id from 1,000,000,000 up that the
////   rank of its kind, marker, creature and nth gives (the ranks below).

import character_tables
import client_tables
import content_support
import database_support
import envoy
import fixture_tables
import genesis_prime/content/refusal
import genesis_prime/game/click_objective
import genesis_prime/game/kill_objective
import genesis_prime/game/place_objective
import genesis_prime/game/target_group
import genesis_prime/import_world_data
import genesis_prime/shared/activate
import genesis_prime/shared/creature_unit_type
import genesis_prime/shared/quest_row
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id, QuestObjectiveId}
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store
import genesis_prime/table/quest_objective
import genesis_prime/table/world_location2
import genesis_prime/terrain.{type Ground}
import genesis_prime/world_map/checklist_index.{Candidate}
import genesis_prime/world_map/creature_faction
import genesis_prime/world_map/objective_spawn.{type Placed}
import genesis_prime/world_map/spawn.{type Row}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/spawn_source
import gleam/dict.{type Dict}
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
import qcheck
import rating_support
import spawn_support
import terrain_support
import unitest

const world = 3460

const boss = 73_499

const turret = 74_862

/// A creature that no kill objective names, which a test stores in World 3460 so
/// that the world is one the server holds spawns for.
const filler = 4064

/// The id of the first spawn the server places for a quest: a placed spawn's id is this
/// plus the rank of its kind, marker, creature and nth (genesis_prime/world_map/objective_spawn).
const first_placed_id = 1_000_000_000

/// The largest id `spawn.id` and a used spawn hold: both are 32-bit integers (migrations
/// 0008 and 0052).
const int4_largest = 2_147_483_647

/// The number of the row's id.
fn number_of(row: Row) -> Int {
  let SpawnId(number) = row.id
  number
}

/// The numbers of the rows' ids, in the order of the rows.
fn numbers_of(rows: List(Row)) -> List(Int) {
  list.map(rows, number_of)
}

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
  placed_with_kills(tables:, stored:, factions:, kills: set.new())
}

/// `placed_by_the_load` with these objectives as the kill table's rows.
fn placed_with_kills(
  tables tables: store.Tables,
  stored stored: List(Row),
  factions factions: creature_faction.Factions,
  kills kills: Set(Int),
) -> Placed {
  placed_with_tables(tables:, stored:, factions:, kills:, clicks: set.new())
}

/// `placed_by_the_load` with these objectives as the kill table's and the click table's rows.
fn placed_with_tables(
  tables tables: store.Tables,
  stored stored: List(Row),
  factions factions: creature_faction.Factions,
  kills kills: Set(Int),
  clicks clicks: Set(Int),
) -> Placed {
  objective_spawn.place(
    tables:,
    stored:,
    factions:,
    kinds: spawn_support.turret_kinds(),
    kills:,
    clicks:,
    grounds: dict.new(),
  )
}

/// The placement over the fixture's tables with these grounds by world, and no
/// objective in the kill or click table.
fn placed_over(
  tables tables: store.Tables,
  stored stored: List(Row),
  grounds grounds: Dict(Int, Ground),
) -> Placed {
  objective_spawn.place(
    tables:,
    stored:,
    factions: creature_faction.none(),
    kinds: spawn_support.turret_kinds(),
    kills: set.new(),
    clicks: set.new(),
    grounds:,
  )
}

/// The rows of the world database, imported into a database of the test's own and
/// read back (with the migrations' seeded rows).
fn stored_by_the_world_database() -> List(Row) {
  let assert Ok(folder) = envoy.get("GENESIS_WORLD_DATA")
    as "the guard saw the variable"
  let database = database_support.new_database(on: database_support.shared())
  let assert Ok(_) =
    import_world_data.import_spawns(
      db: content_support.connect(database:),
      folder:,
    )
    as "the world database imports"
  content_support.stored_spawns(database:)
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
      vendor_creatures: set.new(),
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
      kills: set.new(),
      clicks: set.new(),
      grounds: dict.new(),
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
      vendor_creatures: set.new(),
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
        unread_links: [],
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

/// Each (world, x, z) at which two or more of the rows stand, to the millimetre.
fn shared_places(rows rows: List(Row)) -> List(#(Int, Int, Int)) {
  list.group(rows, fn(row) {
    #(row.world_id, float.round(row.x *. 1000.0), float.round(row.z *. 1000.0))
  })
  |> dict.to_list
  |> list.filter_map(fn(place) {
    case place.1 {
      [_, _, ..] -> Ok(place.0)
      _ -> Error(Nil)
    }
  })
  |> list.sort(fn(left, right) { int.compare(left.1, right.1) })
}

pub fn objectives_whose_markers_are_shared_place_no_two_rows_at_one_place_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objective 4564 (quest 3479, TargetGroup 7288: Creature2 7287 and the group
  // 1463) and 4565 (quest 3480, TargetGroup 1463: 12844, 11945, 11948, 13116,
  // 13117, 13959 and 51126) are type 8, count 8, on markers 12155 to 12158 of
  // World 426 (`table_rows -- QuestObjective 4564 4565`, `-- TargetGroup 7287 7288
  // 1463`, `-- WorldLocation2 12155 12156 12157 12158`). World 426 stores rows of 11945, 11948,
  // 12844, 13116 and 51126, so the creatures to place are 36331, 36335, 13117
  // and 13959. Marker 12157's centre is (4049.0891, -735.689, -5470.0864) with radius
  // 78.62, so its ring slots are 39.31 either side of the centre along x.
  let tables = character_tables.content_tables()
  let held =
    list.index_map(
      [11_945, 11_948, 12_844, 13_116, 51_126],
      fn(creature_id, index) {
        stored(tables:, id: index + 1, creature_id:, world_id: 426)
      },
    )
  let placed =
    placed_by_the_load(tables:, stored: held, factions: creature_faction.none())
  let rows = list.filter(placed.rows, fn(row: Row) { row.world_id == 426 })
  let standing_at = fn(x, z) {
    list.filter(rows, fn(row: Row) { close(row.x, x) && close(row.z, z) })
  }
  assert list.map(standing_at(4088.4006, -5470.0864), fn(row) {
      row.creature_id
    })
    == [13_117]
    as "one Creature2 13117 stands at marker 12157's first ring slot, not one for each of the two objectives"
  assert list.map(standing_at(4009.77705, -5470.0864), fn(row) {
      row.creature_id
    })
    == [13_117]
    as "one Creature2 13117 stands at marker 12157's second ring slot"
  assert shared_places(rows:) == []
    as "no two rows of the two objectives stand at one place"
  // Objective 4564 asks for 36331 twice at marker 12155, 36335 twice at 12156 and
  // 13117 and 13959 twice each at 12157 and 12158; 4565 for 13117 twice at 12155, 13959
  // twice at 12156 and the same as 4564 at the other two. Each objective keeps what
  // it asked of each marker, and a creature both ask of a marker stands once there.
  assert list.map([36_331, 36_335, 13_117, 13_959], fn(creature_id) {
      list.length(of_creatures(placed:, creatures: [creature_id]))
    })
    == [2, 2, 4, 4]
    as "no creature either objective asked for is left out, and none stands twice at a marker"
}

pub fn no_two_creatures_the_real_tables_place_stand_at_one_place_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("world_data")
  use <- unitest.guard(client_tables.present())
  use <- unitest.guard(envoy.get("GENESIS_WORLD_DATA") != Error(Nil))
  let tables = client_tables.with_content_tables()
  let placed =
    placed_by_the_load(
      tables:,
      stored: stored_by_the_world_database(),
      factions: spawn_support.the_boss_is_given_233(tables:),
    )
  let shared = shared_places(rows: list.append(placed.rows, placed.click_rows))
  assert shared == []
    as "no two placed creatures, kill or click, stand at one place of a world"
}

/// What the ground under a marker's ring slots is, to the slot's height.
type Standing {
  /// The slot stands on the ground read at it, a planted raw value's height.
  OnGround(raw: Int)
  /// The slot keeps its marker's own height.
  AtMarkerHeight
}

/// A marker whose centre and ring-slot chunks hold these raw values (a slot with
/// `Error(Nil)` has no chunk), and where each of the three slots stands.
type RingGround {
  RingGround(
    why: String,
    centre: Int,
    first_slot: Result(Int, Nil),
    third_slot: Result(Int, Nil),
    stands: List(Standing),
  )
}

pub fn a_ring_slot_stands_on_the_ground_read_at_it_when_its_marker_is_on_the_ground_and_the_read_is_in_the_ring_band_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objective 21290: Creature2 73492 and 73567, count 3, marker 51740 in World 3460
  // at (-142.06599, -860.46375, 556.80902), radius 38, so slot i of 3 stands 19 from
  // the centre at the angle 2 pi i / 3 from the +x axis towards +z. The marker's
  // centre and slot 1 are in the 32-unit chunk x -160 to -128, z 544 to 576;
  // the slot 0 is in the chunk beside it along x and the slot 2 in the chunk before
  // it along z. A raw value of 9500 is the height -860.464, the marker's own, and
  // each raw step is 0.125 (`terrain_support.height`).
  let centre_raw = 9500
  let base =
    RingGround(
      why: "a slot whose ground is 4.6 above its marker's centre stands on it, a slot in its marker's chunk on the chunk's ground, and a slot with no ground read at the marker's height",
      centre: centre_raw,
      first_slot: Ok(centre_raw + 37),
      third_slot: Error(Nil),
      stands: [OnGround(centre_raw + 37), OnGround(centre_raw), AtMarkerHeight],
    )
  let cases = [
    base,
    RingGround(
      why: "a marker whose centre is 100 below the ground (an interior) keeps its height at every slot",
      centre: centre_raw + 800,
      first_slot: Ok(centre_raw + 837),
      third_slot: Ok(centre_raw + 800),
      stands: [AtMarkerHeight, AtMarkerHeight, AtMarkerHeight],
    ),
    RingGround(
      why: "a marker whose centre is 100 above the ground keeps its height at every slot",
      centre: centre_raw - 800,
      first_slot: Ok(centre_raw - 763),
      third_slot: Ok(centre_raw - 800),
      stands: [AtMarkerHeight, AtMarkerHeight, AtMarkerHeight],
    ),
    RingGround(
      ..base,
      why: "a centre 1.875 below the ground is on the ground, inside the 2 the client lifts a unit by",
      centre: centre_raw + 15,
      first_slot: Ok(centre_raw + 52),
      stands: [
        OnGround(centre_raw + 52),
        OnGround(centre_raw + 15),
        AtMarkerHeight,
      ],
    ),
    RingGround(
      ..base,
      why: "a centre 2.125 below the ground is not on it",
      centre: centre_raw + 17,
      first_slot: Ok(centre_raw + 54),
      stands: [AtMarkerHeight, AtMarkerHeight, AtMarkerHeight],
    ),
    RingGround(
      ..base,
      why: "a slot whose ground is 20 above or below the centre, inside the band of the ring's radius 19 plus the lift 2, stands on it",
      first_slot: Ok(centre_raw + 160),
      third_slot: Ok(centre_raw - 160),
      stands: [
        OnGround(centre_raw + 160),
        OnGround(centre_raw),
        OnGround(centre_raw - 160),
      ],
    ),
    RingGround(
      ..base,
      why: "a slot whose ground is 21.25 above or below the centre, outside that band (a pit, a cliff), keeps the centre's height while a slot inside the band stands on the ground",
      first_slot: Ok(centre_raw + 170),
      third_slot: Ok(centre_raw - 170),
      stands: [AtMarkerHeight, OnGround(centre_raw), AtMarkerHeight],
    ),
    RingGround(
      ..base,
      why: "a slot whose chunk holds the raw value 0x1FFF everywhere, the floor of -1024.09 the client's shared default holds, keeps the centre's height",
      first_slot: Ok(0x1FFF),
      third_slot: Ok(0x1FFF),
      stands: [AtMarkerHeight, OnGround(centre_raw), AtMarkerHeight],
    ),
  ]
  let tables = character_tables.content_tables()
  let centre_x = -142.06599
  let centre_z = 556.80902
  let slot_at = fn(index) {
    let angle = 2.0 *. maths.pi() *. int.to_float(index) /. 3.0
    #(
      centre_x +. 19.0 *. maths.cos(angle),
      centre_z +. 19.0 *. maths.sin(angle),
    )
  }
  list.each(cases, fn(row) {
    let #(first_x, first_z) = slot_at(0)
    let #(third_x, third_z) = slot_at(2)
    let chunks =
      list.flatten([
        [#(centre_x, centre_z, row.centre)],
        case row.first_slot {
          Ok(raw) -> [#(first_x, first_z, raw)]
          Error(Nil) -> []
        },
        case row.third_slot {
          Ok(raw) -> [#(third_x, third_z, raw)]
          Error(Nil) -> []
        },
      ])
    let placed =
      placed_over(
        tables:,
        stored: the_world_holds_spawns(tables:),
        grounds: dict.from_list([
          #(world, terrain_support.ground_with_chunks(chunks:)),
        ]),
      )
    let rows = of_creatures(placed:, creatures: [73_492, 73_567])
    assert list.length(rows) == 3 as row.why
    assert list.map(rows, fn(placed_row) { placed_row.y })
      |> list.zip(row.stands)
      |> list.all(fn(pair) {
        case pair.1 {
          OnGround(raw:) -> close(pair.0, terrain_support.height(raw:))
          AtMarkerHeight -> close(pair.0, -860.46375)
        }
      })
      as row.why
  })
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

pub fn placement_ids_are_at_or_above_the_first_placed_id_whatever_the_stored_ids_are_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = character_tables.content_tables()
  // Stored rows of another world hide no placement, and the one in World 3460 makes it
  // a world with spawns. Stored ids of 1, 2 and 70,880 move no placed id.
  let held = [
    stored(tables:, id: 1, creature_id: boss, world_id: 1387),
    stored(tables:, id: 70_880, creature_id: boss, world_id: 1387),
    stored(tables:, id: 2, creature_id: filler, world_id: world),
  ]
  let placed =
    placed_by_the_load(tables:, stored: held, factions: creature_faction.none())
  assert placed.rows != []
  let numbers = numbers_of(list.append(placed.rows, placed.click_rows))
  assert list.all(numbers, fn(number) {
    number >= first_placed_id && number <= int4_largest
  })
    as "at or above the first placed id and inside the integer column of a stored id and of a used spawn (0008, 0052)"
  assert list.all(numbers, fn(number) {
    !spawn_source.is_run_only_id(SpawnId(number))
  })
    as "never a run-only id"
  assert list.length(list.unique(numbers)) == list.length(numbers)
    as "each id is once"
}

/// Each rank below is the rank of one (kind, marker, creature, nth) among those every type 5
/// objective and every kill or linked-use objective of the fixture's rows can ask a placement
/// for: kills first, then clicks, each sorted by marker and then creature, each triple holding
/// as many ranks as the most slots any objective gives that creature at that marker (a count
/// dealt over the objective's markers in one world). The numbers were worked out apart from the
/// server's code, by a scratch Python script over the committed rows of QuestObjective,
/// TargetGroup, WorldLocation2, Creature2, Quest2 and Prerequisite, which finds 106 triples
/// holding 415 ranks.
fn ranked(ranks ranks: List(Int)) -> List(Int) {
  list.map(ranks, fn(rank) { first_placed_id + rank })
}

pub fn a_placed_id_is_the_first_placed_id_plus_the_rank_of_its_kind_marker_creature_and_nth_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = character_tables.content_tables()
  let placed =
    placed_by_the_load(
      tables:,
      stored: the_world_holds_spawns(tables:),
      factions: creature_faction.none(),
    )
  // Objective 21286 counts 5 of Creature2 73464 at marker 51739: the triple (kill, 51739,
  // 73464) starts at rank 372 and holds five.
  assert numbers_of(of_creatures(placed:, creatures: [73_464]))
    == ranked(ranks: [372, 373, 374, 375, 376])
    as "the five rows of the boss take the five ranks of its triple, nth 0 to 4"
  // Objective 21290 counts 3 of TargetGroup 14356 (73492, 73567) at marker 51740: the two
  // triples hold three each, from 377 and 380, and the cycle stands 73492, 73567, 73492.
  assert numbers_of(of_creatures(placed:, creatures: [73_492, 73_567]))
    == ranked(ranks: [377, 380, 378])
    as "a creature of the group stood twice takes nth 0 and 1 of its own triple"
  assert numbers_of(of_creatures(placed:, creatures: [boss]))
    == ranked(ranks: [383])
    as "objectives 21296 and 21310 name the boss at marker 51744 and place it once"
  assert numbers_of(of_creatures(placed:, creatures: [turret]))
    == ranked(ranks: [390, 391])
    as "one turret at each of markers 52902 and 52903, a triple of their own each"
  let mines = click_of(placed:, creatures: [mine, mine_medium, mine_hard])
  assert list.map(mines, fn(row: Row) { row.creature_id })
    == [mine, mine_medium, mine_hard, mine, mine_medium, mine_hard]
    as "the click rows are the mines at the Exile markers 51662 to 51664, then the Dominion markers 52899 to 52901"
  assert numbers_of(mines) == ranked(ranks: [409, 410, 411, 412, 413, 414])
    as "the click triples come after every kill triple (415 ranks less the click ones)"
}

/// The (Creature2 id, rank) of the rows placed of these creatures, sorted.
fn ranks_of(
  placed placed: Placed,
  creatures creatures: List(Int),
) -> List(#(Int, Int)) {
  of_creatures(placed:, creatures:)
  |> list.map(fn(row: Row) {
    #(row.creature_id, number_of(row) - first_placed_id)
  })
  |> list.sort(fn(a, b) { int.compare(a.0 * 1000 + a.1, b.0 * 1000 + b.1) })
}

type Kept {
  Kept(why: String, stored: List(#(Int, Int, Int)), placed: List(#(Int, Int)))
}

pub fn adding_or_deleting_stored_rows_leaves_each_surviving_placed_id_unchanged_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = character_tables.content_tables()
  // The stored rows are (id, creature, world). The expected pairs are (creature, rank) of
  // the boss 73464 (objective 21286) and of the group 14356's 73492 and 73567 (objective 21290),
  // the ranks of `a_placed_id_is_the_first_placed_id_plus_the_rank_...`.
  let whole = [
    #(73_464, 372),
    #(73_464, 373),
    #(73_464, 374),
    #(73_464, 375),
    #(73_464, 376),
    #(73_492, 377),
    #(73_492, 378),
    #(73_567, 380),
  ]
  let one_row = #(1, filler, world)
  let cases = [
    Kept(
      why: "the world's one row, and an unrelated row in another world",
      stored: [one_row, #(2, filler, 1387)],
      placed: whole,
    ),
    Kept(
      why: "a row with a higher id than every other",
      stored: [one_row, #(2, filler, 1387), #(70_880, filler, 1387)],
      placed: whole,
    ),
    Kept(
      why: "the world's row deleted and another with id 9 added in the world",
      stored: [#(9, filler, world)],
      placed: whole,
    ),
    Kept(
      why: "a stored row of the boss: its five placed rows go, the group's stay",
      stored: [one_row, #(5, 73_464, world)],
      placed: [#(73_492, 377), #(73_492, 378), #(73_567, 380)],
    ),
    Kept(
      why: "a stored row of 73567: the group stands 73492 three times, its first two ids unchanged and the third the next of its triple, and 73567's id goes",
      stored: [one_row, #(5, 73_567, world)],
      placed: [
        #(73_464, 372),
        #(73_464, 373),
        #(73_464, 374),
        #(73_464, 375),
        #(73_464, 376),
        #(73_492, 377),
        #(73_492, 378),
        #(73_492, 379),
      ],
    ),
  ]
  list.each(cases, fn(row) {
    let held =
      list.map(row.stored, fn(one) {
        stored(tables:, id: one.0, creature_id: one.1, world_id: one.2)
      })
    let placed =
      placed_by_the_load(
        tables:,
        stored: held,
        factions: creature_faction.none(),
      )
    assert ranks_of(placed:, creatures: [73_464, 73_492, 73_567]) == row.placed
      as row.why
  })
}

pub fn a_placed_id_names_one_creature_and_world_whatever_stored_rows_are_added_or_deleted_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = character_tables.content_tables()
  // Creatures the fixture places in Worlds 3460 and 22, as (creature, world).
  let pool = [
    #(73_464, world),
    #(73_492, world),
    #(73_567, world),
    #(boss, world),
    #(51_440, 22),
    #(26_436, 22),
  ]
  // A run's stored rows are the drawn ones alone, each with an id of its own below the first
  // placed id, so a run holds a row in no world, one world or both, and two runs differ in
  // which worlds hold a stored row.
  let rows_of = fn(drawn: List(#(Int, Int))) {
    list.index_map(drawn, fn(one, position) {
      let #(choice, high) = one
      let assert Ok(#(creature_id, world_id)) =
        list.drop(pool, choice) |> list.first
        as "the choice is an index of the pool"
      stored(tables:, id: 10 + high * 20 + position, creature_id:, world_id:)
    })
  }
  let rows_drawn =
    qcheck.generic_list(
      elements_from: qcheck.tuple2(
        qcheck.bounded_int(from: 0, to: 5),
        qcheck.bounded_int(from: 0, to: 9_000_000),
      ),
      length_from: qcheck.bounded_int(from: 0, to: 12),
    )
  // 100 draws: each places twice over the fixture's tables, which takes about 5 ms.
  use drawn <- qcheck.run(
    qcheck.default_config() |> qcheck.with_test_count(100),
    qcheck.tuple2(rows_drawn, rows_drawn),
  )
  let #(first_run, second_run) = drawn
  let named_by_id = fn(drawn) {
    let placed =
      placed_by_the_load(
        tables:,
        stored: rows_of(drawn),
        factions: creature_faction.none(),
      )
    let rows = list.append(placed.rows, placed.click_rows)
    let named =
      list.map(rows, fn(row: Row) {
        #(number_of(row), #(row.creature_id, row.world_id))
      })
    assert list.length(list.unique(list.map(named, fn(one) { one.0 })))
      == list.length(named)
      as "an id is once in a run"
    assert list.all(named, fn(one) { one.0 >= first_placed_id })
      as "an id is at or above the first placed id"
    dict.from_list(named)
  }
  let first_named = named_by_id(first_run)
  let second_named = named_by_id(second_run)
  dict.each(first_named, fn(number, named) {
    case dict.get(second_named, number) {
      Ok(other) -> {
        assert other == named
          as "an id of both runs names the same creature in the same world"
        Nil
      }
      Error(Nil) -> Nil
    }
  })
}

pub fn a_creature_a_kill_and_a_click_objective_both_stand_at_one_marker_gets_two_ids_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = character_tables.content_tables()
  // Objective 10256 (quest 6591) is a type 2 kill of Creature2 51440 and objective 16170 a
  // type 5 click of it, both at marker 40836 in World 22 (`table_rows -- QuestObjective
  // 10256 16170`): the creature stands as a kill row and as a click row. The triples (kill,
  // 40836, 51440) and (click, 40836, 51440) are ranks 364 and 408.
  let placed =
    placed_with_tables(
      tables:,
      stored: [stored(tables:, id: 1, creature_id: filler, world_id: 22)],
      factions: creature_faction.none(),
      kills: set.new(),
      clicks: set.from_list([16_170]),
    )
  assert numbers_of(of_creatures(placed:, creatures: [51_440]))
    == ranked(ranks: [364])
    as "the kill row takes the rank of the kill triple"
  assert numbers_of(click_of(placed:, creatures: [51_440]))
    == ranked(ranks: [408])
    as "the click row takes the rank of the click triple, above the kill row's"
}

pub fn a_stored_spawn_at_or_above_the_first_placed_id_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = character_tables.content_tables()
  let rows =
    list.map(
      [first_placed_id - 1, first_placed_id, first_placed_id + 1],
      fn(id) { stored(tables:, id:, creature_id: filler, world_id: world) },
    )
  let rule =
    "its id is at or above 1000000000, where the spawns the server places begin"
  assert objective_spawn.refusals(stored: rows)
    == [
      refusal.Refusal(
        table: "spawn",
        row: refusal.RowId(first_placed_id),
        rule:,
      ),
      refusal.Refusal(
        table: "spawn",
        row: refusal.RowId(first_placed_id + 1),
        rule:,
      ),
    ]
    as "the rows at and above the first placed id are refused, the one below is not"
}

/// The placement over the client's whole tables and the kill and click rows the migrations
/// seed, with these stored rows.
fn placed_over_the_real_tables(
  tables tables: store.Tables,
  stored stored: List(Row),
  kills kills: Set(Int),
  clicks clicks: Set(Int),
) -> Placed {
  placed_with_tables(
    tables:,
    stored:,
    factions: creature_faction.none(),
    kills:,
    clicks:,
  )
}

/// The creature and the world of each id a placement gives, each id once.
fn named_ids(placed placed: Placed) -> Dict(Int, #(Int, Int)) {
  let rows = list.append(placed.rows, placed.click_rows)
  let named =
    dict.from_list(
      list.map(rows, fn(row: Row) {
        #(number_of(row), #(row.creature_id, row.world_id))
      }),
    )
  assert dict.size(named) == list.length(rows) as "each id is once"
  named
}

pub fn a_placed_id_survives_every_change_of_the_real_stored_rows_test() -> Nil {
  // deadline: 11 s measured: the world database is imported and the client's tables placed over once for each change
  use <- owned_test.run(600_000)
  use <- unitest.tag("world_data")
  use <- unitest.guard(client_tables.present())
  use <- unitest.guard(envoy.get("GENESIS_WORLD_DATA") != Error(Nil))
  let stored = stored_by_the_world_database()
  let tables = client_tables.with_content_tables()
  let kills = content_support.objective_ids(table: kill_objective.table)
  let clicks = content_support.objective_ids(table: click_objective.table)
  let run = fn(rows) {
    named_ids(placed: placed_over_the_real_tables(
      tables:,
      stored: rows,
      kills:,
      clicks:,
    ))
  }
  let baseline = run(stored)
  let highest =
    list.fold(stored, 0, fn(highest, row) { int.max(highest, number_of(row)) })
  let assert Ok(template) =
    list.find(stored, fn(row: Row) { row.entity_type == 0 })
    as "the world database holds a creature row"
  let one_per_world =
    list.fold(stored, dict.new(), fn(found, row: Row) {
      case dict.has_key(found, row.world_id) {
        True -> found
        False -> dict.insert(found, row.world_id, row)
      }
    })
    |> dict.values
  // The (world, creature) pairs a change can matter for: stored rows of a creature the
  // baseline places somewhere, and the pairs the baseline places.
  let placed_creatures =
    set.from_list(list.map(dict.values(baseline), fn(named) { named.0 }))
  let every_nth = fn(items: List(a), step: Int, most: Int) -> List(a) {
    list.index_map(items, fn(item, index) { #(index, item) })
    |> list.filter(fn(one) { one.0 % step == 0 })
    |> list.map(fn(one) { one.1 })
    |> list.take(most)
  }
  let deletions =
    list.filter_map(stored, fn(row: Row) {
      case set.contains(placed_creatures, row.creature_id) {
        True -> Ok(#(row.world_id, row.creature_id))
        False -> Error(Nil)
      }
    })
    |> list.unique
    |> list.sort(fn(a, b) {
      int.compare(a.1 * 100_000 + a.0, b.1 * 100_000 + b.0)
    })
    |> every_nth(7, 12)
  let additions =
    dict.values(baseline)
    |> list.unique
    |> list.sort(fn(a, b) {
      int.compare(a.0 * 100_000 + a.1, b.0 * 100_000 + b.1)
    })
    |> every_nth(9, 8)
  // The worlds the baseline places rows in, from the lowest: the change that leaves one of
  // them with no stored row, and the change that leaves it with one row, are the ones that
  // change which worlds hold a stored row.
  let placed_worlds =
    dict.values(baseline)
    |> list.map(fn(named) { named.1 })
    |> list.unique
    |> list.sort(int.compare)
  let some_placed_worlds =
    list.flatten([
      list.take(placed_worlds, 2),
      every_nth(placed_worlds, 5, 3),
      list.take(list.reverse(placed_worlds), 2),
    ])
    |> list.unique
  let changes =
    list.flatten([
      [
        #("one stored row per world", one_per_world),
        #("a stored row above the highest id", [
          spawn.Row(..template, id: SpawnId(highest + 1)),
          ..stored
        ]),
        #(
          "the highest stored row deleted",
          list.filter(stored, fn(row) { number_of(row) != highest }),
        ),
      ],
      list.map(deletions, fn(pair) {
        #(
          "every stored row of creature "
            <> int.to_string(pair.1)
            <> " in World "
            <> int.to_string(pair.0)
            <> " deleted",
          list.filter(stored, fn(row: Row) {
            #(row.world_id, row.creature_id) != pair
          }),
        )
      }),
      list.map(some_placed_worlds, fn(world_id) {
        #(
          "every stored row of World " <> int.to_string(world_id) <> " deleted",
          list.filter(stored, fn(row: Row) { row.world_id != world_id }),
        )
      }),
      list.map(some_placed_worlds, fn(world_id) {
        #(
          "every stored row of World "
            <> int.to_string(world_id)
            <> " replaced by one",
          [
            spawn.Row(..template, id: SpawnId(highest + 1), world_id:),
            ..list.filter(stored, fn(row: Row) { row.world_id != world_id })
          ],
        )
      }),
      list.map(additions, fn(pair) {
        #(
          "a stored row of creature "
            <> int.to_string(pair.0)
            <> " in World "
            <> int.to_string(pair.1)
            <> " added",
          [
            spawn.Row(
              ..template,
              id: SpawnId(highest + 1),
              creature_id: pair.0,
              world_id: pair.1,
            ),
            ..stored
          ],
        )
      }),
    ])
  assert list.all(dict.keys(baseline), fn(number) {
    number >= first_placed_id && number <= int4_largest
  })
    as "every placed id is at or above the first placed id and inside the integer column"
  let after = list.map(changes, fn(change) { #(change.0, run(change.1)) })
  list.each(after, fn(change) {
    let #(why, named) = change
    assert list.all(dict.keys(named), fn(number) {
      number >= first_placed_id && number <= int4_largest
    })
      as {
        why
        <> ": every placed id is at or above the first placed id and inside the integer column"
      }
    dict.each(baseline, fn(number, was) {
      case dict.get(named, number) {
        Ok(now) -> {
          assert now == was
            as {
              why
              <> ": an id of the baseline names the same creature in the same world"
            }
          Nil
        }
        Error(Nil) -> Nil
      }
    })
  })
  assert list.any(after, fn(change) {
    set.from_list(dict.keys(change.1)) != set.from_list(dict.keys(baseline))
  })
    as "some change adds or removes a placed row, so the runs are not the baseline again"
  assert list.any(after, fn(change) {
    string.starts_with(change.0, "every stored row of World ")
    && string.ends_with(change.0, " deleted")
    && dict.size(change.1) < dict.size(baseline)
  })
    as "deleting every stored row of a world that holds placed rows removes placed rows"
  let placed = placed_over_the_real_tables(tables:, stored:, kills:, clicks:)
  let pyrius = 51_440
  assert numbers_of(of_creatures(placed:, creatures: [pyrius]))
    != numbers_of(click_of(placed:, creatures: [pyrius]))
    as "marker 40836's Creature2 51440 is a kill row and a click row, with ids of their own"
}

pub fn the_placed_checklist_targets_of_the_real_tables_take_the_indexes_after_the_stored_ones_test() -> Nil {
  // deadline: 20 s measured: the world database is imported, and the client's tables placed over and the checklist indexes of every spawn assigned once
  use <- owned_test.run(600_000)
  use <- unitest.tag("world_data")
  use <- unitest.guard(client_tables.present())
  use <- unitest.guard(envoy.get("GENESIS_WORLD_DATA") != Error(Nil))
  let stored = stored_by_the_world_database()
  let tables = client_tables.with_content_tables()
  let placed =
    placed_over_the_real_tables(
      tables:,
      stored:,
      kills: content_support.objective_ids(table: kill_objective.table),
      clicks: content_support.objective_ids(table: click_objective.table),
    )
  let placed_rows = list.append(placed.rows, placed.click_rows)
  let candidates =
    list.map(list.append(stored, placed_rows), fn(row: Row) {
      let assert Ok(creature) =
        creature2.get(tables, Creature2Id(row.creature_id))
        as "the client holds the creature of every row"
      Candidate(
        spawn: row.id,
        unit: target_group.Unit(
          creature_id: Creature2Id(row.creature_id),
          faction_id: id.Faction2Id(row.faction_id),
          unit_race_id: creature2.unit_race_id(creature),
        ),
      )
    })
  let indexes = checklist_index.assign(tables:, candidates:)
  let targets =
    checklist_index.checklists(tables:, candidates:)
    |> list.flat_map(fn(checklist) { checklist.targets })
    |> set.from_list
  let placed_targets =
    list.filter(placed_rows, fn(row: Row) { set.contains(targets, row.id) })
  // Objective 7207 (quest 5070) counts 500 of 16 targets, 15 of them stored: the stored
  // ones hold 0 to 14 and the placed Creature2 21517 at marker 15289 takes 15. Objective
  // 16235 (quest 6587) counts 3 of one target, the placed Creature2 30307 at marker 24531,
  // which takes 0. The same as when placed ids followed the stored ones in stand order.
  assert list.map(placed_targets, fn(row: Row) { row.creature_id })
    |> list.sort(int.compare)
    == [21_517, 30_307]
    as "only those two placed rows are the target of a checklist"
  let index_of = fn(creature_id) {
    let assert Ok(row) =
      list.find(placed_targets, fn(row: Row) { row.creature_id == creature_id })
      as "the placed target is there"
    dict.get(indexes, row.id)
  }
  assert index_of(21_517) == Ok(15)
    as "opcode.0x262: the placed target takes the index after the fifteen stored ones"
  assert index_of(30_307) == Ok(0)
    as "opcode.0x262: the lone placed target takes the lowest index"
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
/// - each pair not stored has the objective's count of its own creatures standing
///   in its markers' circles (`one_objective`), whatever other objectives share the
///   markers;
/// - no row is placed in a world with no stored spawn, and the selection refuses
///   none of the rows. The count of rows the placement makes is the coverage run's,
///   not a literal here.
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
  let stored = content_support.stored_spawns(database:)
  let tables = client_tables.with_content_tables()
  let factions = spawn_support.the_boss_is_given_233(tables:)
  let placed = placed_by_the_load(tables:, stored:, factions:)
  let worlds = set.from_list(list.map(stored, fn(row: Row) { row.world_id }))
  let held =
    objective_spawn.held_by(stored:, kinds: spawn_support.turret_kinds())
  let kill_objectives =
    list.filter(quest_objective.all(tables), fn(objective) {
      list.contains([2, 8, 16], objective.type_)
      && quest_row.marker_ids(objective:) != []
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
      vendor_creatures: set.new(),
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
    quest_row.marker_ids(objective:)
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
      vendor_creatures: set.new(),
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

/// The name of a skip's reason, matched without a catch-all so a new reason is
/// seen here.
fn reason_of(why: objective_spawn.Why) -> String {
  case why {
    objective_spawn.NoCreatureRow(..) -> "NoCreatureRow"
    objective_spawn.NamesNoCreature(..) -> "NamesNoCreature"
    objective_spawn.NoMarkerRow(..) -> "NoMarkerRow"
    objective_spawn.NoSpawnsInWorld(..) -> "NoSpawnsInWorld"
    objective_spawn.TurretHasNoKind(..) -> "TurretHasNoKind"
    objective_spawn.NotStarted(..) -> "NotStarted"
  }
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
  assert stands_at(row: first, x: 72.9871, y: -872.0891, z: 357.634)
    as "73463 at marker 52899"
  assert stands_at(row: second, x: 53.515, y: -872.0891, z: 374.479)
    as "73667 at marker 52900"
  assert stands_at(row: third, x: 43.1171, y: -872.0891, z: 395.189)
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
  assert stands_at(row:, x: 72.9871, y: -872.0891, z: 357.634)
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
  assert stands_at(row:, x: -70.4453, y: -868.839, z: 383.553)
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
  assert stands_at(row:, x: 72.9871, y: -872.0891, z: 357.634)
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
  assert stands_at(row:, x: -70.4453, y: -868.839, z: 383.553)
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
  assert stands_at(row: first, x: -70.4453, y: -868.839, z: 383.553)
    as "51662 first"
  assert stands_at(row: second, x: 72.9871, y: -872.0891, z: 357.634)
    as "then 52899"
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

pub fn a_click_marker_stands_as_the_unit_type_of_its_creation_type_test() -> Nil {
  use <- owned_test.run(60_000)
  // `0x140479560`: the unit type equals the creation type for 0 to 14; 18 pairs with 19
  // and 20 with 32 (world database, a guess). A value the client refuses (26 and over,
  // `0x140485790`) is paired as its own number and so reaches the same start test.
  let placed_with = fn(creation_type) {
    use changed <- fixture_tables.changed(table: "Creature2", id: mine, with: [
      #("CreationTypeEnum", Integer(creation_type)),
    ])
    click_placed_in_world(tables: changed)
  }
  let not_started = fn(placed: Placed, unit_type) {
    list.contains(
      placed.click_skipped,
      objective_spawn.Skipped(
        objective_id: 21_287,
        why: objective_spawn.NotStarted(creature_id: mine, unit_type:),
      ),
    )
  }
  let bind_point = placed_with(18)
  assert click_of(placed: bind_point, creatures: [mine]) == []
    && not_started(bind_point, 19)
    as "18 stands as unit type 19, which the server does not start"
  let collidable = placed_with(20)
  let rows = click_of(placed: collidable, creatures: [mine])
  assert rows != [] && list.all(rows, fn(row) { row.entity_type == 32 })
    as "20 stands as unit type 32"
  let plain = placed_with(0)
  let rows = click_of(placed: plain, creatures: [mine])
  assert rows != [] && list.all(rows, fn(row) { row.entity_type == 0 })
    as "0 stands as unit type 0"
  let refused = placed_with(26)
  assert click_of(placed: refused, creatures: [mine]) == []
    && not_started(refused, 26)
    as "a refused creation type reaches the pairing and stands as its own number, which is not started"
}

pub fn the_start_test_the_placement_uses_is_the_one_select_applies_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.content_tables()
  let row = stored(tables:, id: 1, creature_id: filler, world_id: world)
  // Every entity type up to 40 (the client's unit types stop at 32), with the
  // kinds that give a Turret row a creature_kind row and the kinds that do not.
  int.range(from: 0, to: 41, with: Nil, run: fn(_, entity_type) {
    list.each([spawn_support.kinds(), spawn_support.turret_kinds()], fn(kinds) {
      let selection =
        spawn.select(
          rows: [spawn.Row(..row, entity_type:)],
          tables:,
          formulas: rating_support.formulas(),
          kinds:,
          vendor_creatures: set.new(),
          factions: creature_faction.none(),
        )
      let is_other =
        list.any(selection.coverage, fn(coverage) {
          list.any(coverage.other_types, fn(counted) {
            counted.0 == entity_type
          })
        })
      assert is_other == !spawn.starts_entity_type(entity_type:)
        as {
          "entity type "
          <> int.to_string(entity_type)
          <> ": the selection counts it as Other exactly when the start test says it does not start"
        }
    })
  })
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
  assert unread_of_the_mine(placed:) == []
    as "a link to an objective of another type is a correct drop, not an unread link"
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
  assert stands_at(row:, x: 72.9871, y: -872.0891, z: 357.634)
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

/// The unread links of the mine, whichever the tables give it.
fn unread_of_the_mine(
  placed placed: Placed,
) -> List(objective_spawn.UnreadLink) {
  list.filter(placed.unread_links, fn(link) { link.creature_id == mine })
}

pub fn a_link_to_a_quest_the_client_has_no_row_of_is_reported_test() -> Nil {
  use <- owned_test.run(60_000)
  let no_row = 9_999_999
  // The mine's questAnim pair now names a quest the client's Quest2 lacks.
  use changed <- fixture_tables.changed(table: "Creature2", id: mine, with: [
    #("questAnimStateId", Integer(no_row)),
    #("questAnimObjectiveIndex", Integer(0)),
  ])
  let placed = click_placed_in_world(tables: changed)
  assert list.contains(
    unread_of_the_mine(placed:),
    objective_spawn.UnreadLink(
      creature_id: mine,
      quest_id: no_row,
      index: 0,
      why: objective_spawn.NoQuestRow,
    ),
  )
    as "the link to a quest with no row is reported with the creature, quest and index"
  assert list.any(objective_spawn.report(placed:), fn(line) {
    string.contains(line, "Creature2 73463")
    && string.contains(line, "Quest2 9999999")
    && string.contains(line, "no row")
  })
    as "the report names the creature and the quest"
}

pub fn a_link_to_an_index_the_quest_has_no_objective_at_is_reported_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 10518 holds six objectives: index 6 is past its last, -2 is below 0
  // (-1 names the quest alone and is no link).
  list.each([6, -2], fn(index) {
    use changed <- fixture_tables.changed(table: "Creature2", id: mine, with: [
      #("questAnimStateId", Integer(10_518)),
      #("questAnimObjectiveIndex", Integer(index)),
    ])
    let placed = click_placed_in_world(tables: changed)
    assert list.contains(
      unread_of_the_mine(placed:),
      objective_spawn.UnreadLink(
        creature_id: mine,
        quest_id: 10_518,
        index:,
        why: objective_spawn.NoObjectiveAtIndex,
      ),
    )
      as "the link to an index the quest has no objective at is reported"
    assert list.any(objective_spawn.report(placed:), fn(line) {
      string.contains(line, "Creature2 73463")
      && string.contains(line, "Quest2 10518")
      && string.contains(line, "index " <> int.to_string(index))
    })
      as "the report names the creature, the quest and the index"
  })
}

pub fn a_link_to_a_quest_whose_objective_row_is_missing_is_reported_test() -> Nil {
  use <- owned_test.run(60_000)
  let no_row = 9_999_998
  // Quest 10518's last slot now names a QuestObjective row the client lacks, so the
  // quest cannot be read and the mine's link to it (index 1, by its prerequisite)
  // is unread. The server's load refuses such tables (building `Activations` names the
  // row), so the tables are edited with no requirement, and with the activations the
  // unchanged rows build, which the link reading takes: the placement reads the quest's
  // rows as they stand.
  let assert Ok(loaded) = fixture_tables.load(rows: fixture_tables.rows())
    as "the unchanged rows load"
  let activations = activate.activations(tables: loaded)
  let assert Ok(rows) =
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "Quest2",
      id: 10_518,
      with: [#("objective05", Integer(no_row))],
    )
    as "the quest's row is changed"
  let assert Ok(changed) =
    fixture_tables.edited(
      rows:,
      entries: server_table.entries(),
      requirements: [],
      derivations: [
        store.derivation(key: store.DerivedKey("Activations"), build: fn(_) {
          Ok(activations)
        }),
      ],
    )
    as "the rows are read with no requirement"
  let placed = click_placed_in_world(tables: changed)
  assert list.contains(
    unread_of_the_mine(placed:),
    objective_spawn.UnreadLink(
      creature_id: mine,
      quest_id: 10_518,
      index: 1,
      why: objective_spawn.NoObjectiveRow(objective_id: no_row),
    ),
  )
    as "the link is reported with the objective row the quest lacks"
  assert list.any(objective_spawn.report(placed:), fn(line) {
    string.contains(line, "Creature2 73463")
    && string.contains(line, "QuestObjective 9999998")
  })
    as "the report names the creature and the missing row"
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

pub fn click_placement_ids_are_above_every_kill_placement_id_test() -> Nil {
  use <- owned_test.run(10_000)
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
  let highest_kill = list.fold(numbers_of(placed.rows), 0, int.max)
  let clicks = numbers_of(placed.click_rows)
  assert list.all(clicks, fn(number) {
    number > highest_kill && number >= first_placed_id
  })
    as "above every kill-placed id, and at or above the first placed id"
  assert list.all(clicks, fn(number) {
    !spawn_source.is_run_only_id(SpawnId(number))
  })
  assert list.length(list.unique(clicks)) == list.length(clicks)
    as "each id is once"
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
      vendor_creatures: set.new(),
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
        unread_links: [],
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
        unread_links: [],
      ),
    )
  let from_click =
    list.drop_while(lines, fn(line) {
      !string.starts_with(line, "click objectives:")
    })
  let assert [click_line, skip_line] = from_click
    as "the click line, then the skip"
  assert click_line
    == "click objectives: placed 3 creatures with no stored spawn at their marker, skipped 1 pairs and 0 links that name no objective"
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
/// - 3 unplaced pairs of a unit type the server does not start;
/// - 5 distinct (objective, marker) pairs whose marker the client has no
///   WorldLocation2 row of;
/// - 162 distinct (objective, marker) pairs whose marker lies in a world holding no
///   stored row (the script counts 236 of them per linked creature, and the server
///   reports each pair once);
/// - of the 3296 links the script follows from every Creature2 (questAnim pair or
///   prerequisite), 392 name no objective, the very (creature, quest, index) triples
///   the server reports: 80 to a quest the client has no Quest2 row of, 312 to an
///   index whose objective slot of the quest is empty, and none to a slot whose
///   QuestObjective row is missing;
/// - of the units (unit type 0) placed, 40 in world 22, 27 in world 51, 3 in world
///   426 and 39 in world 1061, of which Creature2 13133 (factionId 0, Neutral to
///   both player factions) in world 22 starts like the others, so all 109 start. Both
///   stored-row sources, the world database's and the play database's, give the same
///   counts.
pub fn every_click_objective_with_a_marker_starts_or_has_a_spawn_test() -> Nil {
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
  let stored = content_support.stored_spawns(database:)
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
  let skipped_as = fn(reason) {
    list.count(placed.click_skipped, fn(skipped) {
      reason_of(skipped.why) == reason
    })
  }
  assert skipped_as("NotStarted") == 3
    as "the pairs whose unit type the server does not start"
  assert skipped_as("NoMarkerRow") == 5
    as "the markers the client has no row of"
  assert skipped_as("NoSpawnsInWorld") == 162
    as "the (objective, marker) pairs in a world with no stored spawn"
  let unread_as = fn(why) {
    list.count(placed.unread_links, fn(link) { link.why == why })
  }
  assert unread_as(objective_spawn.NoQuestRow) == 80
    as "the links to a quest the client has no row of"
  assert unread_as(objective_spawn.NoObjectiveAtIndex) == 312
    as "the links to an index past the quest's last objective"
  assert list.length(placed.unread_links) == 392
    as "no link names an objective whose QuestObjective row is missing"
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
      vendor_creatures: set.new(),
      factions:,
    )
  assert selection.refusals == []
    as "a placed row that the checks refuse would stop the server's start"
  // Creature2 13133 (Protostar X-97 Gravity Defiance System, factionId 0 in the
  // client's table, no chosen faction) is Neutral to both player factions
  // (`0x14045a950.faction_zero`), so it starts with the rest.
  assert list.all(selection.coverage, fn(coverage) {
    list.all(coverage.left_out, fn(pair) { pair.1 == 0 })
  })
    as "no placed creature is left out, whatever the reason"
  let started_in = fn(world_id) {
    let assert Ok(coverage) =
      list.find(selection.coverage, fn(coverage) {
        coverage.world_id == world_id
      })
      as "the world has a coverage"
    coverage.started
  }
  assert list.map([22, 51, 426, 1061], started_in) == [40, 27, 3, 39]
    as "the creatures that start from the rows placed, by world"
  let assert Ok(world_22) = dict.get(selection.worlds, 22)
    as "world 22 has spawns"
  assert list.any(dict.values(world_22.by_id), fn(standing) {
    standing.creature_id == Creature2Id(13_133)
  })
    as "Creature2 13133 starts in world 22"
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
  assert sent == 344 as "every placed row starts or is sent"
}

/// What the kill table's rows make the placement do: the rows stored, the objectives in the
/// table, and how many rows of the creature are placed.
type KillTarget {
  KillTarget(
    why: String,
    stored: List(#(Int, Int)),
    kills: List(Int),
    creature: Int,
    placed: Int,
  )
}

pub fn the_kill_targets_stand_in_the_marker_circle_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.content_tables()
  // Quest 5895's objective 8866 and quest 5896's 8867 are type 5, count 1, on TargetGroup
  // 5256 (Creature2 26037) at marker 19529 in World 51 (`table_rows -- QuestObjective 8866
  // 8867`, `-- TargetGroup 5256`, `-- WorldLocation2 19529`).
  let scientist = 26_037
  let base =
    KillTarget(
      why: "a kill-table row whose creature has no stored spawn gets one at its marker",
      stored: [#(filler, 51)],
      kills: [8866],
      creature: scientist,
      placed: 1,
    )
  let cases = [
    base,
    KillTarget(
      ..base,
      why: "a creature with a stored spawn in the marker's world is left to it",
      stored: [#(filler, 51), #(scientist, 51)],
      placed: 0,
    ),
    KillTarget(
      ..base,
      why: "a type 5 row not in the kill table places nothing",
      kills: [],
      placed: 0,
    ),
    KillTarget(
      ..base,
      why: "two objectives of the same pane and marker place the creature once",
      kills: [8866, 8867],
      placed: 1,
    ),
    KillTarget(
      ..base,
      why: "a marker in a world with no stored spawn places nothing",
      stored: [#(filler, 22)],
      placed: 0,
    ),
  ]
  list.each(cases, fn(row) {
    let placed =
      placed_with_kills(
        tables:,
        stored: list.index_map(row.stored, fn(pair, index) {
          stored(tables:, id: index + 1, creature_id: pair.0, world_id: pair.1)
        }),
        factions: creature_faction.none(),
        kills: set.from_list(row.kills),
      )
    assert list.length(of_creatures(placed:, creatures: [row.creature]))
      == row.placed
      as row.why
  })
  let placed =
    placed_with_kills(
      tables:,
      stored: [stored(tables:, id: 1, creature_id: filler, world_id: 22)],
      factions: creature_faction.none(),
      kills: set.from_list([8866]),
    )
  assert list.contains(
    placed.skipped,
    objective_spawn.Skipped(
      objective_id: 8866,
      why: objective_spawn.NoSpawnsInWorld(marker_id: 19_529, world_id: 51),
    ),
  )
    as "the report names the objective, the marker and the world that holds no spawn"
  // Objective 8281 is type 5, count 25, on TargetGroup 2539 (Creature2 24039, 24040, 24041,
  // 24042 and 54033, in that order) at marker 18235: radius 100 at (4252.03125, -943.09375,
  // 313.00586) in World 51, zone 1252.
  let placed =
    placed_with_kills(
      tables:,
      stored: [stored(tables:, id: 1, creature_id: filler, world_id: 51)],
      factions: creature_faction.none(),
      kills: set.from_list([8281]),
    )
  let creatures = [24_039, 24_040, 24_041, 24_042, 54_033]
  let rows = of_creatures(placed:, creatures:)
  assert list.length(rows) == 25 as "as many as the objective counts"
  assert list.map(rows, fn(row) { row.creature_id })
    == list.flatten(list.repeat(creatures, 5))
    as "the pane's creatures take the places in its order, cycling"
  list.each(rows, fn(row) {
    let dx = row.x -. 4252.03125
    let dz = row.z -. 313.005859375
    let assert Ok(across) = float.square_root(dx *. dx +. dz *. dz)
      as "a sum of squares has a root"
    assert close(across, 50.0)
      as "each stands on the circle of half the marker's radius"
    assert row.world_id == 51 && row.area_id == 1252
      as "the marker's world and zone"
  })
}

/// What the click table's rows make the placement do: the rows stored (creature, world), the
/// objectives in the click table, and how many click rows of the creature are placed.
type ClickTarget {
  ClickTarget(
    why: String,
    stored: List(#(Int, Int)),
    clicks: List(Int),
    creature: Int,
    placed: Int,
  )
}

pub fn the_click_targets_stand_at_the_marker_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.content_tables()
  // Quest 6591's objective 16170 is type 5, count 1, on TargetGroup 6299 (Creature2 51440) at
  // marker 40836 in World 22; quest 5918's 9002 is on TargetGroup 7874 (Creature2 26436) at
  // marker 19699 in World 22 (`table_rows -- QuestObjective 16170 9002`, `-- TargetGroup 6299
  // 7874`, `-- WorldLocation2 40836 19699`). Objective 10256 of quest 6591 is a type 2 kill of
  // Creature2 51440 on the same pane and marker. Creature2 26436's own link names quest 5918's
  // objective 8903, a type 12 objective, which names no click target. Objective 6159's pane
  // lists Creature2 16595, which has no activate spell, at marker 12358 in World 51.
  let pyrius = 51_440
  let base =
    ClickTarget(
      why: "a click-table row whose creature has no stored spawn gets one at its marker",
      stored: [#(filler, 22)],
      clicks: [16_170],
      creature: pyrius,
      placed: 1,
    )
  let cases = [
    base,
    ClickTarget(
      ..base,
      why: "a stored row of the creature in the marker's world serves it",
      stored: [#(filler, 22), #(pyrius, 22)],
      placed: 0,
    ),
    ClickTarget(
      ..base,
      why: "a stored row of the creature in another world serves no marker",
      stored: [#(filler, 22), #(pyrius, 51)],
      placed: 1,
    ),
    ClickTarget(
      ..base,
      why: "a type 5 row not in the click table places nothing",
      clicks: [],
      placed: 0,
    ),
    ClickTarget(
      ..base,
      why: "a type 2 and a type 5 row of one pane and marker place the creature once",
      clicks: [16_170, 10_256],
      placed: 1,
    ),
    ClickTarget(
      ..base,
      why: "a marker in a world with no stored spawn places nothing",
      stored: [#(filler, 51)],
      placed: 0,
    ),
    ClickTarget(
      ..base,
      why: "quest 5918's creature is placed once at the marker of 9002, and its link to the type 12 objective 8903 places none",
      clicks: [9002],
      creature: 26_436,
    ),
    ClickTarget(
      why: "a pane creature the client offers no click on is not placed",
      stored: [#(filler, 51)],
      clicks: [6159],
      creature: 16_595,
      placed: 0,
    ),
  ]
  list.each(cases, fn(row) {
    let placed =
      placed_with_tables(
        tables:,
        stored: list.index_map(row.stored, fn(pair, index) {
          stored(tables:, id: index + 1, creature_id: pair.0, world_id: pair.1)
        }),
        factions: creature_faction.none(),
        kills: set.new(),
        clicks: set.from_list(row.clicks),
      )
    assert list.length(click_of(placed:, creatures: [row.creature]))
      == row.placed
      as row.why
  })
  let placed =
    placed_with_tables(
      tables:,
      stored: [stored(tables:, id: 1, creature_id: filler, world_id: 22)],
      factions: creature_faction.none(),
      kills: set.new(),
      clicks: set.from_list([16_170]),
    )
  let assert [row] = click_of(placed:, creatures: [pyrius])
    as "one row of the creature"
  assert list.length(of_creatures(placed:, creatures: [pyrius])) == 1
    as "objective 10256's kill row of the same creature and marker stands too"
  let pyrius_marker = the_marker_of(tables:, marker_id: 40_836)
  list.each(
    list.append(of_creatures(placed:, creatures: [pyrius]), [row]),
    fn(on_the_ring) {
      let dx = on_the_ring.x -. pyrius_marker.position0
      let dz = on_the_ring.z -. pyrius_marker.position2
      let assert Ok(across) = float.square_root(dx *. dx +. dz *. dz)
        as "a sum of squares has a root"
      assert close(across, pyrius_marker.radius /. 2.0)
        && close(on_the_ring.y, pyrius_marker.position1)
        as "the kill row and the click row of one marker stand on its half-radius ring, at its height"
    },
  )
  assert shared_places(rows: list.append(placed.rows, placed.click_rows)) == []
    as "the kill row and the click row of one marker stand on two places"
  assert row.world_id == 22 && row.area_id == pyrius_marker.world_zone_id
    as "the marker's world and zone"
  // Quest 5918's creature 26436 has no kill objective at its marker 19699, so its
  // click row is the marker's only one and stands at the marker's centre.
  let placed =
    placed_with_tables(
      tables:,
      stored: [stored(tables:, id: 1, creature_id: filler, world_id: 22)],
      factions: creature_faction.none(),
      kills: set.new(),
      clicks: set.from_list([9002]),
    )
  let assert [alone] = click_of(placed:, creatures: [26_436])
    as "one row of the creature"
  let marker = the_marker_of(tables:, marker_id: 19_699)
  assert stands_at(
    row: alone,
    x: marker.position0,
    y: marker.position1,
    z: marker.position2,
  )
    as "the creature stands at the marker's centre"
  assert alone.world_id == 22 && alone.area_id == marker.world_zone_id
    as "the marker's world and zone"
  let skipped =
    placed_with_tables(
      tables:,
      stored: [stored(tables:, id: 1, creature_id: filler, world_id: 51)],
      factions: creature_faction.none(),
      kills: set.new(),
      clicks: set.from_list([16_170]),
    )
  assert list.contains(
    skipped.click_skipped,
    objective_spawn.Skipped(
      objective_id: 16_170,
      why: objective_spawn.NoSpawnsInWorld(marker_id: 40_836, world_id: 22),
    ),
  )
    as "the report names the objective, the marker and the world that holds no spawn"
}
