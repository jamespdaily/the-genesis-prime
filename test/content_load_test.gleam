//// The content load at start (`genesis_prime/content`), run on databases of the
//// test's own. Expected values come from these places.
//// - The design of the world spawns (the Design artifact of issue 375, sections 1
////   and 6): the load waits for the database as readiness does and the tree
////   starts after it; a database whose migrations differ stops the start with the
////   difference; a refused row stops the start with the reason, and every refusal
////   of every table is logged first, so two bad rows are both named by table, id
////   and rule; a failed query stops the start with the database's reason.
//// - The migrations' own refusals are those of `genesis_prime/migration` (the
////   sentences `migration_start_test` pins).
//// - The 27 Virtual Defense Daguns are server-choice rows of migration 0008, so a
////   migrated database holds them and the load puts them in World 3460's term.
//// - Migration 0027 gives the tutorial boss (Creature2 73499, whose row says faction
////   219, Friendly to both player factions) faction 233, Hostile to both
////   (Faction2Relationship 746), so the boss starts; Creature2 74862 keeps 219.
//// The waits are the load's own settings, shortened here, so no test waits 30 s.

import character_tables
import content_support
import database_support
import fixture_tables
import genesis_prime/connection/frame.{Frame}
import genesis_prime/content
import genesis_prime/content/class_resource as content_class_resource
import genesis_prime/content/creature_kind as content_creature_kind
import genesis_prime/content/game_number as content_game_number
import genesis_prime/content/objective_set
import genesis_prime/content/projector_landing as content_projector_landing
import genesis_prime/content/refusal.{Refusal}
import genesis_prime/content/server_proxy as content_server_proxy
import genesis_prime/content/spawn as content_spawn
import genesis_prime/content/terrain as content_terrain
import genesis_prime/content/tutorial_quest as content_tutorial_quest
import genesis_prime/content/vendor as content_vendor
import genesis_prime/content/zone_welcome as content_zone_welcome
import genesis_prime/game/activate
import genesis_prime/game/arrival_objective
import genesis_prime/game/class_resource
import genesis_prime/game/click_objective
import genesis_prime/game/connection/state as connection_state
import genesis_prime/game/held_objective
import genesis_prime/game/kill_objective
import genesis_prime/game/projector
import genesis_prime/game/server_proxy
import genesis_prime/game/spell_plan
import genesis_prime/game/start_place
import genesis_prime/game/zone_welcome
import genesis_prime/migration
import genesis_prime/readiness
import genesis_prime/table/id.{ClassId, Creature2Id, Spell4Id}
import genesis_prime/world_map/creature_kind
import genesis_prime/world_map/spawn
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/spawn_source.{Summoned}
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option
import gleam/set
import gleam/string
import log_capture
import login_support
import mailbox_support
import owned_test
import place_support
import planted_table
import server_proxy_support
import spawn_support
import spell_tables
import tutorial_support
import unitest

/// A spawn row of a creature the client has no row for, as the world database's
/// row `row`.
fn bad_row(row row: Int, creature creature: Int) -> String {
  "insert into spawn (source, source_row, entity_type, creature_id, world_id, area_id, x, y, z, rotation_x, rotation_y, rotation_z, display_info_id, outfit_info_id, faction_id, base_faction_id, active_prop_id, world_socket_id) values ('world_database', "
  <> int.to_string(row)
  <> ", 0, "
  <> int.to_string(creature)
  <> ", 3460, 0, 0, 0, 0, 0, 0, 0, 26565, 0, 1441, 1441, 0, 0)"
}

/// How many of the spawns stand a creature of this Creature2 id.
fn count_of(
  spawns spawns: dict.Dict(a, spawn.Spawn),
  creature creature: Int,
) -> Int {
  list.count(dict.values(spawns), fn(one) {
    one.creature_id == Creature2Id(creature)
  })
}

