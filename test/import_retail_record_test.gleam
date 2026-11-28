//// The retail-record import's change detection and writes (`genesis_prime/import_retail_record`:
//// the queries `count_*`, `retire_stale_*` and `insert_new_*` of both creature-spell tables),
//// on the retail rows migrations 0035 and 0036 hold. Expected values come from these places.
//// - A creature spell is keyed by its creature and its spell: the unique indexes
////   `creature_special_creature_id_spell4_id_is_unique` and
////   `creature_auto_attack_creature_id_spell4_id_is_unique` (migration 0036), on the rows no
////   run has retired. A row is the same when its order (and, for a special, its cooldown)
////   is the same; `source_row` is null on a retail-record row, by
////   `creature_special_world_database_row_has_a_source_row` and its twin, so it is no key.
//// - The migrated rows: Yeti Snowstalker (Creature2 51126) holds the auto-attacks Spell4 33251
////   at order 0 and 33252 at order 1; Rootbrute Grimspore (12212) holds the special Spell4
////   55317 at order 0 with a cooldown of 10 000 ms.
//// - The import's header: rows of another source and rows a run has retired are not counted,
////   and a second run of the same rows writes nothing.
//// Each test runs on a database of its own, copied from the migrated template.

import ask_support
import content_support
import database_support
import genesis_prime/content/creature_kind as content_creature_kind
import genesis_prime/dev_database
import genesis_prime/import_retail_record/sql
import genesis_prime/shared/creature_kind
import genesis_prime/table/id.{Spell4Id}
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import owned_test
import pog

/// Which table of creature spells a case runs on. A special holds a cooldown; an
/// auto-attack holds none.
type Table {
  Autos
  Specials
}

/// A creature spell as the import writes it: `cooldown_ms` is 0 for an auto-attack.
type Spell {
  Spell(creature_id: Int, spell4_id: Int, order_index: Int, cooldown_ms: Int)
}

/// What the import's count says of the rows it would write.
type Counts {
  Counts(inserted: Int, retired: Int, changed: Int, unchanged: Int)
}

/// What one run did: the counts, the rows each write touched and the run's id.
type Outcome {
  Outcome(counts: Counts, retired: Int, written: Int, run: Int)
}

fn table_name(table: Table) -> String {
  case table {
    Autos -> "creature_auto_attack"
    Specials -> "creature_special"
  }
}

/// The Yeti's first auto-attack, or Rootbrute Grimspore's special: the migrated row
/// the cases change.
fn the_row_the_case_changes(table: Table) -> Spell {
  case table {
    Autos ->
      Spell(
        creature_id: 51_126,
        spell4_id: 33_251,
        order_index: 0,
        cooldown_ms: 0,
      )
    Specials ->
      Spell(
        creature_id: 12_212,
        spell4_id: 55_317,
        order_index: 0,
        cooldown_ms: 10_000,
      )
  }
}

/// The rows a run that changes nothing writes: every active retail-record row of the table.
fn the_migrated_rows(
  database database: String,
  table table: Table,
) -> List(Spell) {
  let cooldown = case table {
    Autos -> "0"
    Specials -> "cooldown_ms"
  }
  let assert Ok(pog.Returned(rows:, ..)) =
    pog.query(
      "select creature_id, spell4_id, order_index::int, "
      <> cooldown
      <> " from "
      <> table_name(table)
      <> " where source = 'retail_record' and retired_by_import is null order by creature_id, spell4_id",
    )
    |> pog.returning({
      use creature_id <- decode.field(0, decode.int)
      use spell4_id <- decode.field(1, decode.int)
      use order_index <- decode.field(2, decode.int)
      use cooldown_ms <- decode.field(3, decode.int)
      decode.success(Spell(creature_id:, spell4_id:, order_index:, cooldown_ms:))
    })
    |> pog.timeout(ask_support.beyond_the_test_ms)
    |> pog.execute(content_support.connect(database:))
    as "the migrated rows read"
  rows
}

