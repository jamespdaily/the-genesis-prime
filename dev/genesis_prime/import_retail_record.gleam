//// Imports the retail record's creature spells into the content tables
//// `creature_auto_attack` and `creature_special` (genesis_prime/content): for each
//// spawned creature the record's page matches, the auto-attacks and specials its
//// Abilities tab lists that the server's own load accepts.
////
//// `gleam run -m genesis_prime/import_retail_record [-- --list] [--dry-run] [--accept-smaller-read]`
////
//// It reads
//// - `npcs.jsonl` in `$GENESIS_JABBITHOLE_DIR` (Jabbithole's local record, never
////   committed; the tool refuses to run with the variable unset);
//// - the client's tables (`$GENESIS_TABLE_DIR`, else `GENESIS_HOME`/tables, else
////   `~/.genesis-prime/tables`) and `en-US.bin` (`$GENESIS_CLIENT_FILES_DIR`, else
////   `GENESIS_HOME`/client-files, else `~/.genesis-prime/client-files`);
//// - from the database the server uses (PGHOST, PGPORT, PGUSER, PGPASSWORD and
////   PGDATABASE): the spawn rows the import of the world database wrote (run
////   `genesis_prime/import_world_data` first) and the `creature_kind` rows.
////
//// ```
//// npcs.jsonl ─▶ pages (genesis_prime/jabbithole_page)
//// spawns, names, tables ─▶ rule (genesis_prime/retail_creature_spell): an outcome per creature
//// outcomes ─▶ writer, one transaction:
////                count against the table's active retail_record rows
////                print what it would add and retire
////                refuse a read under `smallest_read_percent` of them
////                record the run in retail_record_import
////                retire the active retail_record rows the import no longer produces or has changed
////                insert the rows the table lacks, each carrying the run's id
////          ─▶ report: counts, creatures and spells left out by rule
//// ```
////
//// - **It owns every `retail_record` row of the two tables, and deletes none.** A row the
////   rule no longer produces is retired: its `retired_by_import` is the run's id, and the
////   content load reads only rows no run has retired. A changed row is retired and written
////   again. Rows of any other source (`server_choice`, `world_database`) are never touched,
////   and a row of another source that holds the same creature and spell, or the same place
////   in the creature's list, makes the table refuse the write, so nothing is written.
//// - **It refuses a read that is empty or much smaller:** no spawn row of a fighting unit
////   type, or fewer rows to write than `smallest_read_percent` of the table's active
////   `retail_record` rows. `--accept-smaller-read` lets a smaller one through.
//// - **`--dry-run`** prints what it would add and retire and writes nothing.
//// - **It writes only what the server's load accepts:** the rule runs the load's own
////   checks of an auto-attack and of a special for the creature's difficulty.
//// - **It is idempotent.** A second run of the same input retires and writes nothing; it still
////   records itself in `retail_record_import`.
//// - **It does not record itself in `content_import`:** that table holds files the setup
////   check re-hashes from `GENESIS_WORLD_DATA`, which Jabbithole's record is not part of.
//// - **A refused file writes nothing:** a line of `npcs.jsonl` that is not JSON or lacks a
////   field, a malformed `en-US.bin`, a table that does not load.
//// - **`--list`** prints, after the counts, each creature left out and each spell left
////   out with its rule.

import argv
import envoy
import genesis_prime/content/creature_kind as content_creature_kind
import genesis_prime/content/refusal
import genesis_prime/dev_database
import genesis_prime/digest
import genesis_prime/import_retail_record/sql
import genesis_prime/jabbithole_page
import genesis_prime/language_file
import genesis_prime/retail_creature_spell.{
  type Auto, type Outcome, type Special, Matched, Unmatched,
}
import genesis_prime/table
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/table/loader/store
import genesis_prime/table_folder
import genesis_prime/world_map/creature_unit_type
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/result
import gleam/set
import gleam/string
import pog
import simplifile

/// How a table's retail-record rows stood against the import's rows.
type Counts {
  Counts(inserted: Int, changed: Int, retired: Int, unchanged: Int)
}

