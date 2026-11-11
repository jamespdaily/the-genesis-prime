//// The spawns that start in each world from Jim's whole world database, loaded
//// through the content load with the client's real tables. Expected values come
//// from these places.
//// - The decode of issue 375 (its facts `world_data.creature_disposition` and
////   `world_data.spawn_checks`), re-run by a scratch Python reimplementation of
////   the selection (a quest creature starts whatever else it links to, and
////   whether or not a player faction may attack it) that gave 40,043: world 22
////   starts 11,248 spawns, 51 13,173, 426 376, 870 693, 990 739, 1061 12,897,
////   1387 851 and 3460 66, and the other worlds none. The rows left out in all
////   are no faction 452, Friendly to both 7,400, a service link 33 and health 0
////   215.
//// - A creature with an objective link is not left out as Friendly to both
////   (`objective_link.has_link`: the client builds it whatever its faction), so
////   the Friendly rows with a link start. They are counted apart from
////   `spawn.select`, by a scratch Python script over `spawn.tsv` and the client's
////   Creature2 (questAnimStateId, prerequisiteIdAnimState, the quest and service
////   columns, factionId), Faction2 and Faction2Relationship rows with the
////   client's faction level walk: of the 7,400 stored rows Friendly to both with
////   no quest, 599, 581, 31, 9, 60 and 610 in worlds 22, 51, 426, 870, 990 and
////   1061 have a link, none of them a service link or health 0, so they start
////   (11,847, 13,754, 407, 702, 799 and 13,507 stored spawns in those worlds)
////   and 5,510 stay Friendly to both.
//// - The creatures of kill objectives that the load places at their markers
////   (`objective_spawn.place`, in the worlds that hold a stored spawn) start in
////   addition. The rows placed are a count over the client's QuestObjective,
////   TargetGroup, WorldLocation2 and Creature2 tables and `spawn.tsv`, made
////   apart from the server's code by a scratch Python script over the same rows:
////   432, 608, 38, 20, 12, 623, 20 and 11 in worlds 22, 51, 426, 870, 990, 1061,
////   1387 and 3460 (11 there before migration 0028's turret rows, 9 with them, below),
////   and none in a world with no stored spawn. The same script's
////   rules over those rows' creatures find, of the rows placed, 9, 10, 0, 0, 0,
////   20, 0 and 5 Friendly to both with no quest, and of them 0, 8, 0, 0, 0, 20, 0
////   and 0 with a link, which start. The selection starts 423, 605, 38, 20, 12,
////   623, 20 and 6 of the rows placed and leaves out the others as it does stored
////   rows (no faction, Friendly to both, a service link, health 0).
//// - Migration 0027: the boss, Creature2 73499 (one of the 5 rows placed in 3460 that
////   are Friendly to both with no quest or link, QuestObjective 21296 and 21310),
////   stands with faction 233, Hostile to both player factions
////   (Faction2Relationship 746), so it starts. The left-out counts above are over the
////   stored rows alone, which it is not one of.
//// - Migration 0008: World 3460 also holds the 27 Virtual Defense Daguns, server
////   choices, which start (Hostile to Dominion), so 3460 has 66 + 27.
//// - Migration 0028: the Sim-Turrets start as creatures with factions 1441 (73494,
////   Exile) and 1442 (74862, Dominion), Hostile to their own side only. The 2 stored
////   type 13 rows of 73494 in 3460 start as creatures (so 3460 holds no static type
////   13 and 239 of the 241 remain) and hold it, so 73494 has no placed row and the
////   placed rows are 1,762 in all and 9 in 3460, 2 of them 74862's, which has no
////   stored row. 3460 starts 66 stored + 27 Daguns (migration 0008) + 2 stored
////   73494 rows + 9 placed rows = 104.
//// The test needs the client's tables and the world database (`GENESIS_WORLD_DATA`),
//// so it is skipped where either is missing (a fork's CI run without the client's
//// data); it imports the whole file into a database of its own.