/// One run of the import on `incoming`, in the order the import does it: count, record the
/// run, retire what it no longer writes, write what is new.
fn run_import(
  database database: String,
  table table: Table,
  incoming incoming: List(Spell),
) -> Outcome {
  let column = fn(read: fn(Spell) -> Int) { list.map(incoming, read) }
  let creature_ids = column(fn(row) { row.creature_id })
  let spell4_ids = column(fn(row) { row.spell4_id })
  let order_indexes = column(fn(row) { row.order_index })
  let cooldowns = column(fn(row) { row.cooldown_ms })
  let assert Ok(outcome) =
    dev_database.transaction(
      db: content_support.connect(database:),
      deadline_ms: ask_support.beyond_the_test_ms,
      work: fn(tx) {
        use counted <- result.try(case table {
          Autos ->
            sql.count_auto_attacks(tx, creature_ids, spell4_ids, order_indexes)
            |> result.map(fn(returned) {
              list.map(returned.rows, fn(row) {
                Counts(row.inserted, row.retired, row.changed, row.unchanged)
              })
            })
          Specials ->
            sql.count_specials(
              tx,
              creature_ids,
              spell4_ids,
              order_indexes,
              cooldowns,
            )
            |> result.map(fn(returned) {
              list.map(returned.rows, fn(row) {
                Counts(row.inserted, row.retired, row.changed, row.unchanged)
              })
            })
        })
        let assert [counts] = counted as "the count gives one row"
        use started <- result.try(sql.start_import(
          tx,
          string.repeat("a", 64),
          0,
          0,
          0,
          0,
          0,
          0,
        ))
        let assert [sql.StartImportRow(id: run)] = started.rows
          as "the run's insert gives its id"
        use retired <- result.try(case table {
          Autos ->
            sql.retire_stale_auto_attacks(
              tx,
              run,
              creature_ids,
              spell4_ids,
              order_indexes,
            )
          Specials ->
            sql.retire_stale_specials(
              tx,
              run,
              creature_ids,
              spell4_ids,
              order_indexes,
              cooldowns,
            )
        })
        use written <- result.try(case table {
          Autos ->
            sql.insert_new_auto_attacks(
              tx,
              run,
              creature_ids,
              spell4_ids,
              order_indexes,
            )
          Specials ->
            sql.insert_new_specials(
              tx,
              run,
              creature_ids,
              spell4_ids,
              order_indexes,
              cooldowns,
            )
        })
        Ok(Outcome(
          counts:,
          retired: retired.count,
          written: written.count,
          run:,
        ))
      },
    )
    as "the run's statements ran"
  outcome
}

/// How many rows of the table hold the condition.
fn rows_where(
  database database: String,
  table table: Table,
  condition condition: String,
) -> Int {
  content_support.count(
    database:,
    sql: "select count(*) from " <> table_name(table) <> " where " <> condition,
  )
}

/// Each case runs on both tables unless its name says one.
fn on_each_table(case_: fn(Table) -> Nil) -> Nil {
  list.each([Autos, Specials], case_)
}

pub fn a_row_written_again_unchanged_is_counted_unchanged_and_nothing_is_retired_or_written_test() -> Nil {
  use <- owned_test.run(10_000)
  use table <- on_each_table
  let database = database_support.new_database(on: database_support.shared())
  let rows = the_migrated_rows(database:, table:)
  let outcome = run_import(database:, table:, incoming: rows)
  assert outcome.counts
    == Counts(inserted: 0, retired: 0, changed: 0, unchanged: list.length(rows))
    as { table_name(table) <> ": every row is the same row" }
  assert #(outcome.retired, outcome.written) == #(0, 0)
    as {
      table_name(table)
      <> ": a second run of the same rows retires and writes nothing"
    }
}

