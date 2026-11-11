//// Imports Jim's world database into the content tables (genesis_prime/content):
//// one importer for each file, all sharing one reader and one writer. The spawn
//// importer reads `spawn.tsv`.
////
//// `gleam run -m genesis_prime/import_world_data`
////
//// The folder is `$GENESIS_WORLD_DATA` (a line of `~/.genesis-prime/env.sh`, never
//// committed); the database is the one the server uses, from PGHOST, PGPORT,
//// PGUSER, PGPASSWORD and PGDATABASE. It refuses to run with the variable unset.
////
//// ```
//// file ─▶ reader: the exact header, the field count of each line, each field's
////                 type, finite numbers, ids that repeat, stat arrays of unequal
////                 length; a refusal names the line, the column and the value,
////                 and nothing is written
////      ─▶ writer, one transaction:
////           batches of 5,000 rows through unnest, upserted on `source_row`
////             (a changed row keeps its id; a row that is the same is left alone)
////           each row's stats made the file's
////           the world-database rows no longer in the file deleted, every other
////             source left alone
////           the file's SHA-256 and row count recorded in `content_import`
//// ```
////
//// - **Every range rule is the schema's** (migration 0008): the reader parses and
////   never judges a value, so a unit type of 37 or a faction of 16384 is written
////   to the database, which refuses it. A refusal is reported under its
////   constraint's name with the failing `source_row`, read from the error's
////   detail, and nothing is written (the transaction rolls back).
//// - **The transaction's deadline is sized for the file** (`transaction_deadline_ms`):
////   the pool drops a connection held past its deadline, and the default of 5,000
////   ms is shorter than the whole world database's transaction.
//// - **It is idempotent.** A second run of the same file changes nothing, and
////   prints the counts inserted, changed, removed and unchanged.

import argv
import envoy
import genesis_prime/dev_database
import genesis_prime/digest
import genesis_prime/import_world_data/sql
import gleam/bit_array
import gleam/bool
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import pog
import simplifile

/// The columns of `spawn.tsv`, in order.
const spawn_columns = [
  "id", "entity_type", "creature_id", "world_id", "area_id", "x", "y", "z",
  "rotation_x", "rotation_y", "rotation_z", "display_info", "outfit_info",
  "faction1", "faction2", "quest_checklist_index", "active_prop_id",
  "world_socket_id", "stat_ids", "stat_values",
]

/// How many rows one statement writes.
const batch_size = 5000