import client_tables
import content_support
import database_support
import envoy
import genesis_prime
import genesis_prime/content
import genesis_prime/content/spawn as content_spawn
import genesis_prime/game/prerequisite
import genesis_prime/game/rating
import genesis_prime/game/vendor
import genesis_prime/import_world_data
import genesis_prime/readiness
import genesis_prime/step/runtime
import genesis_prime/table/world
import genesis_prime/world_map/objective_spawn
import genesis_prime/world_map/spawn
import genesis_prime/world_map/static_object.{type StaticObject}
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_key
import owned_test
import spawn_support
import unitest

/// How the load asks: the database is up, so one attempt answers.
fn asking() -> readiness.Settings {
  readiness.Settings(within_ms: 5000, attempt_ms: 2000, pause_ms: 100)
}

pub fn the_whole_world_database_starts_the_decoded_number_of_spawns_in_each_world_test() -> Nil {
  // A hang guard, not a result check: the world-data part took 162 s and 202 s on
  // CI's runner in the two runs that passed and went past 300 s on a slow runner
  // (the same run's glinter took 2.1 times, gleam-test 1.5 times and client-suite
  // 1.8 times their passing runs). 600 s is three times the slowest passing run.
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
  let tables = client_tables.with_content_tables()
  let key = owned_key.new_fixture_key()
  let pool =
    database_support.config(
      database_support.settings(),
      database:,
      pool_name: process.new_name("world_data_counts_pool"),
      pool_size: 1,
    )
  let before = runtime.now().monotonic_ms
  let loaded =
    content.load(
      tables:,
      migrations: genesis_prime.load_migrations(),
      pool:,
      ask: asking(),
      probe: content.pool_probe,
      key:,
    )
  let took = runtime.now().monotonic_ms - before
  assert loaded == Ok(Nil) as "the whole world database loads"
  let assert Ok(rows) =
    content_spawn.rows(db: content_support.connect(database:))
    as "the spawn rows read back"
  // The kill objectives' creatures that have no stored spawn in their marker's
  // world stand at its marker (`objective_spawn.place`): the rows placed, by
  // world, are the counts named in the head of this file, and the load starts the
  // selection's share of them beside the decoded stored spawns.
  let placed =
    objective_spawn.place(
      tables:,
      stored: rows,
      factions: spawn_support.the_boss_is_given_233(tables:),
      kinds: spawn_support.turret_kinds(),
    ).rows
  assert list.length(placed) == 1762
    as "the rows placed in all, none of them in a world with no stored spawn"
  assert list.count(placed, fn(row) { row.creature_id == 74_862 }) == 2
    as "the Dominion Sim-Turret has no stored row, so its 2 are placed; the Exile Sim-Turret's 2 stored rows hold it"
  assert list.map(
      [22, 51, 426, 870, 990, 1061, 1387, 3460, 1535, 3022],
      fn(world_id) { list.count(placed, fn(row) { row.world_id == world_id }) },
    )
    == [432, 608, 38, 20, 12, 623, 20, 9, 0, 0]
    as "the rows placed in each world"
  assert list.map(
      [22, 51, 426, 870, 990, 1061, 1387, 3460, 1535, 3022],
      fn(world_id) { dict.size(content_spawn.world(key:, world_id:).by_id) },
    )
    == [
      11_847 + 423,
      13_754 + 605,
      407 + 38,
      702 + 20,
      799 + 12,
      13_507 + 623,
      851 + 20,
      66 + 27 + 2 + 9,
      0,
      0,
    ]
    as {
      "the spawns that start in each world; the load took "
      <> int.to_string(took)
      <> " ms"
    }
  // The rows left out in all worlds are the selection's own count over the same
  // rows and tables: the load keeps the selection's spawns and logs these.
  let selection =
    spawn.select(
      rows:,
      tables:,
      formulas: rating.formulas(tables:),
      kinds: spawn_support.kinds(),
      vendors: vendor.none(),
      factions: spawn_support.the_boss_is_given_233(tables:),
    )
  let left_out_in_all = fn(reason) {
    list.flat_map(selection.coverage, fn(world) { world.left_out })
    |> list.filter(fn(entry) { entry.0 == reason })
    |> list.fold(0, fn(total, entry) { total + entry.1 })
  }
  assert list.map(
      [spawn.NoFaction, spawn.FriendlyToBoth, spawn.ServiceLink, spawn.Dead],
      left_out_in_all,
    )
    == [452, 5510, 33, 215]
    as "the rows left out in all worlds: no faction, Friendly to both, a service link, health 0"
  // The world database's spawn rows (`spawn.tsv`, counted by entity type): 171
  // type 4, 4,380 type 8, 17,904 type 10, 491 type 11, 101 type 12, 241 type 13,
  // 79 type 14 and 1,178 type 32 spawns, every one passing the client's checks,
  // the 107 of types 10 and 11 whose creatures have minLevel 0 and no stats among
  // them; world 3460 holds 302 type 10, 2 type 13 and 15 type 32. Every type 13
  // and 32 spawn outside 3460 records a health above 0 and 3460's record none,
  // so none is left out as dead.
  let objects =
    list.flat_map(world.all(tables), fn(row) {
      dict.values(content_spawn.world(key:, world_id: row.id).objects)
    })
  let of_type = fn(objects: List(StaticObject), unit_type) {
    list.count(objects, fn(object) { object.unit_type == unit_type })
  }
  assert list.map(spawn.object_types, of_type(objects, _))
    == [171, 4380, 17_904, 491, 101, 239, 79, 1178]
    as "every static spawn of the world database loads, by type"
  let ship = dict.values(content_spawn.world(key:, world_id: 3460).objects)
  assert list.map(spawn.object_types, of_type(ship, _))
    == [0, 0, 302, 0, 0, 0, 0, 15]
    as "world 3460's static objects, by type"
  assert list.all(objects, fn(object) {
    case object.unit_type {
      static_object.Turret | static_object.SimpleCollidable ->
        case object.health {
          Some(static_object.Health(value:, ..)) -> value > 0
          None -> False
        }
      static_object.Door
      | static_object.Collectible
      | static_object.Simple
      | static_object.Platform
      | static_object.Mailbox
      | static_object.InstancePortal -> True
    }
  })
    as "every type 13 and 32 object is sent a health above 0, so the client does not create it dead"
  Nil
}