pub fn the_load_puts_the_migrated_databases_spawns_in_the_worlds_term_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil) as "a migrated database loads"
  let world = content_spawn.world(key:, world_id: 3460)
  assert dict.size(world.by_id) == 27 + 12 + 4
    as "migration 0008's 27 Virtual Defense Daguns, and the 16 creatures that start of the ones the fixture's kill objectives with a marker in World 3460 place, the boss and the four Sim-Turrets included"
  assert count_of(spawns: world.by_id, creature: 73_465) == 27
    as "the 27 Virtual Defense Daguns are the stored spawns the template holds"
  assert list.map([73_492, 73_567, 73_473, 73_566], fn(creature) {
      count_of(spawns: world.by_id, creature:)
    })
    == [2, 1, 2, 1]
    as "objective 21290's group 14356 (73492, 73567, 73492) and objective 21317's group 14402 (73473, 73566, 73473) place 3 each, alternating the group's creatures"
  assert count_of(spawns: world.by_id, creature: 73_464) == 5
    as "objective 21286 (quest 10518) counts 5 of Creature2 73464, which stands 5 times"
  assert dict.size(content_spawn.world(key:, world_id: 22).by_id) == 0
    as "a World row with no spawn that starts has an empty term"
  assert list.sort(
      dict.keys(content_terrain.world(key:, world_id: 3460).areas),
      int.compare,
    )
    == [64 * 128 + 63, 64 * 128 + 64]
    as "migration 0008's 27 stored spawns stand at x -9.0 to 84.8 and z 252.1 to 328.7: area row 64, columns 63 and 64 (area_file.cell), the two squares the ground holds"
  assert dict.size(content_terrain.world(key:, world_id: 22).areas) == 0
    as "a World row with no stored spawn holds an empty ground"
}

pub fn the_boss_starts_with_its_chosen_faction_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil) as "a migrated database loads"
  let world = content_spawn.world(key:, world_id: 3460)
  assert count_of(spawns: world.by_id, creature: 73_499) == 1
    as "objectives 21296 and 21310 place one boss at marker 51744, and migration 0027 gives it faction 233 in place of its Creature2 row's 219, Friendly to both"
  let assert Ok(boss) =
    list.find(dict.values(world.by_id), fn(one) {
      one.creature_id == Creature2Id(73_499)
    })
    as "the boss starts"
  assert boss.faction_id == 233 && boss.base_faction_id == 233
    as "Faction2Relationship 746 makes 233 Hostile to the parent of both player factions"
}

pub fn the_sim_turrets_start_with_their_chosen_factions_and_charges_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil) as "a migrated database loads"
  let world = content_spawn.world(key:, world_id: 3460)
  let factions = fn(creature) {
    world.by_id
    |> dict.values
    |> list.filter(fn(one) { one.creature_id == Creature2Id(creature) })
    |> list.map(fn(one) { #(one.faction_id, one.base_faction_id) })
  }
  assert factions(73_494) == [#(1441, 1441), #(1441, 1441)]
    as "objective 21288 counts 2 of Creature2 73494, which migration 0029 gives faction 1441, Hostile to Exile (Faction2Relationship 2943)"
  assert factions(74_862) == [#(1442, 1442), #(1442, 1442)]
    as "objective 21316 counts 2 of Creature2 74862, which migration 0029 gives faction 1442, Hostile to Dominion (Faction2Relationship 2946)"
  let kinds = content_creature_kind.kinds(key:)
  let charge = fn(creature) {
    let kind = creature_kind.kind_of(kinds:, creature2_id: creature)
    #(kind.attack_spell4_id, kind.attack_interval_ms)
  }
  assert charge(73_494) == #(Spell4Id(85_469), 3000)
    as "migration 0029 gives the Exile turret its charge, Spell4 85469, and the interval server choice"
  assert charge(74_862) == #(Spell4Id(86_978), 3000)
    as "migration 0029 gives the Dominion turret its charge, Spell4 86978, and the interval server choice"
}

pub fn a_summon_of_the_boss_after_the_load_takes_its_chosen_faction_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil) as "a migrated database loads"
  let assert Ok(summoned) =
    spawn.summoned(
      checks: content_spawn.summon_checks(key:),
      summoned: Summoned(
        id: SpawnId(-1),
        creature_id: Creature2Id(73_499),
        level: option.None,
        place: place_support.at(
          world_id: 3460,
          world_zone_id: 5968,
          x: 0.0,
          y: 0.0,
          z: 0.0,
        ),
      ),
    )
    as "the summon checks the load put hold the boss's chosen faction, so the boss would start"
  assert summoned.faction_id == 233 && summoned.base_faction_id == 233
    as "Faction2Relationship 746 makes 233 Hostile to the parent of both player factions"
}

pub fn the_load_puts_the_kinds_in_a_term_the_default_row_is_the_60_second_choice_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "insert into creature_kind (creature_id, respawn_ms, attack_spell4_id, attack_interval_ms, source, reason) values (73464, 5000, 5649, 1500, 'server_choice', 'a short respawn for the training Beast')",
  )
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil)
  let kinds = content_creature_kind.kinds(key:)
  assert creature_kind.kind_of(kinds:, creature2_id: 73_464).respawn_ms == 5000
    as "a creature with a row of its own takes it"
  assert creature_kind.kind_of(kinds:, creature2_id: 73_465).respawn_ms
    == 60_000
    as "any other creature takes the default row of migration 0009 (death.creature_respawn)"
}

