//// The content tables: data the server owns, kept in Postgres and loaded once at
//// start into persistent terms. Behaviour stays in code (rules, the client's
//// formulas, message layouts, client facts); `spawn` is the first content table
//// (genesis_prime/content/spawn) and every later one follows the same pattern.
////
//// - **Where a row comes from.** Every content table has `source` (a row of the
////   `content_source` table: `world_database`, `retail_record`, `server_choice`,
////   `game_master`), `source_row` (the row's id in its source file) and `reason`,
////   and the checks that a world-database row names its source row and any other
////   row states its reason (migration 0008).
//// - **How rows get in.** A world-database row comes through the import tool
////   (`genesis_prime/import_world_data`), which has one importer for each file
////   and records each import in `content_import`; a server choice is seeded by a
////   migration. CI seeds planted rows the same ways.
//// - **One load at start, before the tree.** `load` runs in `main`, once the
////   client's tables are loaded and before the supervision tree starts, so the
////   listeners open after it.
//// - **Each table's pure check** turns a row into a typed record or a refusal
////   naming the table, the id and the rule; the client's tables are the
////   reference. Nothing queries a content table during play.
////
//// ```
//// main ─▶ load_content ─▶ content.load(tables, migrations, pool, ask settings, key)
////           tables: the server's and the content-only ones, loaded for this load
////           starts a pool of its own: one connection, not the tree's
////           waits for the database as readiness does (readiness.await with no tree):
////             attempts of attempt_ms, pause_ms between them, a warning each within_ms
////           compares the migrations the database recorded with the files (genesis_prime/migration)
////           for each table, in order:
////             its one query ─▶ rows ─▶ its pure check ─▶ typed records and refusals
////           every refusal of every table logged; any ─▶ Error(Refused(all of them))
////           else each table's terms put under key; the coverage logged
////           ends its pool
////        ─▶ Ok: starts the tree (pool, store, ..., listeners) ─▶ readiness ask ─▶ ready line
////        ─▶ Error: main stops with the sentences; no tree, no listener, status 1
//// ```
////
//// - **Why before the tree.** A map reads its world's term when it starts, and
////   the first player can arrive when the listeners open, so the term must exist
////   by then. The tree's own pool starts inside the tree, so the load has a pool
////   of its own and the tree starts clean after it.
//// - **The wait is readiness's** (genesis_prime/readiness), with no tree to watch:
////   attempts of 2 s with 250 ms between them, a warning each 30 s, and then the
////   same again, so a database that comes up late works. With the database down
////   at start nothing listens until it answers, where the tree used to start first
////   and answer `Unavailable` meanwhile. The migration comparison is readiness's
////   too (`migration.check`): a database that ran other migrations stops the
////   start with the difference, as the ready line's does.
//// - **Every refusal is collected.** One bad row shows its neighbours: all are
////   logged, then the start stops, as a client table that fails to load does.
//// - **The terms** are put once, one for each table and world, under `key`
////   (genesis_prime/content/term); a world of the client's World table with no
////   spawn gets an empty one, so a missing term is a bug and crashes its reader.
//// - **Content-only tables.** The faction, outfit and world tables the selection
////   reads load with the creature tables for the load alone
////   (`server_table.load_for_content`), and the caller unloads them after it: they
////   are not in the server's tables, whose digest a recording's header holds.
////
//// What happens at each failure point of the load:
////
//// | Point | What happens |
//// |---|---|
//// | the database answers late | the load waits and warns each 30 s, and asks again; the tree starts after it |
//// | the migrations differ | the start stops with the difference |
//// | a row is refused | the start stops with the reason |
//// | several rows are refused | every refusal is logged, then the start stops |
//// | a query fails | the start stops with the database's reason |

import genesis_prime/content/refusal.{type Refusal}
import genesis_prime/content/spawn as content_spawn
import genesis_prime/migration.{type Migration}
import genesis_prime/readiness
import genesis_prime/step
import genesis_prime/step/runtime
import genesis_prime/store/worker
import genesis_prime/table/loader/store.{type Key}
import genesis_prime/world_map/spawn
import genesis_prime/world_map/spawn_id
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import pog