/// Why an import did not finish.
type Failure {
  /// `GENESIS_JABBITHOLE_DIR` is not set.
  NoRecord
  /// A file could not be read.
  Unreadable(file: String, reason: String)
  /// The record's file was refused; nothing was written.
  RecordRefused(refusal: jabbithole_page.Refusal)
  /// `en-US.bin` was refused; nothing was written.
  LanguageRefused(refusal: language_file.Refusal)
  /// The client's tables did not load.
  TablesUnreadable(error: store.LoadError)
  /// The spawn table gave no row of a unit type the server fights with, so the import
  /// would retire every `retail_record` row; `groups_read` is how many creature, world
  /// and area groups the query returned, of any unit type.
  NoSpawns(groups_read: Int)
  /// The import would write fewer rows of a table than `smallest_read_percent` of its
  /// active `retail_record` rows.
  ReadTooSmall(table: String, writing: Int, active: Int)
  /// The creature_kind table holds rows the load refuses; nothing was written.
  KindRowsRefused(refusals: List(refusal.Refusal))
  /// The database refused a row, naming the constraint; nothing was written.
  RowRefused(constraint: String)
  /// The database failed in another way.
  Database(failure: dev_database.Failure)
}

/// What a run did, for the report.
type Done {
  Done(
    outcomes: List(Outcome),
    names: Dict(Int, String),
    autos: Counts,
    specials: Counts,
    list_all: Bool,
    dry_run: Bool,
  )
}

/// What the run does with the rows it counted.
type Mode {
  /// Writes, but refuses a read under `smallest_read_percent` of the active rows unless
  /// `accept_smaller` is true.
  Write(accept_smaller: Bool)
  /// Prints what it would add and retire and writes nothing.
  DryRun
}

/// A read that gives fewer rows of a table than this share of its active `retail_record`
/// rows, in percent, is refused: a changed input or an unread record, not a changed page.
const smallest_read_percent = 50

pub fn main() -> Nil {
  dev_database.finish(result: run(), describe:)
}

fn run() -> Result(String, Failure) {
  let arguments = argv.load().arguments
  let list_all = list.contains(arguments, "--list")
  let dry_run = list.contains(arguments, "--dry-run")
  let mode = case dry_run {
    True -> DryRun
    False ->
      Write(accept_smaller: list.contains(arguments, "--accept-smaller-read"))
  }
  use folder <- result.try(
    envoy.get("GENESIS_JABBITHOLE_DIR") |> result.replace_error(NoRecord),
  )
  use db <- result.try(dev_database.connect() |> result.map_error(Database))
  use #(pages, input_sha256) <- result.try(read_pages(folder:))
  use language <- result.try(read_language())
  use tables <- result.try(
    table.read(from: table_folder.path())
    |> result.map_error(TablesUnreadable),
  )
  use spawned <- result.try(read_spawned(db:))
  use kind_rows <- result.try(
    content_creature_kind.rows(db)
    |> result.map_error(fn(error) {
      case error {
        content_creature_kind.QueryFailed(reason:) ->
          Database(dev_database.failure_of(error: reason))
        content_creature_kind.RowsRefused(refusals:) ->
          KindRowsRefused(refusals:)
      }
    }),
  )
  use texts <- result.try(texts_of(language:, tables:, spawned:))
  let outcomes =
    retail_creature_spell.plan(
      inputs: retail_creature_spell.Inputs(
        tables:,
        texts:,
        pages:,
        kind_creature_ids: set.from_list(
          list.map(kind_rows, fn(row) { row.creature_id }),
        ),
      ),
      spawned:,
    )
  let autos = list.flat_map(outcomes, autos_of)
  let specials = list.flat_map(outcomes, specials_of)
  use #(auto_counts, special_counts) <- result.map(write(
    db:,
    autos:,
    specials:,
    input_sha256:,
    mode:,
  ))
  report(Done(
    outcomes:,
    names: names_of(texts:, tables:, outcomes:),
    autos: auto_counts,
    specials: special_counts,
    list_all:,
    dry_run:,
  ))
}

