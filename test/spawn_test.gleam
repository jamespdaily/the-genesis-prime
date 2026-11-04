//// The spawns of the training creatures (`genesis_prime/world_map/spawn`), built
//// from the client's tables when they load. Expected values come from these
//// places.
//// - The client's own circles (fact `Quest2.10518`, `Quest2.10524`): the Exile
////   objective circle is WorldLocation2 51739 and the Dominion one 52898, each of
////   radius 55; the circle's centre and radius are read from the client's row.
//// - Jim's world database (`spawn.tsv` rows 29113 to 29139): the 27 points of the
////   Virtual Battle Beast (Creature2 73464), each marked as that row. The Dominion
////   Virtual Defense Dagun (Creature2 73465) has no record anywhere, so each of its
////   27 points is marked as the offset of one of those rows.
//// - The client's Creature2 validity rules (`0x140485790`, `0x140483d20`): the
////   tables' load fails when a spawn names a creature the client would not load.
//// - The creature trace of the combat core (the Client trace artifact of issue
////   274, its creatures section; facts `Creature2.73464` and `Creature2.73465`,
////   `0x1404585c0`): the Virtual Battle Beast is level 1, faction 1441, display
////   26565, Base Health 135.97028 x 1.0 x 0.387 x 1.0 = 52.6205, so 52; the Virtual
////   Defense Dagun is level 1, faction 1442, display 26578 and, with the
////   archetype's 0.96, Base Health 50.5157, so 50.
//// - The rule of the spawn's choices (its doc comment): an override of property 7
////   is Base Health; the display is the entry of greatest weight with a
////   Creature2DisplayInfo row, the lowest display id on a tie; an id of 0 for the
////   difficulty or the resist needs no row, and multiplies by 1.0.
//// The test of the points reads the client's real tables, so it is skipped where
//// there are none (`GENESIS_NO_CLIENT=1`); the test of the validity rules loads
//// planted tables, so it runs in CI.

import character_tables
import client_tables
import genesis_prime/game/start_place
import genesis_prime/table/creature2_display_group_entry
import genesis_prime/table/creature2_display_info
import genesis_prime/table/creature2_outfit_group_entry
import genesis_prime/table/creature2_override_properties
import genesis_prime/table/id.{Creature2Id, WorldLocation2Id}
import genesis_prime/table/instance_portal
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/loader/tbl_file
import genesis_prime/table/path_mission
import genesis_prime/table/world_location2
import genesis_prime/world_map/spawn.{type Spawn, NoRecord, WorldDatabase}
import gleam/erlang/reference
import gleam/float
import gleam/list
import gleam/string
import owned_test
import planted_table
import unitest

/// The world-database rows of the 27 Virtual Battle Beasts.
fn beast_rows() -> List(Int) {
  list.index_map(list.repeat(Nil, 27), fn(_, offset) { 29_113 + offset })
}

/// The spawns of the creature in the tables' load, in the order of the points.
fn of_creature(spawns: List(Spawn), creature: Int) -> List(Spawn) {
  list.filter(spawns, fn(spawn) { spawn.creature_id == Creature2Id(creature) })
}

/// Whether the spawn stands inside the client's circle it names: within the
/// circle's radius of its centre.
fn inside_its_circle(tables: table_store.Tables, spawn: Spawn) -> Bool {
  let assert Ok(circle) = world_location2.get(tables, spawn.area)
    as "the spawn's circle is a WorldLocation2 row"
  let dx = start_place.x(spawn.place) -. circle.position0
  let dy = start_place.y(spawn.place) -. circle.position1
  let dz = start_place.z(spawn.place) -. circle.position2
  let assert Ok(distance) = float.square_root(dx *. dx +. dy *. dy +. dz *. dz)
    as "a sum of squares has a root"
  distance <=. circle.radius
}