pub fn a_database_with_no_default_kind_stops_the_load_naming_the_table_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "delete from creature_kind where creature_id = 0",
  )
  let #(loaded, _key) = content_support.load(database:)
  let assert Error(content.Refused(refusals:)) = loaded
    as "no default row stops the start"
  assert list.map(refusals, fn(refused) { #(refused.table, refused.row) })
    == [#("creature_kind", refusal.RowId(0))]
}

pub fn a_kind_row_for_a_creature_the_client_does_not_hold_stops_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "insert into creature_kind (creature_id, respawn_ms, attack_spell4_id, attack_interval_ms, source, reason) values (200001, 5000, 5649, 1500, 'server_choice', 'a creature the client does not hold')",
  )
  let #(loaded, _key) = content_support.load(database:)
  let assert Error(content.Refused(refusals:)) = loaded
    as "a refused kind row stops the start"
  assert list.map(refusals, fn(refused) { #(refused.table, refused.row) })
    == [#("creature_kind", refusal.RowId(200_001))]
}

pub fn a_held_row_naming_an_objective_the_client_does_not_hold_stops_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "insert into held_objective (objective_id, kind, source, reason) values (4000000, 'instance_run', 'server_choice', 'an objective the client does not hold')",
  )
  let #(loaded, _key) = content_support.load(database:)
  let assert Error(content.Refused(refusals:)) = loaded
    as "a refused held row stops the start"
  assert list.map(refusals, fn(refused) { #(refused.table, refused.row) })
    == [#("held_objective", refusal.RowId(4_000_000))]
}

pub fn the_content_load_puts_the_held_objectives_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil)
  let held = objective_set.read(key:, table: held_objective.table)
  assert set.size(held) == 146
    as "migrations 0034, 0039 and 0041 seed 146 held_objective rows"
  assert list.all([12_547, 17_882, 21_536, 19_357, 21_267], fn(objective) {
    set.contains(held, objective)
  })
    as "migration 0034's first row (12547, an instance run), a pvp_match row (17882) and its last row (21536), migration 0039's 19357 and migration 0041's 21267 (a store purchase, which the load accepts: type 5, visible, required, unlinked)"
  assert !set.contains(held, 12_548)
    as "an objective migration 0034 does not list is not held"
}

/// A content table whose rows each name a QuestObjective: what the migrated database holds in
/// it, how the connections' settings carry it, and a row the load refuses.
type ObjectiveTable {
  ObjectiveTable(
    table: String,
    /// How many rows the migrations seed.
    size: Int,
    /// Rows the migrations seed, and the reason each is listed.
    members: List(Int),
    /// An objective the migrations do not list.
    not_a_member: Int,
    carried: fn(connection_state.Settings) -> set.Set(Int),
    /// An objective the load refuses, and why.
    refused: Int,
    refused_because: String,
  )
}

pub fn an_objective_table_loads_its_rows_and_a_refused_row_stops_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = [
    ObjectiveTable(
      table: arrival_objective.table,
      size: 50,
      members: [4770, 19_336, 19_357, 7342, 18_099],
      not_a_member: 4849,
      carried: fn(settings) { settings.arrival_objectives },
      // QuestObjective 4849 is a visible marked script that a type 42 spell effect names: a
      // cast advances it, so it is no place (`objective_action.named`).
      refused: 4849,
      refused_because: "an objective a spell effect names",
    ),
    ObjectiveTable(
      table: kill_objective.table,
      size: 9,
      members: [8010, 8866, 15_996],
      not_a_member: 7515,
      carried: fn(settings) { settings.script_rows.kills },
      // QuestObjective 4000000 is no row of the client's table.
      refused: 4_000_000,
      refused_because: "an objective the client lacks",
    ),
    ObjectiveTable(
      table: click_objective.table,
      size: 5,
      members: [7652, 7653, 7654, 9002, 16_170],
      not_a_member: 7515,
      carried: fn(settings) { settings.script_rows.clicks },
      refused: 4_000_000,
      refused_because: "an objective the client lacks",
    ),
  ]
  list.each(tables, fn(row) {
    let database = database_support.new_database(on: database_support.shared())
    let #(loaded, key) = content_support.load(database:)
    assert loaded == Ok(Nil) as row.table
    let rows = objective_set.read(key:, table: row.table)
    assert set.size(rows) == row.size
      as { row.table <> ": the migrations seed this many rows" }
    assert list.all(row.members, fn(objective) { set.contains(rows, objective) })
      as { row.table <> ": the first, last or named rows its migrations list" }
    assert !set.contains(rows, row.not_a_member)
      as { row.table <> ": an objective its migrations do not list is no row" }
    assert row.carried(
        login_support.servers_settings_over(spawns: key).game.settings,
      )
      == rows
      as { row.table <> ": the settings the load's key gave carry the table" }
    let refused = database_support.new_database(on: database_support.shared())
    content_support.change(
      database: refused,
      sql: "insert into "
        <> row.table
        <> " (objective_id, source, reason) values ("
        <> int.to_string(row.refused)
        <> ", 'server_choice', '"
        <> row.refused_because
        <> "')",
    )
    let #(loaded, _key) = content_support.load(database: refused)
    let assert Error(content.Refused(refusals:)) = loaded
      as { row.table <> ": a refused row stops the start" }
    assert list.map(refusals, fn(refused) { #(refused.table, refused.row) })
      == [#(row.table, refusal.RowId(row.refused))]
      as { row.table <> ": the refusal names the table and the row" }
  })
}

pub fn the_load_puts_every_term_the_game_listener_reads_at_start_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil)
  // The readers of the content terms `genesis_prime.game` puts in each connection's
  // settings: a term the load did not put crashes its reader.
  let _classes = content_class_resource.classes(key:)
  let _proxies = content_server_proxy.proxies(key:)
  let _welcomes = content_zone_welcome.zone_welcomes(key:)
  let _vendors = content_vendor.vendors(key:)
  let _numbers = content_game_number.numbers(key:)
  let _visibility = content_spawn.visibility(key:)
  let _chain = content_tutorial_quest.chain(key:)
  let _landings = content_projector_landing.landings(key:)
  let _reused = content_spawn.reused_unit_objectives(key:)
  let _held = objective_set.read(key:, table: held_objective.table)
  let _arrivals = objective_set.read(key:, table: arrival_objective.table)
  let _kills = objective_set.read(key:, table: kill_objective.table)
  let _clicks = objective_set.read(key:, table: click_objective.table)
  Nil
}

pub fn the_load_puts_the_reused_objectives_of_every_type_test() -> Nil {
  use <- owned_test.run(60_000)
  // The migrations seed spawns of no quest creature, so every objective of a count above
  // 1 whose creatures the objective lists has a supply of none and is reused
  // (`objective_units.reused`); the load puts the set under the key the connection's
  // settings read. The fixture's rows (`table_rows -- QuestObjective <id>`): 4470 is type
  // 12 (Creature2 11070, count 3), 4813 type 32 (crate 12919, count 6), 15980 type 5
  // (Creature2 19277, count 3), 10383 type 23 (TargetGroup 3568, count 15) and 11555
  // type 11 (reward pane 3699, count 4); 17932 is type 12 with count 1.
  let database = database_support.new_database(on: database_support.shared())
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil)
  let reused = content_spawn.reused_unit_objectives(key:)
  assert list.all([4470, 4813, 15_980, 10_383, 11_555], fn(objective_id) {
    set.contains(reused, objective_id)
  })
    as "an objective of each of types 12, 32, 5, 23 and 11 whose world holds none of its units is reused"
  assert !set.contains(reused, 17_932)
    as "an objective of count 1 is never reused"
}

pub fn the_servers_settings_run_over_a_real_load_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil)
  // `genesis_prime.settings` reads every content term the game listener needs: a term
  // the load did not put crashes here, naming it.
  let settings = login_support.servers_settings_over(spawns: key)
  assert set.contains(settings.game.settings.held_objectives, 12_547)
    as "migration 0034's first held objective (12547) is in the settings the load's key gave"
  assert set.contains(settings.game.settings.arrival_objectives, 4770)
    as "migration 0038's Tower objective (4770) is in the settings the load's key gave"
  assert settings.game.settings.tutorial_chain
    == content_tutorial_quest.chain(key:)
    as "the settings carry the tutorial chain the load put"
}