/// The pages of the record's file, with the SHA-256 of the file's bytes.
fn read_pages(
  folder folder: String,
) -> Result(#(List(jabbithole_page.Page), String), Failure) {
  let file = folder <> "/npcs.jsonl"
  use text <- result.try(
    simplifile.read(file)
    |> result.map_error(fn(error) {
      Unreadable(file:, reason: simplifile.describe_error(error))
    }),
  )
  jabbithole_page.read(text:)
  |> result.map(fn(pages) {
    #(pages, digest.sha256(bit_array.from_string(text)))
  })
  |> result.map_error(RecordRefused)
}

fn read_language() -> Result(language_file.LanguageFile, Failure) {
  let file = table_folder.client_files_path() <> "/en-US.bin"
  use bytes <- result.try(
    simplifile.read_bits(file)
    |> result.map_error(fn(error) {
      Unreadable(file:, reason: simplifile.describe_error(error))
    }),
  )
  language_file.read(bytes:) |> result.map_error(LanguageRefused)
}

/// The spawn rows of the unit types the server fights with.
fn read_spawned(
  db db: pog.Connection,
) -> Result(List(retail_creature_spell.Spawned), Failure) {
  use returned <- result.try(
    sql.spawned_creatures(db)
    |> result.map_error(fn(error) { Database(dev_database.failure_of(error:)) }),
  )
  let spawned =
    returned.rows
    |> list.filter(fn(row) {
      result.is_ok(creature_unit_type.of_entity_type(
        entity_type: row.entity_type,
      ))
    })
    |> list.map(fn(row) {
      retail_creature_spell.Spawned(
        creature_id: row.creature_id,
        world_id: row.world_id,
        area_id: row.area_id,
        spawns: row.spawns,
      )
    })
  case spawned {
    [] -> Error(NoSpawns(groups_read: list.length(returned.rows)))
    _ -> Ok(spawned)
  }
}

/// The name texts of the spawned creatures that the client's Creature2 table holds,
/// by text id.
fn texts_of(
  language language: language_file.LanguageFile,
  tables tables: store.Tables,
  spawned spawned: List(retail_creature_spell.Spawned),
) -> Result(Dict(Int, String), Failure) {
  list.map(spawned, fn(row) { row.creature_id })
  |> list.unique
  |> list.filter_map(fn(creature_id) {
    creature2.get(tables:, id: Creature2Id(creature_id))
    |> result.map(fn(creature) { creature.localized_text_id_name })
  })
  |> list.unique
  |> list.try_fold(dict.new(), fn(texts, text_id) {
    use found <- result.map(
      language_file.text(file: language, text_id:)
      |> result.map_error(LanguageRefused),
    )
    case found {
      Some(text) -> dict.insert(texts, text_id, text)
      None -> texts
    }
  })
}

/// The names of the creatures in the outcomes, for the report.
fn names_of(
  texts texts: Dict(Int, String),
  tables tables: store.Tables,
  outcomes outcomes: List(Outcome),
) -> Dict(Int, String) {
  list.filter_map(outcomes, fn(outcome) {
    let creature_id = outcome.creature_id
    use creature <- result.try(creature2.get(
      tables:,
      id: Creature2Id(creature_id),
    ))
    use text <- result.map(dict.get(texts, creature.localized_text_id_name))
    #(creature_id, retail_creature_spell.without_plural_marks(text))
  })
  |> dict.from_list
}

fn autos_of(outcome: Outcome) -> List(Auto) {
  case outcome {
    Matched(autos:, ..) -> autos
    Unmatched(..) -> []
  }
}

fn specials_of(outcome: Outcome) -> List(Special) {
  case outcome {
    Matched(specials:, ..) -> specials
    Unmatched(..) -> []
  }
}

/// Why the transaction's work stopped before its commit.
type Stop {
  /// A failure; nothing was written.
  Stopped(failure: Failure)
  /// A dry run, rolled back, with what the run counted.
  Planned(autos: Counts, specials: Counts)
}

