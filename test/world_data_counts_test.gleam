//// The spawns that start in each world from Jim's whole world database, loaded
//// through the content load with the client's real tables. Expected values come
//// from these places.
//// - The decode of issue 375 (its facts `world_data.creature_disposition` and
////   `world_data.spawn_checks`), re-run by a scratch Python reimplementation that
////   gave the same 39,096: world 22 starts 10,920 spawns, 51 12,788, 426 362, 870
////   677, 990 725, 1061 12,726, 1387 836 and 3460 62, and the other worlds none.
//// - Migration 0008: World 3460 also holds the 27 Virtual Defense Daguns, server
////   choices, which start (Hostile to Dominion), so 3460 has 62 + 27.
//// The test needs the client's tables and the world database (`GENESIS_WORLD_DATA`),
//// neither of which CI has (`GENESIS_NO_CLIENT=1`), so it is skipped there; it
//// imports the whole file into a database of its own, which takes a few seconds.

import client_tables
import content_support
import database_support
import envoy
import genesis_prime
import genesis_prime/content
import genesis_prime/content/spawn as content_spawn
import genesis_prime/import_world_data
import genesis_prime/readiness
import genesis_prime/step/runtime
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/list
import owned_key
import owned_test
import unitest

/// How the load asks: the database is up, so one attempt answers.
fn asking() -> readiness.Settings {
  readiness.Settings(within_ms: 5000, attempt_ms: 2000, pause_ms: 100)
}

pub fn the_whole_world_database_starts_the_decoded_number_of_spawns_in_each_world_test() -> Nil {
  use <- owned_test.run(300_000)
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
  let tables = client_tables.every_table()
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
  assert list.map(
      [22, 51, 426, 870, 990, 1061, 1387, 3460, 1535, 3022],
      fn(world_id) { dict.size(content_spawn.world(key:, world_id:).by_id) },
    )
    == [10_920, 12_788, 362, 677, 725, 12_726, 836, 89, 0, 0]
    as {
      "the spawns that start in each world; the load took "
      <> int.to_string(took)
      <> " ms"
    }
  Nil
}