pub fn the_helpers_content_terms_equal_the_loads_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil)
  let loaded_terms = content_support.terms(key)
  let helped_terms = content_support.terms(spawn_support.key_without_spawns())
  assert loaded_terms != []
    as "the load's content terms are found in the store; a changed store layout would empty both lists"
  assert list.filter(loaded_terms, fn(term) {
      !list.contains(helped_terms, term)
    })
    |> list.map(term_name)
    == []
    as "a content term the load puts and the test helper does not: add it to spawn_support's puts"
  assert list.filter(helped_terms, fn(term) {
      !list.contains(loaded_terms, term)
    })
    |> list.map(term_name)
    == []
    as "a content term the test helper puts and the load does not"
}

/// A content term as `table/id`, for a failure that names it.
fn term_name(term: #(String, Int)) -> String {
  term.0 <> "/" <> int.to_string(term.1)
}

pub fn a_refused_kind_row_does_not_hide_a_refused_spawn_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "insert into creature_kind (creature_id, respawn_ms, attack_spell4_id, attack_interval_ms, source, reason) values (200001, 5000, 5649, 1500, 'server_choice', 'a creature the client does not hold')",
  )
  content_support.change(database:, sql: bad_row(row: 1, creature: 200_002))
  let #(loaded, _key) = content_support.load(database:)
  let assert Error(content.Refused(refusals:)) = loaded
    as "the refused rows stop the start"
  assert list.map(refusals, fn(refused) { #(refused.table, refused.rule) })
    == [
      #("spawn", "Creature2 200002 has no row"),
      #("creature_kind", "the client's Creature2 table has no such creature"),
    ]
    as "the spawns are checked with the kinds the load took, so one start names both bad rows"
}

pub fn a_database_that_answers_late_is_waited_for_and_loaded_from_test() -> Nil {
  use <- owned_test.run(60_000)
  // The probe finds the database away for its first five asks, as a database that
  // is still starting is, and then asks the pool: no wall-clock wait, and a
  // window of 100 ms that passes with no answer, which the load warns about and
  // asks again after.
  let database = database_support.new_database(on: database_support.shared())
  let away = process.new_subject()
  list.each(list.repeat(Nil, 5), fn(_) { process.send(away, Nil) })
  let #(loaded, key) =
    content_support.load_asking(
      database:,
      ask: readiness.Settings(within_ms: 100, attempt_ms: 500, pause_ms: 50),
      probe: fn(db) {
        fn(reply) {
          case process.receive(away, within: 0) {
            Ok(Nil) -> Error(Nil)
            Error(Nil) -> content.pool_probe(db)(reply)
          }
        }
      },
    )
  assert loaded == Ok(Nil)
    as "the load asked again until the database answered, and then loaded it"
  // Absence check: the limit is how long this watches for a message that must
  // not come, here a look at the mailbox now.
  assert process.receive(away, within: 0) == Error(Nil)
    as "it was told five times that the database was away"
  assert dict.size(content_spawn.world(key:, world_id: 3460).by_id)
    == 27 + 12 + 4
    as "the 27 stored spawns and the 16 marker-placed ones that start"
}

pub fn a_database_whose_migrations_differ_stops_the_load_with_the_difference_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "delete from schema_migration where name = '0008_spawn'",
  )
  let #(loaded, _key) = content_support.load(database:)
  assert loaded
    == Error(content.MigrationsDiffer(migration.NotApplied(name: "0008_spawn")))
    as "the database has not run the migration 0008_spawn"
}