pub fn the_battle_beasts_stand_at_the_world_databases_points_and_the_daguns_at_their_offsets_each_inside_its_client_circle_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let spawns = spawn.all(tables)
  let beasts = of_creature(spawns, 73_464)
  let daguns = of_creature(spawns, 73_465)
  assert list.length(spawns) == 54
    as "the 27 Virtual Battle Beasts and the 27 Virtual Defense Daguns, and no other creature"
  assert list.map(beasts, fn(beast) { beast.source })
    == list.map(beast_rows(), fn(row) { WorldDatabase(row_id: row) })
    as "each Battle Beast is marked as the world-database row it stands at"
  assert list.map(daguns, fn(dagun) { dagun.source })
    == list.map(beast_rows(), fn(row) { NoRecord(offset_of_row_id: row) })
    as "each Dagun is marked as having no record, with the row whose offset it takes"
  assert list.all(beasts, fn(beast) { beast.area == WorldLocation2Id(51_739) })
    as "the Battle Beasts stand in the Exile objective circle"
  assert list.all(daguns, fn(dagun) { dagun.area == WorldLocation2Id(52_898) })
    as "the Daguns stand in the Dominion objective circle"
  assert list.all(spawns, inside_its_circle(tables, _))
    as "every point lies inside the client's circle it names"
  assert list.length(list.unique(list.map(spawns, fn(spawn) { spawn.id })))
    == 54
    as "each spawn has an id of its own"
  assert list.all(spawns, fn(spawn) {
    start_place.world_id(spawn.place) == 3460
    && start_place.world_zone_id(spawn.place) == 5967
  })
    as "every spawn stands in World 3460, Warfare Woods"
}

/// The load of planted tables whose Virtual Battle Beast row has `changes`, and
/// why it failed: the derivation's name and its reason.
fn failed_load(
  changes changes: List(#(String, planted_table.Cell)),
) -> #(String, String) {
  use folder <- planted_table.in_folder(
    character_tables.files_with_beast_changed(changes:),
  )
  let assert Error(table_store.DerivationFailed(name:, reason:)) =
    server_table.load_under(under: reference.new(), from: folder)
    as "a creature row the client would not load fails the tables' load"
  #(name, reason)
}

pub fn a_creature_row_the_client_would_not_load_fails_the_tables_load_naming_the_rule_test() -> Nil {
  use <- owned_test.run(60_000)
  // 0x140485790: a row is a creature the client loads only when its modelScale
  // is above 0, its CreationTypeEnum is below 26, its archetype row exists, its
  // difficulty and resist are 0 or have a row, and its display group is not 0.
  list.each(
    [
      #(
        [#("modelScale", planted_table.Float(0.0))],
        "modelScale is not above 0",
      ),
      #(
        [#("CreationTypeEnum", planted_table.Integer(26))],
        "CreationTypeEnum is not below 26",
      ),
      #(
        [#("creature2ArcheTypeId", planted_table.Integer(99))],
        "Creature2ArcheType row does not exist",
      ),
      #(
        [#("creature2DifficultyId", planted_table.Integer(99))],
        "Creature2Difficulty row does not exist",
      ),
      #(
        [#("creature2ResistId", planted_table.Integer(99))],
        "Creature2Resist row does not exist",
      ),
      #(
        [#("creature2DisplayGroupId", planted_table.Integer(0))],
        "display group is 0",
      ),
      #(
        [#("pathMissionIdSoldier", planted_table.Integer(99))],
        "pathMissionIdSoldier row does not exist",
      ),
      #(
        [#("instancePortalId", planted_table.Integer(99))],
        "instancePortalId row does not exist",
      ),
      #(
        [#("creature2OutfitGroupId", planted_table.Integer(99))],
        "outfit group has no entries",
      ),
    ],
    fn(case_) {
      let #(changes, words) = case_
      let #(name, reason) = failed_load(changes:)
      assert name == "Spawns" as "the spawns' derivation is what failed"
      assert string.contains(reason, "Creature2 73464")
        && string.contains(reason, words)
        as { "the reason names the creature and the rule: " <> reason }
    },
  )
}

