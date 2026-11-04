//// The content tables: data the server owns, kept in Postgres and loaded once at
//// start into persistent terms. Behaviour stays in code (rules, the client's
//// formulas, message layouts, client facts); `spawn` is the first content table
//// (genesis_prime/content/spawn) and every later one follows the same pattern.
////
//// - **Where a row comes from.** Every content table has `source` (the
////   `content_source` type: `world_database`, `retail_record`, `server_choice`,
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
//// main ─▶ load_tables ─▶ content.load(tables, migrations, pool, ask settings, key)
////           starts a pool of its own: one connection, not the tree's, ended after the load
////           waits for the database as readiness does: attempts of attempt_ms, pause_ms
////             between them, one warning after within_ms, then asks again
////           compares the migrations the database recorded with the files (genesis_prime/migration)
////           for each table, in order (a table others refer to first):
////             its one query ─▶ rows ─▶ its pure check ─▶ typed records and refusals
////           every refusal of every table logged; any ─▶ Error(Refused(all of them))
////           else each table's terms put under key: Ok(Nil)
////        ─▶ Ok: starts the tree (pool, store, ..., listeners) ─▶ readiness ask ─▶ ready line
////        ─▶ Error: main stops with the sentences; no tree, no listener, status 1
//// ```
////
//// - **Why before the tree.** A map reads its world's term when it starts, and
////   the first player can arrive when the listeners open, so the term must exist
////   by then. The tree's own pool starts inside the tree, so the load has a pool
////   of its own and the tree starts clean after it.
//// - **The wait is readiness's** (genesis_prime/readiness): attempts of 2 s with
////   250 ms between them, one warning after 30 s, and then the same again, so a
////   database that comes up late works and one that never does leaves the server
////   not started, with the warning. The migration comparison is readiness's too
////   (`migration.check`): a database that ran other migrations stops the start with
////   the difference, as the ready line's does.
//// - **Every refusal is collected.** One bad row shows its neighbours: all are
////   logged, then the start stops, as a client table that fails to load does.
//// - **The terms** are put once, one for each table and world, under `key`
////   (genesis_prime/content/term).
////
//// What happens at each failure point of the load:
////
//// | Point | What happens |
//// |---|---|
//// | the database answers late | the load waits and warns once after 30 s, and asks again; the tree starts after it |
//// | the migrations differ | the start stops with the difference |
//// | a row is refused | the start stops with the reason |
//// | several rows are refused | every refusal is logged, then the start stops |
//// | a query fails | the start stops with the database's reason |

import genesis_prime/content/refusal.{type Refusal}
import genesis_prime/content/term.{type Key}
import genesis_prime/migration.{type Migration}
import genesis_prime/readiness
import genesis_prime/table/loader/store as table_store
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
/// configuration of the load's own pool.
pub fn load(
  tables _tables: table_store.Tables,
  migrations _migrations: List(Migration),
  pool _pool: pog.Config,
  ask _ask: readiness.Settings,
  key _key: Key,
) -> Result(Nil, LoadError) {
  panic as "the content load is built after the shape's review"
}

/// A sentence for each way the load can fail, for the message the start stops
/// with: the migrations' difference, the query's reason, or one line for each
/// refused row.
pub fn describe(error _error: LoadError) -> String {
  panic as "the content load is built after the shape's review"
}