pub fn two_refused_rows_are_both_logged_with_table_id_and_rule_and_stop_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.tag("serial")
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(database:, sql: bad_row(row: 1, creature: 200_001))
  content_support.change(database:, sql: bad_row(row: 2, creature: 200_002))
  let lines = process.new_subject()
  let capture = log_capture.start_all(into: lines)
  let #(loaded, _key) = content_support.load(database:)
  log_capture.stop(capture)
  let assert Error(content.Refused(refusals:)) = loaded
    as "bad rows stop the load"
  assert list.map(refusals, fn(refused) { #(refused.table, refused.rule) })
    == [
      #("spawn", "Creature2 200001 has no row"),
      #("spawn", "Creature2 200002 has no row"),
    ]
    as "both rows are refused, each naming the table and the rule: one bad row shows its neighbours"
  assert list.all(refusals, fn(refused) {
    case refused.row {
      refusal.RowId(id:) -> id > 0
      refusal.RowName(..) -> False
    }
  })
  let logged =
    mailbox_support.drain(lines)
    |> list.map(fn(line) { line.1 })
    |> list.filter(string.contains(_, "is refused"))
  assert list.length(logged) == 2
    && list.all(refusals, fn(refused) {
      list.contains(logged, refusal.describe(refused))
    })
    as "every refusal is logged before the start stops"
  assert refusal.describe(Refusal(
      table: "spawn",
      row: refusal.RowId(5),
      rule: "a rule",
    ))
    == "the table spawn row 5 is refused: a rule"
}

pub fn a_stored_spawn_at_the_first_placed_id_stops_the_load_naming_it_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("serial")
  // The spawns the server places for a quest take the ids from 1,000,000,000 up, so a stored
  // row at that id could be taken for one (`objective_spawn`). The row is a copy of a
  // migrated one, so the id is the only thing wrong with it.
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "insert into spawn (id, source, source_row, entity_type, creature_id, world_id, area_id, x, y, z, rotation_x, rotation_y, rotation_z, display_info_id, outfit_info_id, faction_id, base_faction_id, active_prop_id, world_socket_id) overriding system value select 1000000000, 'world_database', 999999999, entity_type, creature_id, world_id, area_id, x, y, z, rotation_x, rotation_y, rotation_z, display_info_id, outfit_info_id, faction_id, base_faction_id, active_prop_id, world_socket_id from spawn order by id limit 1",
  )
  let lines = process.new_subject()
  let capture = log_capture.start_all(into: lines)
  let #(loaded, _key) = content_support.load(database:)
  log_capture.stop(capture)
  let assert Error(content.Refused(refusals:)) = loaded
    as "a stored spawn at the first placed id stops the start"
  assert refusals
    == [
      Refusal(
        table: "spawn",
        row: refusal.RowId(1_000_000_000),
        rule: "its id is at or above 1000000000, where the spawns the server places begin",
      ),
    ]
    as "the refusal names the table, the row's id and the rule"
  assert list.any(mailbox_support.drain(lines), fn(line) {
    line.1
    == "the table spawn row 1000000000 is refused: its id is at or above 1000000000, where the spawns the server places begin"
  })
    as "the refusal is logged before the start stops"
}