/// The spawns of a load of these planted files, under a key of its own.
fn spawns_of(files: List(#(String, BitArray))) -> List(Spawn) {
  use folder <- planted_table.in_folder(files)
  let assert Ok(tables) =
    server_table.load_under(under: reference.new(), from: folder)
    as "the planted files load as the server's tables"
  spawn.all(tables)
}

/// The files with the file of `schema` holding `rows` in place of its own.
fn replacing(
  files files: List(#(String, BitArray)),
  schema schema: tbl_file.Schema,
  rows rows: List(List(planted_table.Cell)),
) -> List(#(String, BitArray)) {
  list.map(files, fn(file) {
    case file.0 == schema.file {
      True -> planted_table.file(schema, rows)
      False -> file
    }
  })
}

/// The health, faction and display of the spawns of one creature, each once.
fn values_of(
  spawns: List(Spawn),
  creature: Int,
) -> List(#(Int, Int, Int, Int)) {
  list.filter(spawns, fn(spawn) { spawn.creature_id == Creature2Id(creature) })
  |> list.map(fn(spawn) {
    #(spawn.level, spawn.health, spawn.faction_id, spawn.display_info_id)
  })
  |> list.unique
}

pub fn the_derived_spawns_carry_the_creature_traces_numbers_test() -> Nil {
  use <- owned_test.run(60_000)
  let spawns = spawns_of(character_tables.files())
  assert values_of(spawns, 73_464) == [#(1, 52, 1441, 26_565)]
    as "Creature2.73464: level 1, Base Health 52.6205 truncated, faction 1441, display 26565"
  assert values_of(spawns, 73_465) == [#(1, 50, 1442, 26_578)]
    as "Creature2.73465: level 1, Base Health 50.5157 truncated, faction 1442, display 26578"
}

pub fn a_creatures_override_of_property_7_is_its_base_health_test() -> Nil {
  use <- owned_test.run(60_000)
  let files =
    replacing(
      files: character_tables.files(),
      schema: creature2_override_properties.schema,
      rows: [
        character_tables.override_row(
          id: 1,
          creature: 73_464,
          property: 7,
          value: 77.9,
        ),
        character_tables.override_row(
          id: 2,
          creature: 73_464,
          property: 40,
          value: 1.0,
        ),
      ],
    )
  let spawns = spawns_of(files)
  assert values_of(spawns, 73_464) == [#(1, 77, 1441, 26_565)]
    as "the override's 77.9 truncated, in place of the formula's 52"
  assert values_of(spawns, 73_465) == [#(1, 50, 1442, 26_578)]
    as "another creature keeps the formula"
}

pub fn the_display_is_the_entry_of_greatest_weight_with_a_display_row_and_the_lowest_id_on_a_tie_test() -> Nil {
  use <- owned_test.run(60_000)
  let info = fn(id) {
    planted_table.row(creature2_display_info.schema, [
      #("ID", planted_table.Integer(id)),
    ])
  }
  let weighted = fn(id, group, display, weight) {
    planted_table.row(creature2_display_group_entry.schema, [
      #("id", planted_table.Integer(id)),
      #("creature2DisplayGroupId", planted_table.Integer(group)),
      #("creature2DisplayInfoId", planted_table.Integer(display)),
      #("weight", planted_table.Integer(weight)),
    ])
  }
  let files =
    character_tables.files()
    |> replacing(schema: creature2_display_info.schema, rows: [
      info(26_560),
      info(26_565),
      info(26_570),
      info(26_578),
    ])
    |> replacing(schema: creature2_display_group_entry.schema, rows: [
      weighted(1, 28_793, 26_565, 1),
      weighted(2, 28_793, 26_570, 3),
      weighted(3, 28_793, 26_560, 3),
      weighted(4, 28_793, 26_500, 9),
      weighted(5, 28_431, 26_578, 1),
    ])
  assert list.map(values_of(spawns_of(files), 73_464), fn(values) { values.3 })
    == [26_560]
    as "weight 3 beats weight 1 and, between 26570 and 26560 at weight 3, the lower id wins; the entry of weight 9 has no Creature2DisplayInfo row and counts for nothing"
}

pub fn a_difficulty_and_a_resist_of_0_need_no_row_and_the_difficulty_multiplies_by_1_test() -> Nil {
  use <- owned_test.run(60_000)
  let files =
    character_tables.files_with_beast_changed(changes: [
      #("creature2DifficultyId", planted_table.Integer(0)),
      #("creature2ResistId", planted_table.Integer(0)),
    ])
  assert values_of(spawns_of(files), 73_464) == [#(1, 135, 1441, 26_565)]
    as "CreatureLevel 1's 135.97028 x 1.0 x 1.0 x 1.0, truncated"
}

pub fn a_soldier_mission_an_instance_portal_and_an_outfit_group_with_rows_load_test() -> Nil {
  use <- owned_test.run(60_000)
  let id = fn(schema, number) {
    planted_table.row(schema, [#("ID", planted_table.Integer(number))])
  }
  let files =
    character_tables.files_with_beast_changed(changes: [
      #("pathMissionIdSoldier", planted_table.Integer(5)),
      #("instancePortalId", planted_table.Integer(6)),
      #("creature2OutfitGroupId", planted_table.Integer(7)),
    ])
    |> replacing(schema: path_mission.schema, rows: [id(path_mission.schema, 5)])
    |> replacing(schema: instance_portal.schema, rows: [
      id(instance_portal.schema, 6),
    ])
    |> replacing(schema: creature2_outfit_group_entry.schema, rows: [
      planted_table.row(creature2_outfit_group_entry.schema, [
        #("ID", planted_table.Integer(1)),
        #("creature2OutfitGroupId", planted_table.Integer(7)),
      ]),
    ])
  assert list.length(values_of(spawns_of(files), 73_464)) == 1
    as "the creature with a mission, a portal and an outfit group that have rows is one the client loads"
}
