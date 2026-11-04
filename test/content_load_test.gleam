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
//// The waits are the load's own settings, shortened here, so no test waits 30 s.

import character_tables
import database_support
import genesis_prime
import genesis_prime/content
import genesis_prime/content/creature_kind as content_creature_kind
import genesis_prime/content/refusal.{Refusal}
import genesis_prime/content/spawn as content_spawn
import genesis_prime/migration
import genesis_prime/readiness
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/creature_kind
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/string
import log_capture
import mailbox_support
import owned_key
import owned_test
import pog
import unitest

/// How the load asks in these tests: attempts of 500 ms, 50 ms between them, and
/// the warning after a second.
fn asking() -> readiness.Settings {
  readiness.Settings(within_ms: 1000, attempt_ms: 500, pause_ms: 50)
}

/// The load of the planted tables and the repository's migrations from the
/// database, under a key of its own.
fn load(
  database database: String,
) -> #(Result(Nil, content.LoadError), table_store.Key) {
  load_asking(database:, ask: asking(), probe: content.pool_probe)
}

/// The load with the way it asks the pool chosen by the test.
fn load_asking(
  database database: String,
  ask ask: readiness.Settings,
  probe probe: fn(pog.Connection) -> readiness.Probe,
) -> #(Result(Nil, content.LoadError), table_store.Key) {
  let key = owned_key.new_fixture_key()
  let pool =
    database_support.config(
      database_support.settings(),
      database:,
      pool_name: process.new_name("content_load_pool"),
      pool_size: 1,
    )
  #(
    content.load(
      tables: character_tables.content_tables(),
      migrations: genesis_prime.load_migrations(),
      pool:,
      ask:,
      probe:,
      key:,
    ),
    key,
  )
}

/// Runs `sql` on the database as the test's administrator.
fn change(database: String, sql: String) -> Nil {
  let assert Ok(_) =
    database_support.psql(
      with: database_support.settings(),
      database:,
      arguments: ["-c", sql],
    )
    as "the change to the database ran"
  Nil
}

/// A spawn row of a creature the client has no row for, as the world database's
/// row `row`.
fn bad_row(row row: Int, creature creature: Int) -> String {
  "insert into spawn (source, source_row, entity_type, creature_id, world_id, area_id, x, y, z, rotation_x, rotation_y, rotation_z, display_info_id, outfit_info_id, faction_id, base_faction_id, quest_checklist_index, active_prop_id, world_socket_id) values ('world_database', "
  <> int.to_string(row)
  <> ", 0, "
  <> int.to_string(creature)
  <> ", 3460, 0, 0, 0, 0, 0, 0, 0, 26565, 0, 1441, 1441, 0, 0, 0)"
}

pub fn the_load_puts_the_migrated_databases_spawns_in_the_worlds_term_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let #(loaded, key) = load(database:)
  assert loaded == Ok(Nil) as "a migrated database loads"
  let world = content_spawn.world(key:, world_id: 3460)
  assert dict.size(world.by_id) == 27
    as "migration 0008's 27 Virtual Defense Daguns, the only spawns the template holds"
  assert dict.size(content_spawn.world(key:, world_id: 22).by_id) == 0
    as "a World row with no spawn that starts has an empty term"
}

pub fn the_load_puts_the_kinds_in_a_term_the_default_row_is_the_60_second_choice_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  change(
    database,
    "insert into creature_kind (creature_id, respawn_ms, attack_spell4_id, attack_interval_ms, source, reason) values (73464, 5000, 5649, 1500, 'server_choice', 'a short respawn for the training Beast')",
  )
  let #(loaded, key) = load(database:)
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
  change(database, "delete from creature_kind where creature_id = 0")
  let #(loaded, _key) = load(database:)
  let assert Error(content.Refused(refusals:)) = loaded
    as "no default row stops the start"
  assert list.map(refusals, fn(refused) { #(refused.table, refused.row) })
    == [#("creature_kind", refusal.RowId(0))]
}

pub fn a_kind_row_for_a_creature_the_client_does_not_hold_stops_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  change(
    database,
    "insert into creature_kind (creature_id, respawn_ms, attack_spell4_id, attack_interval_ms, source, reason) values (200001, 5000, 5649, 1500, 'server_choice', 'a creature the client does not hold')",
  )
  let #(loaded, _key) = load(database:)
  let assert Error(content.Refused(refusals:)) = loaded
    as "a refused kind row stops the start"
  assert list.map(refusals, fn(refused) { #(refused.table, refused.row) })
    == [#("creature_kind", refusal.RowId(200_001))]
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
    load_asking(
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
  assert process.receive(away, within: 0) == Error(Nil)
    as "it was told five times that the database was away"
  assert dict.size(content_spawn.world(key:, world_id: 3460).by_id) == 27
}

pub fn a_database_whose_migrations_differ_stops_the_load_with_the_difference_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  change(database, "delete from schema_migration where name = '0008_spawn'")
  let #(loaded, _key) = load(database:)
  assert loaded
    == Error(content.MigrationsDiffer(migration.NotApplied(name: "0008_spawn")))
    as "the database has not run the migration 0008_spawn"
}

pub fn two_refused_rows_are_both_logged_with_table_id_and_rule_and_stop_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.tag("serial")
  let database = database_support.new_database(on: database_support.shared())
  change(database, bad_row(row: 1, creature: 200_001))
  change(database, bad_row(row: 2, creature: 200_002))
  let lines = process.new_subject()
  let capture = log_capture.start_all(into: lines)
  let #(loaded, _key) = load(database:)
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

pub fn a_query_that_fails_stops_the_load_with_the_databases_reason_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  change(database, "alter table spawn rename column x to east")
  let #(loaded, _key) = load(database:)
  let assert Error(content.QueryFailed(table: "spawn", reason:)) = loaded
    as "a failed query stops the load"
  assert string.contains(reason, "undefined_column")
    as { "the database's reason is named: " <> reason }
}

pub fn a_missing_and_an_unknown_game_number_stop_the_load_each_named_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  change(database, "delete from game_number where name = 'leash_range'")
  change(
    database,
    "insert into game_number (name, value, unit, source, reason) values ('evade_range', 30, 'units', 'server_choice', 'a number the server has no use for')",
  )
  let #(loaded, _key) = load(database:)
  let assert Error(content.Refused(refusals:)) = loaded
    as "a game number the server does not know, or one it reads and does not find, stops the start (the design of step F, section 2)"
  assert list.map(refusals, fn(refused) { #(refused.table, refused.row) })
    == [
      #("game_number", refusal.RowName("evade_range")),
      #("game_number", refusal.RowName("leash_range")),
    ]
    as "each refusal names the table and the number by its name"
}