pub fn the_load_puts_every_stored_and_placed_spawn_id_in_the_ids_term_test() -> Nil {
  use <- owned_test.run(10_000)
  // The migrated database holds the 27 Virtual Defense Daguns of World 3460; the load places
  // the creatures of the quest markers there that no stored row serves, and every placed row
  // there starts (`a_database_that_answers_late_is_waited_for_and_loaded_from_test` counts the
  // 16 started). The ids term holds every stored row's id and every placed row's, started or
  // not, so a quest's used objects of either are kept; because every placed row here starts,
  // the term's ids from the first placed id up equal the started ones.
  let database = database_support.new_database(on: database_support.shared())
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil)
  let ids = content_spawn.loaded_spawns(key:).ids
  let stored = content_support.stored_spawns(database:)
  assert stored != []
  assert list.all(stored, fn(row) { set.contains(ids, row.id) })
    as "every stored row's id is in the term"
  let world = content_spawn.world(key:, world_id: 3460)
  let started = list.append(dict.keys(world.by_id), dict.keys(world.objects))
  assert list.all(started, fn(id) { set.contains(ids, id) })
    as "every spawn and object of the world's term has its id in the ids term"
  let above_the_stored = fn(ids: List(spawn_id.SpawnId)) {
    list.filter(ids, fn(id) {
      let SpawnId(number) = id
      number >= 1_000_000_000
    })
    |> list.sort(fn(a, b) {
      let SpawnId(a) = a
      let SpawnId(b) = b
      int.compare(a, b)
    })
  }
  assert above_the_stored(set.to_list(ids)) == above_the_stored(started)
    as "an id from 1,000,000,000 up in the term is one of the placed rows the world's term holds, and each of them is there, since every placed row of this world starts"
  assert above_the_stored(started) != []
    as "the load places rows in the migrated database's world"
}

pub fn a_query_that_fails_stops_the_load_with_the_databases_reason_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "alter table spawn rename column x to east",
  )
  let #(loaded, _key) = content_support.load(database:)
  let assert Error(content.QueryFailed(table: "spawn", reason:)) = loaded
    as "a failed query stops the load"
  assert string.contains(reason, "undefined_column")
    as { "the database's reason is named: " <> reason }
}

