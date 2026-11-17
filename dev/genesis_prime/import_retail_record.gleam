//// Imports the retail record's creature spells into the content tables
//// `creature_auto_attack` and `creature_special` (genesis_prime/content): for each
//// spawned creature the record's page matches, the auto-attacks and specials its
//// Abilities tab lists that the server's own load accepts.
////
//// `gleam run -m genesis_prime/import_retail_record [-- --list]`
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
////                count against the table's retail_record rows
////                delete the retail_record rows the import no longer produces or has changed
////                insert the rows the table lacks
////          ─▶ report: counts, creatures and spells left out by rule
//// ```
////
//// - **It owns every `retail_record` row of the two tables.** A row the rule no longer
////   produces is removed and counted; rows of any other source (`server_choice`,
////   `world_database`) are left alone, and a row of another source that holds the same
////   creature and spell, or the same place in the creature's list, makes the table refuse
////   the write, so nothing is written.
//// - **It writes only what the server's load accepts:** the rule runs the load's own
////   checks of an auto-attack and of a special for the creature's difficulty.
//// - **It is idempotent.** A second run of the same input changes nothing.
//// - **It does not record itself in `content_import`:** that table holds files the setup
////   check re-hashes from `GENESIS_WORLD_DATA`, which Jabbithole's record is not part of.
//// - **A refused file writes nothing:** a line of `npcs.jsonl` that is not JSON or lacks a
////   field, a malformed `en-US.bin`, a table that does not load.
//// - **`--list`** prints, after the counts, each creature left out and each spell left
////   out with its rule.

import argv
import envoy
import genesis_prime/content/creature_kind as content_creature_kind
import genesis_prime/dev_database
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
import gleam/dict.{type Dict}
import gleam/int
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
  Counts(inserted: Int, changed: Int, removed: Int, unchanged: Int)
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
  )
}

pub fn main() -> Nil {
  dev_database.finish(result: run(), describe:)
}

fn run() -> Result(String, Failure) {
  let list_all = list.contains(argv.load().arguments, "--list")
  use folder <- result.try(
    envoy.get("GENESIS_JABBITHOLE_DIR") |> result.replace_error(NoRecord),
  )
  use db <- result.try(dev_database.connect() |> result.map_error(Database))
  use pages <- result.try(read_pages(folder:))
  use language <- result.try(read_language())
  use tables <- result.try(
    table.read(from: table_folder.path())
    |> result.map_error(TablesUnreadable),
  )
  use spawned <- result.try(read_spawned(db:))
  use kind_rows <- result.try(
    content_creature_kind.rows(db)
    |> result.map_error(fn(error) { Database(dev_database.failure_of(error:)) }),
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
  use #(auto_counts, special_counts) <- result.map(write(db:, autos:, specials:))
  report(Done(
    outcomes:,
    names: names_of(texts:, tables:, outcomes:),
    autos: auto_counts,
    specials: special_counts,
    list_all:,
  ))
}

fn read_pages(
  folder folder: String,
) -> Result(List(jabbithole_page.Page), Failure) {
  let file = folder <> "/npcs.jsonl"
  use text <- result.try(
    simplifile.read(file)
    |> result.map_error(fn(error) {
      Unreadable(file:, reason: simplifile.describe_error(error))
    }),
  )
  jabbithole_page.read(text:) |> result.map_error(RecordRefused)
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
  use returned <- result.map(
    sql.spawned_creatures(db)
    |> result.map_error(fn(error) { Database(dev_database.failure_of(error:)) }),
  )
  returned.rows
  |> list.filter(fn(row) {
    result.is_ok(creature_unit_type.of_entity_type(entity_type: row.entity_type))
  })
  |> list.map(fn(row) {
    retail_creature_spell.Spawned(
      creature_id: row.creature_id,
      world_id: row.world_id,
      area_id: row.area_id,
      spawns: row.spawns,
    )
  })
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

/// Writes the rows in one transaction, giving how the two tables' retail-record rows
/// stood before.
fn write(
  db db: pog.Connection,
  autos autos: List(Auto),
  specials specials: List(Special),
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
        |> result.map_error(failure_of),
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
        |> result.map_error(failure_of),
      )
      use _deleted <- result.try(
        sql.delete_stale_auto_attacks(
          tx,
          auto_columns(fn(row) { row.creature_id }),
          auto_columns(fn(row) { row.spell4_id }),
          auto_columns(fn(row) { row.order_index }),
          auto_columns(fn(row) { row.reason }),
        )
        |> result.map_error(failure_of),
      )
      use _deleted <- result.try(
        sql.delete_stale_specials(
          tx,
          special_columns(fn(row) { row.creature_id }),
          special_columns(fn(row) { row.spell4_id }),
          special_columns(fn(row) { row.order_index }),
          special_columns(fn(row) { row.cooldown_ms }),
          special_columns(fn(row) { row.reason }),
        )
        |> result.map_error(failure_of),
      )
      use _inserted <- result.try(
        sql.insert_new_auto_attacks(
          tx,
          auto_columns(fn(row) { row.creature_id }),
          auto_columns(fn(row) { row.spell4_id }),
          auto_columns(fn(row) { row.order_index }),
          auto_columns(fn(row) { row.reason }),
        )
        |> result.map_error(failure_of),
      )
      use _inserted <- result.try(
        sql.insert_new_specials(
          tx,
          special_columns(fn(row) { row.creature_id }),
          special_columns(fn(row) { row.spell4_id }),
          special_columns(fn(row) { row.order_index }),
          special_columns(fn(row) { row.cooldown_ms }),
          special_columns(fn(row) { row.reason }),
        )
        |> result.map_error(failure_of),
      )
      Ok(#(
        first_row(counted_autos.rows, fn(row) {
          Counts(
            inserted: row.inserted,
            changed: row.changed,
            removed: row.removed,
            unchanged: row.unchanged,
          )
        }),
        first_row(counted_specials.rows, fn(row) {
          Counts(
            inserted: row.inserted,
            changed: row.changed,
            removed: row.removed,
            unchanged: row.unchanged,
          )
        }),
      ))
    },
  )
  |> result.map_error(fn(error) {
    case error {
      dev_database.Undone(failure) -> failure
      dev_database.NoConnection -> Database(dev_database.DatabaseDown)
      dev_database.Failed(error) -> failure_of(error)
      dev_database.NotAPool ->
        Database(dev_database.NotChanged(
          "the import needs a pool of connections, not one connection",
        ))
    }
  })
}

/// The statements the transaction runs, for its deadline: six, each allowed pog's own
/// query timeout, and the transaction's own begin and commit.
const statements = 8

fn first_row(rows: List(row), counts: fn(row) -> Counts) -> Counts {
  case rows {
    [row, ..] -> counts(row)
    [] -> Counts(inserted: 0, changed: 0, removed: 0, unchanged: 0)
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
  <> ", removed "
  <> int.to_string(counts.removed)
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
