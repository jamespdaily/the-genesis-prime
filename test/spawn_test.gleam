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
//// - The client's Creature2 validity rules (`0x140485790`): the tables' load fails
////   when a spawn names a creature the client would not load.
//// The test of the points reads the client's real tables, so it is skipped where
//// there are none (`GENESIS_NO_CLIENT=1`); the test of the validity rules loads
//// planted tables, so it runs in CI.

import character_tables
import client_tables
import genesis_prime/game/start_place
import genesis_prime/table/id.{Creature2Id, WorldLocation2Id}
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store as table_store
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