pub fn a_missing_and_an_unknown_game_number_stop_the_load_each_named_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "delete from game_number where name = 'leash_range'",
  )
  // The table refuses a name nobody listed, so the name is listed first (a new
  // name is one insert, migration 0014); the server still has no use for it.
  content_support.change(
    database:,
    sql: "insert into game_number_name (name, unit) values ('evade_range', 'units')",
  )
  content_support.change(
    database:,
    sql: "insert into game_number (name, value, unit, source, reason) values ('evade_range', 30, 'units', 'server_choice', 'a number the server has no use for')",
  )
  let #(loaded, _key) = content_support.load(database:)
  let assert Error(content.Refused(refusals:)) = loaded
    as "a game number the server does not know, or one it reads and does not find, stops the start (the design of step F, section 2)"
  assert list.map(refusals, fn(refused) { #(refused.table, refused.row) })
    == [
      #("game_number", refusal.RowName("evade_range")),
      #("game_number", refusal.RowName("leash_range")),
    ]
    as "each refusal names the table and the number by its name"
}

pub fn a_missing_armor_refill_time_stops_the_load_named_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "delete from game_number where name = 'interrupt_armor_refill_ms'",
  )
  let #(loaded, _key) = content_support.load(database:)
  let assert Error(content.Refused(refusals:)) = loaded
    as "a creature that cannot refill its armor stops the start (migration 0016)"
  assert list.map(refusals, fn(refused) { #(refused.table, refused.row) })
    == [#("game_number", refusal.RowName("interrupt_armor_refill_ms"))]
}

pub fn the_load_puts_each_playable_classs_resource_in_a_term_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil)
  let assert Ok(stalker) =
    class_resource.of_class(
      classes: content_class_resource.classes(key:),
      class_id: ClassId(5),
    )
    as "migration 0011 holds the Stalker's rows"
  assert stalker
    == class_resource.Resource(
      slot: 3,
      vitals: [5, 13, 13, 12, 9, 10, 11, 16],
      max: 100.0,
      start: 100.0,
      regen: option.Some(class_resource.Regen(per_tick: 7.0, tick_ms: 1000)),
      refill_after_combat_ms: option.None,
      drain: option.None,
      empty_after_combat_ms: option.None,
      focus: option.None,
    )
    as "the design: Suit Power in slot 3, 100, full at the start, +7 each second"
}

pub fn a_playable_class_with_no_max_row_stops_the_load_naming_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "delete from class_resource where class_id = 3 and name = 'max'",
  )
  let #(loaded, _key) = content_support.load(database:)
  let assert Error(content.Refused(refusals:)) = loaded
    as "a playable class with no maximum stops the start (the design, test 14)"
  assert list.map(refusals, fn(refused) { #(refused.table, refused.row) })
    == [#("class_resource", refusal.RowName("3 max"))]
}

pub fn a_class_missing_the_rows_of_its_refill_stops_the_load_naming_each_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "delete from class_resource where (class_id = 4 and name = 'refill_after_combat_ms') or (class_id = 5 and name like 'regen%') or (class_id = 7 and name = 'regen_amount')",
  )
  let #(loaded, _key) = content_support.load(database:)
  let assert Error(content.Refused(refusals:)) = loaded
    as "the Medic's refill, the Stalker's and the Spellslinger's regeneration each need their rows (the design's values table): a class that would never refill stops the start"
  assert list.map(refusals, fn(refused) { #(refused.table, refused.row) })
    == [
      #("class_resource", refusal.RowName("4 refill_after_combat_ms")),
      #("class_resource", refusal.RowName("5 regen_amount")),
      #("class_resource", refusal.RowName("5 regen_period_ms")),
      #("class_resource", refusal.RowName("5 regen_tick_ms")),
      #("class_resource", refusal.RowName("7 regen_amount")),
    ]
    as "each missing row is named by its class and number"
}

pub fn the_load_puts_the_servers_proxies_in_a_term_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil)
  assert server_proxy_support.changes(
    proxies: content_server_proxy.proxies(key:),
    plans: spell_plan.plans(character_tables.content_tables()),
    base: 26_468,
  )
    as "migration 0018's seed row, Pulse Blast's go 1 casting 42148, is selected over the committed spell trees and kept"
}

pub fn the_load_puts_the_zones_welcomes_from_the_seed_in_a_term_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil)
  let welcomes = content_zone_welcome.zone_welcomes(key:)
  assert zone_welcome.on_terrain_loaded(welcomes:, world_zone_id: 648)
    == [Frame(message_id: 0x0179, body: <<0x4c, 0x01, 0x00, 0x00>>)]
    as "migration 0020 seeds WorldZone 35 with Tutorial 332 (the Northern Wilds welcome), and 648 Landing Site's parent is 35; 0x179 carries 332 in 32 bits, least significant byte first"
}