/// Why the load did not finish.
pub type LoadError {
  /// The database recorded other migrations than the files.
  MigrationsDiffer(refusal: migration.Refusal)
  /// A query failed, for the reason the database gave.
  QueryFailed(table: String, reason: String)
  /// These rows are refused, all of them from every table.
  Refused(refusals: List(Refusal))
}

/// Loads every content table into persistent terms under `key`, as the
/// sequence above gives: waits for the database as `ask` says, compares the
/// migrations with `migrations`, checks every row against the client's `tables`,
/// logs every refusal and puts the terms only when there is none. `pool` is the
/// configuration of the load's own pool. `tables` stay loaded: the caller unloads
/// them, or keeps them for another load.
pub fn load(
  tables tables: store.Tables,
  migrations migrations: List(Migration),
  pool pool: pog.Config,
  ask ask: readiness.Settings,
  key key: Key,
) -> Result(Nil, LoadError) {
  let assert Ok(started) = pog.start(pool)
    as "the content load's database pool started"
  process.unlink(started.pid)
  let loaded = read(tables:, migrations:, db: started.data, ask:, key:)
  process.send_abnormal_exit(started.pid, runtime.Shutdown)
  loaded
}

/// The load itself, on the pool: the wait, the migrations, the query, the
/// selection, the log and the terms.
fn read(
  tables tables: store.Tables,
  migrations migrations: List(Migration),
  db db: pog.Connection,
  ask ask: readiness.Settings,
  key key: Key,
) -> Result(Nil, LoadError) {
  use _ready <- result.try(
    wait(db:, migrations:, ask:) |> result.map_error(MigrationsDiffer),
  )
  use rows <- result.try(
    content_spawn.rows(db)
    |> result.map_error(fn(error) {
      QueryFailed(
        table: content_spawn.table,
        reason: worker.describe_query_error(error),
      )
    }),
  )
  let selection = spawn.select(rows:, tables:)
  case selection.refusals {
    [] -> {
      list.each(selection.coverage, fn(coverage) {
        runtime.log(
          step.LogInfo,
          spawn.describe_coverage(coverage:),
          step.no_one,
        )
      })
      log_levels_out_of_range(selection)
      content_spawn.put(key:, selection:)
      Ok(Nil)
    }
    refusals -> {
      list.each(refusals, fn(refused) {
        runtime.log(step.LogError, refusal.describe(refused), step.no_one)
      })
      Error(Refused(refusals:))
    }
  }
}

/// The info line of the spawns whose level lies outside their creature's range.
fn log_levels_out_of_range(selection: spawn.Selection) -> Nil {
  case selection.out_of_range_levels {
    [] -> Nil
    levels ->
      runtime.log(
        step.LogInfo,
        "spawns started with a level outside their creature's range: "
          <> string.join(
          list.map(levels, fn(id) {
            let spawn_id.SpawnId(number) = id
            int.to_string(number)
          }),
          ", ",
        ),
        step.no_one,
      )
  }
}

/// Asks the database through the load's pool until it answers, as readiness
/// does at start, warning each window that passes with no answer.
fn wait(
  db db: pog.Connection,
  migrations migrations: List(Migration),
  ask ask: readiness.Settings,
) -> Result(Nil, migration.Refusal) {
  case
    readiness.await(
      probe: fn(reply) { worker.probe_pool(pool: db, reply:) },
      tree: None,
      settings: ask,
      files: migrations,
    )
  {
    readiness.Ready -> Ok(Nil)
    readiness.MigrationsRefused(refusal:) -> Error(refusal)
    readiness.DatabaseUnreachable -> {
      runtime.log(step.LogWarning, "the database is unreachable", step.no_one)
      wait(db:, migrations:, ask:)
    }
    readiness.TreeEnded(..) ->
      panic as "the content load watches no tree, so none ended"
  }
}

/// A sentence for each way the load can fail, for the message the start stops
/// with: the migrations' difference, the query's reason, or one line for each
/// refused row.
pub fn describe(error error: LoadError) -> String {
  case error {
    MigrationsDiffer(refusal:) -> migration.describe(refusal)
    QueryFailed(table:, reason:) ->
      "the query of the table " <> table <> " failed: " <> reason
    Refused(refusals:) ->
      string.join(list.map(refusals, refusal.describe), "\n")
  }
}