/// Counts the rows in one transaction, refuses a read that is empty or much smaller, prints
/// what it would add and retire, and, unless it is a dry run, records the run, retires the
/// rows the import no longer produces and writes the rest. Gives how the two tables'
/// active retail-record rows stood before.
fn write(
  db db: pog.Connection,
  autos autos: List(Auto),
  specials specials: List(Special),
  input_sha256 input_sha256: String,
  mode mode: Mode,
) -> Result(#(Counts, Counts), Failure) {
  dev_database.transaction(
    db:,
    deadline_ms: statements * dev_database.default_timeout_ms,
    work: fn(tx) {
      let auto_columns = fn(read: fn(Auto) -> a) { list.map(autos, read) }
      let special_columns = fn(read: fn(Special) -> a) {
        list.map(specials, read)
      }
      use counted_autos <- result.try(
        sql.count_auto_attacks(
          tx,
          auto_columns(fn(row) { row.creature_id }),
          auto_columns(fn(row) { row.spell4_id }),
          auto_columns(fn(row) { row.order_index }),
          auto_columns(fn(row) { row.reason }),
        )
        |> result.map_error(stopped),
      )
      use counted_specials <- result.try(
        sql.count_specials(
          tx,
          special_columns(fn(row) { row.creature_id }),
          special_columns(fn(row) { row.spell4_id }),
          special_columns(fn(row) { row.order_index }),
          special_columns(fn(row) { row.cooldown_ms }),
          special_columns(fn(row) { row.reason }),
        )
        |> result.map_error(stopped),
      )
      let auto_counts =
        first_row(counted_autos.rows, fn(row) {
          Counts(
            inserted: row.inserted,
            changed: row.changed,
            retired: row.retired,
            unchanged: row.unchanged,
          )
        })
      let special_counts =
        first_row(counted_specials.rows, fn(row) {
          Counts(
            inserted: row.inserted,
            changed: row.changed,
            retired: row.retired,
            unchanged: row.unchanged,
          )
        })
      io.println(
        "creature_auto_attack: would add "
        <> int.to_string(added(auto_counts))
        <> ", retire "
        <> int.to_string(retired(auto_counts))
        <> ", keep "
        <> int.to_string(auto_counts.unchanged)
        <> "\ncreature_special: would add "
        <> int.to_string(added(special_counts))
        <> ", retire "
        <> int.to_string(retired(special_counts))
        <> ", keep "
        <> int.to_string(special_counts.unchanged),
      )
      use _checked <- result.try(case mode {
        Write(accept_smaller: False) ->
          read_is_large_enough(
            table: "creature_auto_attack",
            counts: auto_counts,
          )
          |> result.try(fn(_) {
            read_is_large_enough(
              table: "creature_special",
              counts: special_counts,
            )
          })
          |> result.map_error(Stopped)
        Write(accept_smaller: True) | DryRun -> Ok(Nil)
      })
      case mode {
        DryRun -> Error(Planned(autos: auto_counts, specials: special_counts))
        Write(..) -> {
          use started <- result.try(
            sql.start_import(
              tx,
              input_sha256,
              added(auto_counts),
              retired(auto_counts),
              auto_counts.unchanged,
              added(special_counts),
              retired(special_counts),
              special_counts.unchanged,
            )
            |> result.map_error(stopped),
          )
          let assert [sql.StartImportRow(id: import_id)] = started.rows
            as "an insert that returns its id gives one row"
          use _retired <- result.try(
            sql.retire_stale_auto_attacks(
              tx,
              import_id,
              auto_columns(fn(row) { row.creature_id }),
              auto_columns(fn(row) { row.spell4_id }),
              auto_columns(fn(row) { row.order_index }),
              auto_columns(fn(row) { row.reason }),
            )
            |> result.map_error(stopped),
          )
          use _retired <- result.try(
            sql.retire_stale_specials(
              tx,
              import_id,
              special_columns(fn(row) { row.creature_id }),
              special_columns(fn(row) { row.spell4_id }),
              special_columns(fn(row) { row.order_index }),
              special_columns(fn(row) { row.cooldown_ms }),
              special_columns(fn(row) { row.reason }),
            )
            |> result.map_error(stopped),
          )
          use _inserted <- result.try(
            sql.insert_new_auto_attacks(
              tx,
              import_id,
              auto_columns(fn(row) { row.creature_id }),
              auto_columns(fn(row) { row.spell4_id }),
              auto_columns(fn(row) { row.order_index }),
              auto_columns(fn(row) { row.reason }),
            )
            |> result.map_error(stopped),
          )
          use _inserted <- result.try(
            sql.insert_new_specials(
              tx,
              import_id,
              special_columns(fn(row) { row.creature_id }),
              special_columns(fn(row) { row.spell4_id }),
              special_columns(fn(row) { row.order_index }),
              special_columns(fn(row) { row.cooldown_ms }),
              special_columns(fn(row) { row.reason }),
            )
            |> result.map_error(stopped),
          )
          Ok(#(auto_counts, special_counts))
        }
      }
    },
  )
  |> fn(done) {
    case done {
      Ok(counts) -> Ok(counts)
      Error(dev_database.Undone(Planned(autos:, specials:))) ->
        Ok(#(autos, specials))
      Error(dev_database.Undone(Stopped(failure))) -> Error(failure)
      Error(dev_database.NoConnection) ->
        Error(Database(dev_database.DatabaseDown))
      Error(dev_database.Failed(error)) -> Error(failure_of(error))
      Error(dev_database.NotAPool) ->
        Error(
          Database(dev_database.NotChanged(
            "the import needs a pool of connections, not one connection",
          )),
        )
    }
  }
}

fn stopped(error: pog.QueryError) -> Stop {
  Stopped(failure_of(error))
}

/// The rows a run adds: the new ones and the changed ones, written again.
fn added(counts: Counts) -> Int {
  counts.inserted + counts.changed
}

/// The rows a run retires: the ones it no longer produces and the changed ones.
fn retired(counts: Counts) -> Int {
  counts.retired + counts.changed
}

/// Refuses a table the import would write under `smallest_read_percent` of its active
/// rows; a table with no active row passes.
fn read_is_large_enough(
  table table: String,
  counts counts: Counts,
) -> Result(Nil, Failure) {
  let active = counts.changed + counts.retired + counts.unchanged
  let writing = counts.inserted + counts.changed + counts.unchanged
  case active > 0 && writing * 100 < active * smallest_read_percent {
    True -> Error(ReadTooSmall(table:, writing:, active:))
    False -> Ok(Nil)
  }
}

/// The statements the transaction runs, for its deadline: seven, each allowed pog's own
/// query timeout, and the transaction's own begin and commit.
const statements = 9

fn first_row(rows: List(row), counts: fn(row) -> Counts) -> Counts {
  case rows {
    [row, ..] -> counts(row)
    [] -> Counts(inserted: 0, changed: 0, retired: 0, unchanged: 0)
  }
}

fn failure_of(error: pog.QueryError) -> Failure {
  case error {
    pog.ConstraintViolated(constraint:, ..) -> RowRefused(constraint:)
    pog.PostgresqlError(..)
    | pog.UnexpectedArgumentCount(..)
    | pog.UnexpectedArgumentType(..)
    | pog.UnexpectedResultType(..)
    | pog.QueryTimeout
    | pog.ConnectionUnavailable -> Database(dev_database.failure_of(error:))
  }
}

fn describe(failure failure: Failure) -> String {
  case failure {
    NoRecord ->
      "GENESIS_JABBITHOLE_DIR is not set: it names the folder that holds Jabbithole's npcs.jsonl"
    Unreadable(file:, reason:) ->
      "the file " <> file <> " could not be read: " <> reason
    RecordRefused(refusal:) ->
      jabbithole_page.describe(refusal:) <> ": nothing was written"
    LanguageRefused(refusal:) ->
      "en-US.bin: "
      <> language_file.describe(refusal:)
      <> ": nothing was written"
    TablesUnreadable(error:) ->
      "the client's tables did not load from "
      <> table_folder.path()
      <> ": "
      <> store.describe(error)
      <> "; run python3.13 -I setup_check/extract_tables.py"
    NoSpawns(groups_read: 0) ->
      "the spawn table holds no rows, so every retail_record row would be retired: run genesis_prime/import_world_data first; nothing was written"
    NoSpawns(groups_read:) ->
      "none of the "
      <> int.to_string(groups_read)
      <> " creature, world and area groups in the spawn table is of a unit type the server fights with, so every retail_record row would be retired: nothing was written"
    ReadTooSmall(table:, writing:, active:) ->
      "the import would write "
      <> int.to_string(writing)
      <> " rows of "
      <> table
      <> ", under "
      <> int.to_string(smallest_read_percent)
      <> "% of its "
      <> int.to_string(active)
      <> " active retail_record rows: nothing was written; pass --accept-smaller-read if the smaller read is right"
    KindRowsRefused(refusals:) ->
      string.join(list.map(refusals, refusal.describe), "; ")
      <> ": nothing was written"
    RowRefused(constraint:) ->
      "the database refused a row under the constraint "
      <> constraint
      <> ": nothing was written"
    Database(failure:) ->
      dev_database.describe(failure, "import the retail record")
  }
}

// ---------------------------------------------------------------- the report

fn report(done: Done) -> String {
  let matched =
    list.filter_map(done.outcomes, fn(outcome) {
      case outcome {
        Matched(..) -> Ok(outcome)
        Unmatched(..) -> Error(Nil)
      }
    })
  let unmatched =
    list.filter_map(done.outcomes, fn(outcome) {
      case outcome {
        Unmatched(creature_id:, spawns:, why:) ->
          Ok(#(creature_id, spawns, why))
        Matched(..) -> Error(Nil)
      }
    })
  let spawns_of = fn(outcomes: List(Outcome)) {
    list.fold(outcomes, 0, fn(total, outcome) { total + outcome.spawns })
  }
  let with_autos =
    list.filter(matched, fn(outcome) {
      case outcome {
        Matched(autos: [_, ..], ..) -> True
        _ -> False
      }
    })
  let with_specials =
    list.filter(matched, fn(outcome) {
      case outcome {
        Matched(specials: [_, ..], ..) -> True
        _ -> False
      }
    })
  let spell_rules = spell_rules_of(matched)
  let lines =
    list.flatten([
      [
        "creatures with a spawn of a fighting unit type: "
          <> count(done.outcomes)
          <> " ("
          <> int.to_string(spawns_of(done.outcomes))
          <> " spawns)",
        "  matched to a page: "
          <> count(matched)
          <> " ("
          <> int.to_string(spawns_of(matched))
          <> " spawns)",
        "    with an auto-attack written: "
          <> count(with_autos)
          <> " ("
          <> int.to_string(spawns_of(with_autos))
          <> " spawns)",
        "    with a special written: "
          <> count(with_specials)
          <> " ("
          <> int.to_string(spawns_of(with_specials))
          <> " spawns)",
        "  left out, by rule:",
      ],
      list.map(creature_rules_of(unmatched), fn(rule) {
        "    " <> rule.0 <> ": " <> int.to_string(rule.1) <> " creatures"
      }),
      ["spells left out, by rule (creature and spell pairs):"],
      list.map(spell_rules, fn(rule) {
        "  "
        <> int.to_string(rule.1)
        <> " x "
        <> rule.0
        <> " (for example Spell4 "
        <> int.to_string(rule.2)
        <> ")"
      }),
      [
        case done.dry_run {
          True -> "dry run, nothing was written; the rows stood so:"
          False -> "the rows stood so before the run:"
        },
        "creature_auto_attack: " <> describe_counts(done.autos),
        "creature_special: " <> describe_counts(done.specials),
      ],
      case done.list_all {
        True -> listing(done:)
        False -> []
      },
    ])
  string.join(lines, "\n")
}

fn count(items: List(a)) -> String {
  int.to_string(list.length(items))
}

fn describe_counts(counts: Counts) -> String {
  "inserted "
  <> int.to_string(counts.inserted)
  <> ", changed "
  <> int.to_string(counts.changed)
  <> ", retired "
  <> int.to_string(counts.retired)
  <> ", unchanged "
  <> int.to_string(counts.unchanged)
}

fn why_of(why: retail_creature_spell.Why) -> String {
  case why {
    retail_creature_spell.NotInTheClientTable ->
      "the client's Creature2 table has no such creature"
    retail_creature_spell.NoNameInTheClient ->
      "the client has no text for the creature's name"
    retail_creature_spell.NoPageByName ->
      "no page of the record has the creature's name"
    retail_creature_spell.NoPageInTheCreatureWorlds ->
      "no page of that name is in a world the creature spawns in"
    retail_creature_spell.PagesDisagree(urls:) ->
      "pages that list different spells, even by the zone of a spawn's area: "
      <> string.join(urls, " and ")
  }
}

/// The rule that left creatures out and how many, most first; the pages that disagree
/// are one rule, their addresses in the listing.
fn creature_rules_of(
  unmatched: List(#(Int, Int, retail_creature_spell.Why)),
) -> List(#(String, Int)) {
  let rule = fn(why: retail_creature_spell.Why) {
    case why {
      retail_creature_spell.PagesDisagree(..) ->
        "pages that list different spells, even by the zone of a spawn's area"
      _ -> why_of(why)
    }
  }
  tally(list.map(unmatched, fn(entry) { rule(entry.2) }))
}

fn tally(rules: List(String)) -> List(#(String, Int)) {
  list.fold(rules, dict.new(), fn(counts, rule) {
    dict.upsert(counts, rule, fn(found) { option.unwrap(found, 0) + 1 })
  })
  |> dict.to_list
  |> list.sort(fn(first, second) {
    case int.compare(second.1, first.1) {
      order.Eq -> string.compare(first.0, second.0)
      other -> other
    }
  })
}

/// Each rule that left a spell out, how many pairs and one Spell4 as an example.
fn spell_rules_of(matched: List(Outcome)) -> List(#(String, Int, Int)) {
  let left_out =
    list.flat_map(matched, fn(outcome) {
      case outcome {
        Matched(left_out:, ..) ->
          list.map(left_out, fn(spell) {
            #(
              retail_creature_spell.rule_of(refusal: spell.why),
              spell.spell4_id,
            )
          })
        Unmatched(..) -> []
      }
    })
  let examples =
    list.fold(left_out, dict.new(), fn(examples, entry) {
      dict.upsert(examples, entry.0, fn(found) {
        case found {
          Some(first) -> int.min(first, entry.1)
          None -> entry.1
        }
      })
    })
  tally(list.map(left_out, fn(entry) { entry.0 }))
  |> list.map(fn(rule) {
    #(rule.0, rule.1, result.unwrap(dict.get(examples, rule.0), 0))
  })
}

/// The `--list` lines: each creature left out and each spell left out.
fn listing(done done: Done) -> List(String) {
  let name = fn(creature_id) {
    case dict.get(done.names, creature_id) {
      Ok(name) -> name
      Error(Nil) -> "?"
    }
  }
  list.flat_map(done.outcomes, fn(outcome) {
    case outcome {
      Unmatched(creature_id:, why:, spawns:) -> [
        "left out creature "
        <> int.to_string(creature_id)
        <> " "
        <> name(creature_id)
        <> " ("
        <> int.to_string(spawns)
        <> " spawns): "
        <> why_of(why),
      ]
      Matched(creature_id:, left_out:, ..) ->
        list.map(left_out, fn(spell) {
          "left out Spell4 "
          <> int.to_string(spell.spell4_id)
          <> " of creature "
          <> int.to_string(creature_id)
          <> " "
          <> name(creature_id)
          <> ": "
          <> retail_creature_spell.describe(refusal: spell.why)
        })
    }
  })
}