pub fn the_tutorial_chain_loads_from_the_migration_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil)
  let chain = content_tutorial_quest.chain(key:)
  assert tutorial_support.order(chain:, faction_enum: 0)
    == [10_513, 10_527, 10_518, 10_529]
    as "migration 0031's Exile rows, each following the one before: Navigating Nexus part 1 and 2, The Face of the Enemy, and its closing talk to Dorian Walker"
  assert tutorial_support.order(chain:, faction_enum: 1)
    == [10_521, 10_532, 10_524, 10_533]
    as "migration 0031's Dominion rows, the same four quests of the Dominion"
}

pub fn the_projector_landings_load_from_the_migration_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil)
  let landings = content_projector_landing.landings(key:)
  let zone_of = fn(creature, faction) {
    let assert Ok(place) =
      projector.landing(
        landings:,
        creature_id: Creature2Id(creature),
        faction_id: faction,
        link: activate.OpenLink,
      )
      as "migration 0032 seeds a landing for each projector and faction"
    start_place.world_zone_id(place)
  }
  assert [
      zone_of(73_735, spawn.exile_faction),
      zone_of(73_735, spawn.dominion_faction),
      zone_of(73_741, spawn.exile_faction),
      zone_of(73_741, spawn.dominion_faction),
      zone_of(73_743, spawn.exile_faction),
      zone_of(73_743, spawn.dominion_faction),
      zone_of(73_745, spawn.exile_faction),
      zone_of(73_745, spawn.dominion_faction),
    ]
    == [5967, 5967, 5969, 5969, 5968, 5968, 5998, 5999]
    as "WorldLocation2 51615, 51617, 51616 and the Exile's 51658 and the Dominion's 51657: the Combat, Housing, Mission and Cryo projectors' zones"
}

pub fn a_server_proxy_row_that_cannot_be_planned_stops_the_load_naming_each_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "insert into server_proxy (spell4_base_id, phase, spell4_id, source, reason) values (99999, 0, 42148, 'server_choice', 'a base with no plan'), (26468, 2, 42148, 'server_choice', 'a go Pulse Blast does not have'), (26468, 0, 99999, 'server_choice', 'a spell the tables lack')",
  )
  let #(loaded, _key) = content_support.load(database:)
  let assert Error(content.Refused(refusals:)) = loaded
    as "a row that names no plan, no go or no spell stops the start (the design, tests 10 to 12)"
  assert list.map(refusals, fn(refused) { #(refused.table, refused.row) })
    == [
      #("server_proxy", refusal.RowName("26468 0 99999")),
      #("server_proxy", refusal.RowName("26468 2 42148")),
      #("server_proxy", refusal.RowName("99999 0 42148")),
    ]
    as "each bad row is named by its key, in the table's key order, and the seed row is not"
  // A held tier plays its own plan, so the seed row (Pulse Blast 26468, go 1, spell 42148) must
  // hold in the plan of every tier. Each case edits the rows of tier 2 (Spell4 53409, whose
  // Proxy 126783 starts the damage spell 56145) and the load of the proxies names the row and
  // the tier.
  list.each(
    [
      #(
        "a tier whose plan has no go 1: its second SpellPhase row (10284) belongs to no spell",
        [
          #("SpellPhase", 10_284, [#("spell4IdOwner", planted_table.Integer(0))]),
        ],
        "is not a go",
      ),
      #(
        "a tier whose root starts its damage spell after a delay, so no Proxy starts a child at once for the server's Proxy to go with",
        [
          #("Spell4Effects", 126_783, [#("delayTime", planted_table.Integer(1))]),
        ],
        "starts no spell at once",
      ),
    ],
    fn(case_) {
      let #(why, edits, sentence) = case_
      let refused =
        fixture_tables.changes(edits:, body: fn(tables) {
          server_proxy.select(
            rows: [spell_tables.volatility_row()],
            tables:,
            plans: spell_plan.plans(tables:),
          )
        })
      let assert Error([refused]) = refused as why
      assert refused.row == refusal.RowName("26468 1 42148") as why
      assert string.contains(refused.rule, "tier 2")
        && string.contains(refused.rule, "53409")
        && string.contains(refused.rule, sentence)
        as { why <> ": " <> refused.rule }
    },
  )
}
