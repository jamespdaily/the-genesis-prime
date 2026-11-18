//// The spawns that start in each world from Jim's whole world database, loaded
//// through the content load with the client's real tables. Expected values come
//// from these places.
//// - The decode of issue 375 (its facts `world_data.creature_disposition` and
////   `world_data.spawn_checks`), re-run by a scratch Python reimplementation of
////   the selection (a quest creature starts whatever else it links to, and
////   whether or not a player faction may attack it) that gave 40,043 with the
////   rows of faction 0 left out: world 22 starts 11,248 spawns, 51 13,173, 426 376,
////   870 693, 990 739, 1061 12,897, 1387 851 and 3460 66, and the other worlds
////   none. The rows left out in all are Friendly to both 7,400, a service link 33
////   and health 0 215.
//// - The rows of faction 0 start (`0x14045a950.faction_zero`: Neutral to both player
////   factions). A scratch Python script apart from the server's code, over
////   `spawn.tsv` (faction1, entity type, stat 0) and the client's Creature2 rows
////   (the quest and service columns), counts 452 NonPlayer rows with faction 0,
////   214, 180, 20 and 38 in worlds 22, 51, 426 and 1061, none with a service link
////   and no quest and none with health 0, so all start, added to the stored
////   spawns that start below.
//// - A creature with an objective link is not left out as Friendly to both
////   (`objective_link.has_link`: the client builds it whatever its faction), so
////   the Friendly rows with a link start. They are counted apart from
////   `spawn.select`, by a scratch Python script over `spawn.tsv` and the client's
////   Creature2 (questAnimStateId, prerequisiteIdAnimState, the quest and service
////   columns, factionId), Faction2 and Faction2Relationship rows with the
////   client's faction level walk: of the 7,400 stored rows Friendly to both with
////   no quest, 599, 581, 31, 9, 60 and 610 in worlds 22, 51, 426, 870, 990 and
////   1061 have a link, none of them a service link or health 0, so they start
////   (11,847, 13,754, 407, 702, 799 and 13,507 stored spawns in those worlds, the
////   faction-0 rows above not among them) and 5,510 stay Friendly to both.
//// - The creatures of kill objectives that the load places at their markers
////   (`objective_spawn.place`, in the worlds that hold a stored spawn) start in
////   addition. The rows placed are a count over the client's QuestObjective,
////   TargetGroup, WorldLocation2 and Creature2 tables and `spawn.tsv`, made
////   apart from the server's code by a scratch Python script over the same rows:
////   432, 608, 38, 20, 12, 623, 20 and 11 in worlds 22, 51, 426, 870, 990, 1061,
////   1387 and 3460 (11 there before migration 0029's turret rows, 9 with them, below),
////   and none in a world with no stored spawn. The same script's
////   rules over those rows' creatures find, of the rows placed, 9, 10, 0, 0, 0,
////   20, 0 and 5 Friendly to both with no quest, and of them 0, 8, 0, 0, 0, 20, 0
////   and 0 with a link, which start. The selection starts 423, 605, 38, 20, 12,
////   623, 20 and 6 of the rows placed and leaves out the others as it does stored
////   rows (Friendly to both, a service link, health 0).
//// - Migration 0027: the boss, Creature2 73499 (one of the 5 rows placed in 3460 that
////   are Friendly to both with no quest or link, QuestObjective 21296 and 21310),
////   stands with faction 233, Hostile to both player factions
////   (Faction2Relationship 746), so it starts. The left-out counts above are over the
////   stored rows alone, which it is not one of.
//// - Migration 0008: World 3460 also holds the 27 Virtual Defense Daguns, server
////   choices, which start (Hostile to Dominion), so 3460 has 66 + 27.
//// - Migration 0029: the Sim-Turrets start as creatures with factions 1441 (73494,
////   Exile) and 1442 (74862, Dominion), Hostile to their own side only. The 2 stored
////   type 13 rows of 73494 in 3460 start as creatures (so 3460 holds no static type
////   13 and 239 of the 241 remain) and hold it, so 73494 has no placed row and the
////   placed rows are 1,762 in all and 9 in 3460, 2 of them 74862's, which has no
////   stored row. 3460 starts 66 stored + 27 Daguns (migration 0008) + 2 stored
////   73494 rows + 9 placed rows = 104.
//// - The creatures of type 5 and 32 objectives (the click targets) that have no stored
////   spawn at their objective's marker are placed there too
////   (`objective_spawn.place`'s `click_rows`): 349 rows in all, 114 of them entity
////   type 0, the units that `WorldSpawns.by_id` holds (the others stand as the
////   static objects counted below), 113, 117, 5, 2, 106, 3 and 3 of them in worlds 22,
////   51, 426, 990, 1061, 1387 and 3460 (the whole-table test of `objective_spawn_test`
////   holds the count over the client's tables and `spawn.tsv`). The selection leaves
////   out none of the type 0 rows, Creature2 13133 in world 22 (no faction) among
////   them, so the creatures that start from them are 40, 27, 3 and 39 in worlds 22,
////   51, 426 and 1061 and none in the others. The counts come from a scratch Python script apart
////   from the server's code, over the client's table dumps (Creature2, Prerequisite,
////   Quest2, QuestObjective, WorldLocation2) and the world database's typed spawn
////   rows: it places 40, 27, 3 and 39 units (CreationTypeEnum 0) in worlds 22, 51, 426
////   and 1061, of which Creature2 13133 (factionId 0 in the Creature2 table) is the one
////   of world 22 that has no faction, and the play database's rows give the same.
////   The click table's pane creatures (`objective_spawn.place`'s `clicks`) add 2 started
////   units in world 22 (Creature2 26436 and 51440) and 3 in world 51 (Creature2 21688, 27100
////   and 27101), each placed at its marker; the table's other candidate, objective 13760's
////   Creature2 36601 of faction 219, is Friendly to both player factions with no quest or
////   link, so the selection leaves it out and the objective stays on the stand-in.
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
import genesis_prime/game/activate
import genesis_prime/game/click_objective
import genesis_prime/game/faction_level
import genesis_prime/game/kill_objective
import genesis_prime/game/place_objective
import genesis_prime/game/prerequisite
import genesis_prime/game/quest as quest_rules
import genesis_prime/game/quest_log
import genesis_prime/game/rating
import genesis_prime/game/target_group
import genesis_prime/game/vendor
import genesis_prime/import_world_data
import genesis_prime/readiness
import genesis_prime/step/runtime
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id, Quest2Id, QuestObjectiveId}
import genesis_prime/table/quest2
import genesis_prime/table/quest_objective
import genesis_prime/table/world
import genesis_prime/world_map/creature_unit_type
import genesis_prime/world_map/objective_spawn
import genesis_prime/world_map/spawn
import genesis_prime/world_map/static_object.{type StaticObject}
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import owned_key
import owned_test
import spawn_support
import terrain_support
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
      terrain: terrain_support.flat_reader(),
      key:,
    )
  let took = runtime.now().monotonic_ms - before
  assert loaded == Ok(Nil) as "the whole world database loads"
  let rows = content_support.stored_spawns(database:)
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
      kills: content_support.objective_ids(table: kill_objective.table),
      clicks: content_support.objective_ids(table: click_objective.table),
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
  let clicked =
    objective_spawn.place(
      tables:,
      stored: rows,
      factions: spawn_support.the_boss_is_given_233(tables:),
      kinds: spawn_support.turret_kinds(),
      kills: content_support.objective_ids(table: kill_objective.table),
      clicks: content_support.objective_ids(table: click_objective.table),
    ).click_rows
  assert list.length(clicked) == 349 as "the click targets' rows placed in all"
  assert list.count(clicked, fn(row) { row.entity_type == 0 }) == 114
    as "the click rows placed as units"
  assert list.map(
      [22, 51, 426, 870, 990, 1061, 1387, 3460, 1535, 3022],
      fn(world_id) { list.count(clicked, fn(row) { row.world_id == world_id }) },
    )
    == [113, 117, 5, 0, 2, 106, 3, 3, 0, 0]
    as "the click rows placed in each world"
  assert list.map(
      [22, 51, 426, 870, 990, 1061, 1387, 3460, 1535, 3022],
      fn(world_id) { dict.size(content_spawn.world(key:, world_id:).by_id) },
    )
    == [
      11_847 + 214 + 423 + 40 + 2,
      13_754 + 180 + 605 + 27 + 3,
      407 + 20 + 38 + 3,
      702 + 20,
      799 + 12,
      13_507 + 38 + 623 + 39,
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
  // A kill row leaves the stand-in only when its rule can fire: for each player faction its
  // quest allows (Quest2 `questPlayerFactionEnum`: 0 Exile, 1 Dominion, 2 either), a creature
  // of its reward pane starts in the world of each of its markers, stored or placed
  // (`objective_spawn.place`), and is not Friendly to that faction, so that player can
  // fight it (`0x1403ad540`; Friendly is level 8 to 10, `0x140787830`).
  let levels = faction_level.build(tables:)
  let listed = quest_log.listed_objectives(tables:)
  let started_by_world = fn(world_id) {
    list.map(dict.values(content_spawn.world(key:, world_id:).by_id), fn(one) {
      #(one.creature_id.value, one.faction_id)
    })
  }
  let player_factions = fn(quest_id) {
    let assert Ok(quest) = quest2.get(tables:, id: Quest2Id(quest_id))
      as "the listing quest is in the client's table"
    quest_rules.allowed_factions(quest:)
  }
  let fought_by = fn(player: Int, started: List(#(Int, Int)), pane: List(Int)) {
    list.any(started, fn(one) {
      list.contains(pane, one.0)
      && !spawn.friendly_to(levels:, player:, unit: one.1)
    })
  }
  // A click row leaves the stand-in only when its rule can fire: for each player faction its
  // quest allows, a creature of its reward pane starts in the world of each of its markers and
  // the client offers that player a click on it (`activate.offers_click`; a Hostile unit is
  // offered no use, `activate.Withheld`).
  let clicked_by = fn(player: Int, started: List(#(Int, Int)), pane: List(Int)) {
    list.any(started, fn(one) {
      let assert Ok(row) = creature2.get(tables, Creature2Id(one.0))
        as "a started creature is in the client's table"
      list.contains(pane, one.0)
      && activate.offers_click(row:)
      && !faction_level.hostile(levels:, from: player, to: one.1)
    })
  }
  let unreached = fn(objective_ids, reached_by) {
    list.filter(objective_ids, fn(objective_id) {
      let assert Ok(row) =
        quest_objective.get(tables:, id: QuestObjectiveId(objective_id))
        as "the objective is in the client's table"
      let pane =
        target_group.listed_creatures(
          tables:,
          group: row.target_group_id_reward_pane,
        )
      let assert Ok(places) = dict.get(listed, objective_id)
        as "a quest lists the objective"
      let factions =
        list.flat_map(places, fn(place) { player_factions({ place.0 }.id) })
      list.any(place_objective.markers(tables:, objective: row), fn(marker) {
        let started = started_by_world(marker.world_id)
        list.any(factions, fn(player) { !reached_by(player, started, pane) })
      })
    })
  }
  assert unreached(
      set.to_list(content_support.objective_ids(table: kill_objective.table)),
      fought_by,
    )
    == []
    as "every kill row has, for each faction its quest allows, a creature of its pane that starts in each world its markers are in and that faction can fight"
  assert unreached([4282, 7272, 7491, 7492], fought_by)
    == [4282, 7272, 7491, 7492]
    as "the four kill rows left on the stand-in have no such creature (the CI test of the table shows their creatures are Friendly to both factions)"
  assert unreached(
      set.to_list(content_support.objective_ids(table: click_objective.table)),
      clicked_by,
    )
    == []
    as "every click row has, for each faction its quest allows, a creature of its pane that starts in each world its markers are in and that the client offers that faction a click on"
  assert unreached([13_760], clicked_by) == [13_760]
    as "objective 13760 (quest 6959), left on the stand-in, has no such creature: Creature2 36601 of faction 219 is Friendly to both player factions and the selection leaves it out"
  // A NonPlayer row placed as part of a map object (`active_prop_id` not 0) never
  // moves: `spawn.tsv` holds 630 such rows of 164 creatures, and each one that
  // starts has no run speed.
  let linked_rows =
    list.filter(rows, fn(row) {
      row.entity_type == 0 && row.world_object_id != 0
    })
  assert list.length(linked_rows) == 630
    as "the world database's NonPlayer rows placed as part of a map object"
  assert list.length(
      list.unique(list.map(linked_rows, fn(row) { row.creature_id })),
    )
    == 164
    as "and their creatures"
  let started =
    list.flat_map(world.all(tables), fn(row) {
      dict.values(content_spawn.world(key:, world_id: row.id).by_id)
    })
  let linked_started =
    list.filter(started, fn(one) {
      one.unit_type == creature_unit_type.NonPlayer && one.world_object_id != 0
    })
  assert list.all(linked_started, fn(one) { one.combat.attack.run_speed == 0.0 })
    as "none of them moves"
  // Every linked row is either started or left out for one of the selection's reasons
  // (friendly to both, a service link, health 0), so the 630 are all explained.
  let linked_selection =
    spawn.select(
      rows: linked_rows,
      tables:,
      formulas: rating.formulas(tables:),
      kinds: spawn_support.kinds(),
      vendors: vendor.none(),
      factions: spawn_support.the_boss_is_given_233(tables:),
    )
  assert linked_selection.refusals == []
    as "no linked row is refused, so none is missing from the count"
  let linked_started_count =
    list.fold(linked_selection.coverage, 0, fn(total, world) {
      total + world.started
    })
  let linked_left_out_count = fn(reason) {
    list.flat_map(linked_selection.coverage, fn(world) { world.left_out })
    |> list.filter(fn(entry) { entry.0 == reason })
    |> list.fold(0, fn(total, entry) { total + entry.1 })
  }
  assert linked_started_count
    + linked_left_out_count(spawn.FriendlyToBoth)
    + linked_left_out_count(spawn.ServiceLink)
    + linked_left_out_count(spawn.Dead)
    == 630
    as "the linked rows that start, plus those left out as friendly to both, with a service link and dead, are the 630 rows"
  assert linked_started_count == list.length(linked_started)
    as "the linked rows the load starts are the ones the selection starts"
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
      [spawn.FriendlyToBoth, spawn.ServiceLink, spawn.Dead],
      left_out_in_all,
    )
    == [5510, 33, 215]
    as "the rows left out in all worlds: Friendly to both, a service link, health 0"
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
    == [171, 4380 + 135, 17_904 + 71, 491 + 4, 101, 239, 79 + 2, 1178 + 23]
    as "every static spawn of the world database loads, and the click rows placed as static types (135, 71, 4, 2 and 23 of types 8, 10, 11, 14 and 32), by type"
  let ship = dict.values(content_spawn.world(key:, world_id: 3460).objects)
  assert list.map(spawn.object_types, of_type(ship, _))
    == [0, 0, 302, 0, 0, 0, 0, 15 + 3]
    as "world 3460's static objects, by type: the 3 Dominion mines placed at their markers (Creature2 73463, 73667 and 73668) are type 32 beside its 15 stored"
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
  let rows = content_support.stored_spawns(database:)
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