pub fn a_row_with_another_order_is_counted_changed_retired_and_written_again_test() -> Nil {
  use <- owned_test.run(10_000)
  use table <- on_each_table
  let database = database_support.new_database(on: database_support.shared())
  let changed = the_row_the_case_changes(table)
  let moved = Spell(..changed, order_index: 2)
  let rows =
    the_migrated_rows(database:, table:)
    |> list.map(fn(row) {
      case
        row.creature_id == changed.creature_id
        && row.spell4_id == changed.spell4_id
      {
        True -> moved
        False -> row
      }
    })
  let outcome = run_import(database:, table:, incoming: rows)
  assert outcome.counts
    == Counts(
      inserted: 0,
      retired: 0,
      changed: 1,
      unchanged: list.length(rows) - 1,
    )
    as { table_name(table) <> ": one row has another order" }
  assert #(outcome.retired, outcome.written) == #(1, 1)
    as {
      table_name(table) <> ": the old row is retired and the new one written"
    }
  let place = fn(order_index, condition) {
    rows_where(
      database:,
      table:,
      condition: "creature_id = "
        <> int.to_string(changed.creature_id)
        <> " and spell4_id = "
        <> int.to_string(changed.spell4_id)
        <> " and order_index = "
        <> int.to_string(order_index)
        <> " and "
        <> condition,
    )
  }
  assert place(
      changed.order_index,
      "retired_by_import = " <> int.to_string(outcome.run),
    )
    == 1
    as { table_name(table) <> ": the old row is retired by the run" }
  assert place(
      moved.order_index,
      "retired_by_import is null and import_id = " <> int.to_string(outcome.run),
    )
    == 1
    as {
      table_name(table)
      <> ": the new row has the new order and the run that wrote it"
    }
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil) as { table_name(table) <> ": the content loads" }
  case table {
    Autos -> {
      let kind =
        creature_kind.kind_of(
          kinds: content_creature_kind.kinds(key:),
          creature2_id: changed.creature_id,
        )
      assert kind.attack_spell4_id == Spell4Id(33_252)
        && kind.alternate_spell4_ids == [Spell4Id(33_251)]
        as "the Yeti leads with the auto-attack that is now first: Slam (33252) at order 1 before 33251 at order 2"
    }
    Specials -> Nil
  }
}

pub fn a_special_with_another_cooldown_is_counted_changed_and_written_again_test() -> Nil {
  use <- owned_test.run(10_000)
  let database = database_support.new_database(on: database_support.shared())
  let changed = the_row_the_case_changes(Specials)
  let slower = Spell(..changed, cooldown_ms: 12_000)
  let rows =
    the_migrated_rows(database:, table: Specials)
    |> list.map(fn(row) {
      case
        row.creature_id == changed.creature_id
        && row.spell4_id == changed.spell4_id
      {
        True -> slower
        False -> row
      }
    })
  let outcome = run_import(database:, table: Specials, incoming: rows)
  assert outcome.counts
    == Counts(
      inserted: 0,
      retired: 0,
      changed: 1,
      unchanged: list.length(rows) - 1,
    )
    as "one special has another cooldown"
  assert #(outcome.retired, outcome.written) == #(1, 1)
    as "the old special is retired and the new one written"
  assert rows_where(
      database:,
      table: Specials,
      condition: "creature_id = 12212 and spell4_id = 55317 and cooldown_ms = 12000 and retired_by_import is null and import_id = "
        <> int.to_string(outcome.run),
    )
    == 1
    as "the new row holds the new cooldown and the run that wrote it"
  assert rows_where(
      database:,
      table: Specials,
      condition: "creature_id = 12212 and spell4_id = 55317 and cooldown_ms = 10000 and retired_by_import = "
        <> int.to_string(outcome.run),
    )
    == 1
    as "the old row keeps its cooldown and is retired by the run"
}

pub fn a_row_the_import_no_longer_writes_is_counted_retired_and_retired_test() -> Nil {
  use <- owned_test.run(10_000)
  use table <- on_each_table
  let database = database_support.new_database(on: database_support.shared())
  let dropped = the_row_the_case_changes(table)
  let rows =
    the_migrated_rows(database:, table:)
    |> list.filter(fn(row) {
      row.creature_id != dropped.creature_id
      || row.spell4_id != dropped.spell4_id
    })
  let outcome = run_import(database:, table:, incoming: rows)
  assert outcome.counts
    == Counts(inserted: 0, retired: 1, changed: 0, unchanged: list.length(rows))
    as { table_name(table) <> ": one row is no longer written" }
  assert #(outcome.retired, outcome.written) == #(1, 0)
    as { table_name(table) <> ": the row is retired and nothing is written" }
  assert rows_where(
      database:,
      table:,
      condition: "creature_id = "
        <> int.to_string(dropped.creature_id)
        <> " and spell4_id = "
        <> int.to_string(dropped.spell4_id)
        <> " and retired_by_import = "
        <> int.to_string(outcome.run),
    )
    == 1
    as { table_name(table) <> ": the row is retired by the run" }
}