/// One row of `spawn.tsv`, typed.
type SpawnRecord {
  SpawnRecord(
    source_row: Int,
    entity_type: Int,
    creature_id: Int,
    world_id: Int,
    area_id: Int,
    x: Float,
    y: Float,
    z: Float,
    rotation_x: Float,
    rotation_y: Float,
    rotation_z: Float,
    display_info_id: Int,
    outfit_info_id: Int,
    faction_id: Int,
    base_faction_id: Int,
    active_prop_id: Int,
    world_socket_id: Int,
    stats: List(#(Int, Float)),
  )
}

/// Why the reader refuses a file: the line (the header is line 1), the column and
/// the value where there is one.
pub type Refusal {
  WrongHeader(found: String)
  WrongFieldCount(line: Int, found: Int)
  BadField(line: Int, column: String, value: String, wanted: String)
  RepeatedId(line: Int, id: Int)
  UnequalStats(line: Int, ids: Int, values: Int)
}

/// What an import did.
pub type Counts {
  Counts(
    inserted: Int,
    changed: Int,
    unchanged: Int,
    removed: Int,
    stats_written: Int,
    stats_deleted: Int,
  )
}

/// Why an import did not finish.
pub type Failure {
  /// `GENESIS_WORLD_DATA` is not set.
  NoWorldData
  /// The file could not be read.
  Unreadable(file: String, reason: String)
  /// The reader refused the file; nothing was written.
  FileRefused(refusal: Refusal)
  /// The schema refused a row: the constraint's name, and the row's id in the
  /// file when the error's detail names it. Nothing was written.
  RowRefused(constraint: String, source_row: Option(Int))
  /// The database failed in another way.
  Database(failure: dev_database.Failure)
}

pub fn main() -> Nil {
  dev_database.finish(result: run(), describe:)
}

fn run() -> Result(String, Failure) {
  let _arguments = argv.load().arguments
  use folder <- result.try(
    envoy.get("GENESIS_WORLD_DATA") |> result.replace_error(NoWorldData),
  )
  use db <- result.try(dev_database.connect() |> result.map_error(Database))
  use counts <- result.map(import_spawns(db:, folder:))
  describe_counts(file: "spawn.tsv", counts:)
}

/// The spawn importer: reads `spawn.tsv` in the folder and imports it on the
/// database, in one transaction, or gives why it did not.
pub fn import_spawns(
  db db: pog.Connection,
  folder folder: String,
) -> Result(Counts, Failure) {
  let file = folder <> "/spawn.tsv"
  use bytes <- result.try(
    simplifile.read_bits(file)
    |> result.map_error(fn(error) {
      Unreadable(file: "spawn.tsv", reason: simplifile.describe_error(error))
    }),
  )
  use text <- result.try(
    bit_array.to_string(bytes)
    |> result.replace_error(Unreadable(
      file: "spawn.tsv",
      reason: "it is not UTF-8 text",
    )),
  )
  use records <- result.try(
    parse_spawns(text:) |> result.map_error(FileRefused),
  )
  write_spawns(db:, records:, sha256: digest.sha256(bytes))
}

/// Parses the text of `spawn.tsv`: the header, then one record for each line.
fn parse_spawns(text text: String) -> Result(List(SpawnRecord), Refusal) {
  case string.split(text, "\n") {
    [header, ..lines] ->
      case string.split(header, "\t") == spawn_columns {
        False -> Error(WrongHeader(found: header))
        True -> parse_lines(lines:, line: 2, seen: dict.new(), parsed: [])
      }
    [] -> Error(WrongHeader(found: ""))
  }
}

fn parse_lines(
  lines lines: List(String),
  line line: Int,
  seen seen: dict.Dict(Int, Nil),
  parsed parsed: List(SpawnRecord),
) -> Result(List(SpawnRecord), Refusal) {
  case lines {
    [] | [""] -> Ok(list.reverse(parsed))
    [text, ..rest] -> {
      use record <- result.try(parse_line(text:, line:))
      case dict.has_key(seen, record.source_row) {
        True -> Error(RepeatedId(line:, id: record.source_row))
        False ->
          parse_lines(
            lines: rest,
            line: line + 1,
            seen: dict.insert(seen, record.source_row, Nil),
            parsed: [record, ..parsed],
          )
      }
    }
  }
}

fn parse_line(
  text text: String,
  line line: Int,
) -> Result(SpawnRecord, Refusal) {
  case string.split(text, "\t") {
    [
      id,
      entity_type,
      creature_id,
      world_id,
      area_id,
      x,
      y,
      z,
      rotation_x,
      rotation_y,
      rotation_z,
      display_info,
      outfit_info,
      faction1,
      faction2,
      _quest_checklist_index,
      active_prop_id,
      world_socket_id,
      stat_ids,
      stat_values,
    ] -> {
      let integer = fn(column, value) { whole(line:, column:, value:) }
      let real = fn(column, value) { finite(line:, column:, value:) }
      use source_row <- result.try(integer("id", id))
      use entity_type <- result.try(integer("entity_type", entity_type))
      use creature_id <- result.try(integer("creature_id", creature_id))
      use world_id <- result.try(integer("world_id", world_id))
      use area_id <- result.try(integer("area_id", area_id))
      use x <- result.try(real("x", x))
      use y <- result.try(real("y", y))
      use z <- result.try(real("z", z))
      use rotation_x <- result.try(real("rotation_x", rotation_x))
      use rotation_y <- result.try(real("rotation_y", rotation_y))
      use rotation_z <- result.try(real("rotation_z", rotation_z))
      use display_info_id <- result.try(integer("display_info", display_info))
      use outfit_info_id <- result.try(integer("outfit_info", outfit_info))
      use faction_id <- result.try(integer("faction1", faction1))
      use base_faction_id <- result.try(integer("faction2", faction2))
      use active_prop_id <- result.try(integer("active_prop_id", active_prop_id))
      use world_socket_id <- result.try(integer(
        "world_socket_id",
        world_socket_id,
      ))
      use ids <- result.try(array(line:, column: "stat_ids", value: stat_ids))
      use values <- result.try(array(
        line:,
        column: "stat_values",
        value: stat_values,
      ))
      use stats <- result.try(stats_of(line:, ids:, values:))
      Ok(SpawnRecord(
        source_row:,
        entity_type:,
        creature_id:,
        world_id:,
        area_id:,
        x:,
        y:,
        z:,
        rotation_x:,
        rotation_y:,
        rotation_z:,
        display_info_id:,
        outfit_info_id:,
        faction_id:,
        base_faction_id:,
        active_prop_id:,
        world_socket_id:,
        stats:,
      ))
    }
    fields -> Error(WrongFieldCount(line:, found: list.length(fields)))
  }
}

fn whole(
  line line: Int,
  column column: String,
  value value: String,
) -> Result(Int, Refusal) {
  int.parse(value)
  |> result.replace_error(BadField(
    line:,
    column:,
    value:,
    wanted: "a whole number",
  ))
}

/// A number that is not NaN or infinite: the reader refuses what does not parse
/// as a finite float.
fn finite(
  line line: Int,
  column column: String,
  value value: String,
) -> Result(Float, Refusal) {
  number(value)
  |> result.replace_error(BadField(
    line:,
    column:,
    value:,
    wanted: "a finite number",
  ))
}

/// A number as Postgres writes it: a whole number (`0`), a decimal (`-1.5`) or one
/// with an exponent (`3.43e+06`, `1e-05`); Gleam's float parser wants a point
/// before an exponent and refuses a whole number.
pub fn number(text: String) -> Result(Float, Nil) {
  case int.parse(text) {
    Ok(whole) -> Ok(int.to_float(whole))
    Error(Nil) ->
      case string.split_once(string.lowercase(text), "e") {
        Ok(#(mantissa, exponent)) ->
          case string.contains(mantissa, ".") {
            True -> float.parse(mantissa <> "e" <> exponent)
            False -> float.parse(mantissa <> ".0e" <> exponent)
          }
        Error(Nil) -> float.parse(text)
      }
  }
}

/// The elements of an array written as `{a,b,c}`, as text.
fn array(
  line line: Int,
  column column: String,
  value value: String,
) -> Result(List(String), Refusal) {
  use <- bool.guard(
    when: !{ string.starts_with(value, "{") && string.ends_with(value, "}") },
    return: Error(BadField(line:, column:, value:, wanted: "an array in braces")),
  )
  case string.slice(value, 1, string.length(value) - 2) {
    "" -> Ok([])
    inside -> Ok(string.split(inside, ","))
  }
}

fn stats_of(
  line line: Int,
  ids ids: List(String),
  values values: List(String),
) -> Result(List(#(Int, Float)), Refusal) {
  use <- bool.guard(
    when: list.length(ids) != list.length(values),
    return: Error(UnequalStats(
      line:,
      ids: list.length(ids),
      values: list.length(values),
    )),
  )
  list.zip(ids, values)
  |> list.try_map(fn(pair) {
    use stat <- result.try(whole(line:, column: "stat_ids", value: pair.0))
    use value <- result.map(finite(line:, column: "stat_values", value: pair.1))
    #(stat, value)
  })
}

/// How long the import's transaction may keep its connection for this many rows:
/// each statement it runs is allowed pog's own query timeout, 5,000 ms. Each
/// batch runs four statements (the spawns, the savepoint, the stats, the
/// release of the savepoint), and two more end the import (the delete of the
/// removed rows and the record of the import). The transaction grows with the
/// file, so a deadline that did not would end it under load.
pub fn transaction_deadline_ms(rows rows: Int) -> Int {
  let batches = { rows + batch_size - 1 } / batch_size
  { batches * 4 + 2 } * dev_database.default_timeout_ms
}

/// Writes the records in one transaction.
fn write_spawns(
  db db: pog.Connection,
  records records: List(SpawnRecord),
  sha256 sha256: String,
) -> Result(Counts, Failure) {
  dev_database.transaction(
    db:,
    deadline_ms: transaction_deadline_ms(rows: list.length(records)),
    work: fn(tx) {
      use batches <- result.try(
        list.sized_chunk(records, batch_size)
        |> list.try_fold(Counts(0, 0, 0, 0, 0, 0), fn(counts, batch) {
          write_batch(tx:, batch:, counts:)
        }),
      )
      let ids = list.map(records, fn(record) { record.source_row })
      use removed <- result.try(
        sql.delete_removed_spawns(tx, ids) |> result.map_error(database_failure),
      )
      use _recorded <- result.map(
        sql.record_import(tx, "spawn.tsv", sha256, list.length(records))
        |> result.map_error(database_failure),
      )
      Counts(
        ..batches,
        removed: first_of(removed.rows, fn(row) { row.removed }),
        unchanged: list.length(records) - batches.inserted - batches.changed,
      )
    },
  )
  |> result.map_error(fn(error) {
    case error {
      dev_database.Undone(failure) -> failure
      dev_database.NoConnection -> Database(dev_database.DatabaseDown)
      dev_database.Failed(error) -> database_failure(error)
      dev_database.NotAPool ->
        Database(dev_database.NotChanged(
          "the import needs a pool of connections, not one connection",
        ))
    }
  })
}

/// A failed query that is not a refused row.
fn database_failure(error: pog.QueryError) -> Failure {
  Database(dev_database.failure_of(error:))
}

/// A failed write of spawn rows: a refused row is named by its constraint and its
/// row in the file, read from the detail's `source_row`.
fn spawn_failure(error: pog.QueryError) -> Failure {
  case error {
    pog.ConstraintViolated(constraint:, detail:, ..) ->
      RowRefused(constraint:, source_row: source_row_of(detail))
    pog.PostgresqlError(..)
    | pog.UnexpectedArgumentCount(..)
    | pog.UnexpectedArgumentType(..)
    | pog.UnexpectedResultType(..)
    | pog.QueryTimeout
    | pog.ConnectionUnavailable -> database_failure(error)
  }
}

fn write_batch(
  tx tx: pog.Connection,
  batch batch: List(SpawnRecord),
  counts counts: Counts,
) -> Result(Counts, Failure) {
  let column = fn(read: fn(SpawnRecord) -> a) { list.map(batch, read) }
  use written <- result.try(
    sql.upsert_spawns(
      tx,
      column(fn(r) { r.source_row }),
      column(fn(r) { r.entity_type }),
      column(fn(r) { r.creature_id }),
      column(fn(r) { r.world_id }),
      column(fn(r) { r.area_id }),
      column(fn(r) { r.x }),
      column(fn(r) { r.y }),
      column(fn(r) { r.z }),
      column(fn(r) { r.rotation_x }),
      column(fn(r) { r.rotation_y }),
      column(fn(r) { r.rotation_z }),
      column(fn(r) { r.display_info_id }),
      column(fn(r) { r.outfit_info_id }),
      column(fn(r) { r.faction_id }),
      column(fn(r) { r.base_faction_id }),
      column(fn(r) { r.active_prop_id }),
      column(fn(r) { r.world_socket_id }),
    )
    |> result.map_error(spawn_failure),
  )
  let triples =
    list.flat_map(batch, fn(record) {
      list.map(record.stats, fn(stat) { #(record.source_row, stat.0, stat.1) })
    })
  use stats <- result.map(write_stats(tx:, triples:, batch:))
  Counts(
    ..counts,
    inserted: counts.inserted + first_of(written.rows, fn(row) { row.inserted }),
    changed: counts.changed + first_of(written.rows, fn(row) { row.changed }),
    stats_written: counts.stats_written
      + first_of(stats.rows, fn(row) { row.written }),
    stats_deleted: counts.stats_deleted
      + first_of(stats.rows, fn(row) { row.deleted }),
  )
}

/// Writes the stats of a batch behind a savepoint: a stat the schema refuses rolls
/// back to it, which leaves the transaction able to look up the refused stat's
/// spawn by its id and name its row in the file. (pog's own nested transaction
/// begins no savepoint and would roll the whole import back.)
fn write_stats(
  tx tx: pog.Connection,
  triples triples: List(#(Int, Int, Float)),
  batch batch: List(SpawnRecord),
) -> Result(pog.Returned(sql.UpsertSpawnStatsRow), Failure) {
  use _saved <- result.try(execute(tx, "savepoint stats"))
  let attempt =
    sql.upsert_spawn_stats(
      tx,
      list.map(triples, fn(triple) { triple.0 }),
      list.map(triples, fn(triple) { triple.1 }),
      list.map(triples, fn(triple) { triple.2 }),
      list.map(batch, fn(record) { record.source_row }),
    )
  case attempt {
    Ok(stats) -> {
      use _released <- result.map(execute(tx, "release savepoint stats"))
      stats
    }
    Error(pog.ConstraintViolated(constraint:, detail:, ..)) -> {
      use _rolled_back <- result.try(execute(tx, "rollback to savepoint stats"))
      use source_row <- result.try(row_of_stat(tx:, detail:))
      Error(RowRefused(constraint:, source_row:))
    }
    Error(error) -> Error(database_failure(error))
  }
}

/// One statement with no rows and no parameters.
fn execute(tx: pog.Connection, statement: String) -> Result(Nil, Failure) {
  pog.query(statement)
  |> pog.execute(tx)
  |> result.replace(Nil)
  |> result.map_error(database_failure)
}

/// The row in the file of the spawn a refused stat belongs to, from the detail
/// `Failing row contains (spawn_id, stat, value)`: the first value is the spawn's
/// id in the table, which the table maps to its row in the file. A detail that does
/// not read gives no row; a lookup the database fails is that failure.
fn row_of_stat(
  tx tx: pog.Connection,
  detail detail: String,
) -> Result(Option(Int), Failure) {
  let spawn_id =
    string.split_once(detail, "Failing row contains (")
    |> result.try(fn(split) { string.split(split.1, ", ") |> list.first })
    |> result.try(int.parse)
  case spawn_id {
    Error(Nil) -> Ok(None)
    Ok(spawn_id) ->
      case sql.source_row_of_spawn(tx, spawn_id) {
        Ok(pog.Returned(rows: [row, ..], ..)) -> Ok(row.source_row)
        Ok(pog.Returned(rows: [], ..)) -> Ok(None)
        Error(error) -> Error(database_failure(error))
      }
  }
}

/// The one row an aggregate query gives, read by `read`; 0 when it gave none.
fn first_of(rows: List(row), read: fn(row) -> Int) -> Int {
  case rows {
    [row, ..] -> read(row)
    [] -> 0
  }
}

/// The row id in the file of the row a constraint refused, from the detail
/// `Failing row contains (id, source, source_row, ...)`, the third value.
fn source_row_of(detail: String) -> Option(Int) {
  case string.split_once(detail, "Failing row contains (") {
    Ok(#(_, rest)) ->
      case string.split(rest, ", ") {
        [_, _, source_row, ..] ->
          case int.parse(source_row) {
            Ok(source_row) -> Some(source_row)
            Error(Nil) -> None
          }
        _ -> None
      }
    Error(Nil) -> None
  }
}

/// A sentence for a refusal of the reader.
pub fn describe_refusal(refusal refusal: Refusal) -> String {
  case refusal {
    WrongHeader(found:) ->
      "spawn.tsv line 1: the header is not the 20 columns "
      <> string.join(spawn_columns, ", ")
      <> ", it is: "
      <> found
    WrongFieldCount(line:, found:) ->
      "spawn.tsv line "
      <> int.to_string(line)
      <> ": "
      <> int.to_string(found)
      <> " fields, not 20"
    BadField(line:, column:, value:, wanted:) ->
      "spawn.tsv line "
      <> int.to_string(line)
      <> ", column "
      <> column
      <> ": "
      <> value
      <> " is not "
      <> wanted
    RepeatedId(line:, id:) ->
      "spawn.tsv line "
      <> int.to_string(line)
      <> ", column id: "
      <> int.to_string(id)
      <> " is in the file twice"
    UnequalStats(line:, ids:, values:) ->
      "spawn.tsv line "
      <> int.to_string(line)
      <> ", columns stat_ids and stat_values: "
      <> int.to_string(ids)
      <> " ids and "
      <> int.to_string(values)
      <> " values"
  }
}

fn describe(failure failure: Failure) -> String {
  case failure {
    NoWorldData ->
      "GENESIS_WORLD_DATA is not set: it names the folder of the world database, a line of ~/.genesis-prime/env.sh"
    Unreadable(file:, reason:) ->
      "the file " <> file <> " could not be read: " <> reason
    FileRefused(refusal:) -> describe_refusal(refusal:)
    RowRefused(constraint:, source_row:) ->
      "the database refused row "
      <> case source_row {
        Some(row) -> int.to_string(row)
        None -> "?"
      }
      <> " of spawn.tsv, under the constraint "
      <> constraint
      <> ": nothing was written"
    Database(failure:) -> dev_database.describe(failure, "import spawn.tsv")
  }
}

/// What an import printed: the counts.
fn describe_counts(file file: String, counts counts: Counts) -> String {
  file
  <> ": inserted "
  <> int.to_string(counts.inserted)
  <> ", changed "
  <> int.to_string(counts.changed)
  <> ", removed "
  <> int.to_string(counts.removed)
  <> ", unchanged "
  <> int.to_string(counts.unchanged)
  <> "; stats written "
  <> int.to_string(counts.stats_written)
  <> ", deleted "
  <> int.to_string(counts.stats_deleted)
}