pub fn world_3460_visibility_index_is_19_41795_and_41803_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("world_data")
  use <- unitest.guard(client_tables.present())
  use <- unitest.guard(envoy.get("GENESIS_WORLD_DATA") != Error(Nil))
  // Creature2.prerequisiteIdVisibility of the creatures that start in World 3460
  // (spawn.left_out_of): Prerequisite 19 (type 250, the Exiles' base faction),
  // 41795 (type 15 on the hologram's spell 85562) and 41803 (type 43 on the
  // tutorial's quests 10527 and 10532). Prerequisites 41959 and 42962 belong to
  // creatures Friendly to both player factions, which are left out, so no unit
  // is shown or hidden by them.
  let assert Ok(folder) = envoy.get("GENESIS_WORLD_DATA")
    as "the guard saw the variable"
  let database = database_support.new_database(on: database_support.shared())
  let assert Ok(_) =
    import_world_data.import_spawns(
      db: content_support.connect(database:),
      folder:,
    )
    as "the world database imports"
  let tables = client_tables.with_content_tables()
  let assert Ok(rows) =
    content_spawn.rows(db: content_support.connect(database:))
    as "the spawn rows read back"
  let selection =
    spawn.select(
      rows: list.filter(rows, fn(row) { row.world_id == 3460 }),
      tables:,
      formulas: rating.formulas(tables:),
      kinds: spawn_support.kinds(),
      vendors: vendor.none(),
      factions: spawn_support.the_boss_is_given_233(tables:),
    )
  assert selection.refusals == [] as "every started spawn's prerequisite loads"
  let assert Ok(index) = dict.get(selection.visibility, 3460)
    as "World 3460 has an index"
  assert list.map(index, fn(one) { prerequisite.id(one).value })
    == [19, 41_795, 41_803]
    as "the World 3460 index holds the prerequisites of its started spawns and sent objects"
}