pub fn a_new_creature_and_spell_is_counted_inserted_and_written_as_a_retail_record_test() -> Nil {
  use <- owned_test.run(10_000)
  use table <- on_each_table
  let database = database_support.new_database(on: database_support.shared())
  let cooldown = case table {
    Autos -> 0
    Specials -> 10_000
  }
  let new =
    Spell(
      creature_id: 99_001,
      spell4_id: 99_002,
      order_index: 0,
      cooldown_ms: cooldown,
    )
  let rows = the_migrated_rows(database:, table:)
  let outcome = run_import(database:, table:, incoming: [new, ..rows])
  assert outcome.counts
    == Counts(inserted: 1, retired: 0, changed: 0, unchanged: list.length(rows))
    as { table_name(table) <> ": one row is new" }
  assert #(outcome.retired, outcome.written) == #(0, 1)
    as {
      table_name(table) <> ": the new row is written and nothing is retired"
    }
  assert rows_where(
      database:,
      table:,
      condition: "creature_id = 99001 and spell4_id = 99002 and source = 'retail_record' and source_row is null and retired_by_import is null and import_id = "
        <> int.to_string(outcome.run),
    )
    == 1
    as {
      table_name(table)
      <> ": the row is a retail record written by the run, with no source row"
    }
}

pub fn a_row_of_another_source_is_never_counted_or_retired_test() -> Nil {
  use <- owned_test.run(10_000)
  use table <- on_each_table
  let database = database_support.new_database(on: database_support.shared())
  let #(creature_id, columns, values) = case table {
    Autos -> #(51_126, "order_index", "9")
    Specials -> #(12_212, "order_index, cooldown_ms", "1, 10000")
  }
  let creature = int.to_string(creature_id)
  let table_text = table_name(table)
  content_support.change(
    database:,
    sql: "insert into "
      <> table_text
      <> " (creature_id, spell4_id, "
      <> columns
      <> ", source) values ("
      <> creature
      <> ", 99001, "
      <> values
      <> ", 'server_choice')",
  )
  content_support.change(
    database:,
    sql: "insert into retail_record_import (input_sha256, auto_attacks_added, auto_attacks_retired, auto_attacks_kept, specials_added, specials_retired, specials_kept) values (repeat('a', 64), 0, 0, 0, 0, 0, 0)",
  )
  content_support.change(
    database:,
    sql: "insert into "
      <> table_text
      <> " (creature_id, spell4_id, "
      <> columns
      <> ", source, import_id, retired_by_import) values ("
      <> creature
      <> ", 99002, "
      <> the_values_of_a_retired_row(table)
      <> ", 'retail_record', (select max(id) from retail_record_import), (select max(id) from retail_record_import))",
  )
  let rows = the_migrated_rows(database:, table:)
  let outcome = run_import(database:, table:, incoming: rows)
  assert outcome.counts
    == Counts(inserted: 0, retired: 0, changed: 0, unchanged: list.length(rows))
    as {
      table_text
      <> ": a row of another source and a retired retail row are not counted"
    }
  assert #(outcome.retired, outcome.written) == #(0, 0)
    as { table_text <> ": neither is retired or written" }
  assert rows_where(
      database:,
      table:,
      condition: "creature_id = "
        <> creature
        <> " and spell4_id = 99001 and source = 'server_choice' and retired_by_import is null",
    )
    == 1
    as { table_text <> ": the server's row stays" }
}

/// The values of a retired retail row: a place the creature's list does not use.
fn the_values_of_a_retired_row(table: Table) -> String {
  case table {
    Autos -> "8"
    Specials -> "2, 10000"
  }
}
