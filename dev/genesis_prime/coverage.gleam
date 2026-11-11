//// Prints the coverage measure: for each engine, the types the client's
//// tables use, heaviest first, against the types the engine handles.
////
//// `gleam run -m genesis_prime/coverage` loads the client's tables from
//// `GENESIS_TABLE_DIR` (else `GENESIS_HOME`/tables, else
//// `~/.genesis-prime/tables`) and prints a Markdown checklist per engine: each
//// type is handled, decoded and missing (with what it lacks and the fact file's
//// key), or not decoded, beside the rows it has in the whole game and in the
//// starting abilities' spells. It exits with 1 when the tables do not load, an
//// engine declares a type no row uses, an engine both handles a type and
//// lists it as missing, an engine handles a type with rows no rule reads and states no
//// gap for it, or a starting ability's tree names a Spell4 or Prerequisite row the tables
//// lack.
////
//// It then lists the parts of the starting abilities' trees the starting abilities'
//// column leaves out, each with why: a Prerequisite only a runner column names, and
//// a Proxy's child behind a gate a level-1 character cannot open
//// (genesis_prime/coverage/starting_ability).
////
//// It then lists the spells the reached spells' tooltips name that no row reaches, with the
//// server's Proxies (the play database's server_proxy table) planted into the trees, and a
//// count line under the totals (genesis_prime/coverage/named_unreached). A play database,
//// a Proxy row or the committed token list (test/fixture/tooltip_tokens/tokens.tsv) the
//// measure cannot take is said in place of the list and counts as a breach.
////
//// It then prints the coverage of the world's spawns, a line for each world: how
//// many start as fight creatures, how many NonPlayer rows are left out and why,
//// and how many rows each other entity type has (genesis_prime/world_map/spawn,
//// the same function the server's load logs). The spawns are those of the play
//// database (PGHOST, PGPORT, PGUSER, PGPASSWORD and PGDATABASE); when it cannot be
//// read the tool says so and goes on.
////
//// The measure's own tests (`test/coverage_*_test.gleam`) read the client's
//// tables and are not part of `./check`: whoever changes the measure runs them
//// with `gleam test -- --tag coverage`.

import genesis_prime/content/creature_faction as content_creature_faction
import genesis_prime/content/creature_kind as content_creature_kind
import genesis_prime/content/refusal
import genesis_prime/content/server_proxy as content_server_proxy
import genesis_prime/content/spawn as content_spawn
import genesis_prime/coverage/checklist
import genesis_prime/coverage/engine
import genesis_prime/coverage/measurement.{type Measurement, Measured}
import genesis_prime/coverage/named_unreached
import genesis_prime/coverage/starting_ability
import genesis_prime/dev_database
import genesis_prime/dev_exit
import genesis_prime/game/rating
import genesis_prime/game/server_proxy
import genesis_prime/game/spell_plan
import genesis_prime/game/vendor
import genesis_prime/store/worker
import genesis_prime/table
import genesis_prime/table/loader/store
import genesis_prime/table_folder
import genesis_prime/tooltip_token
import genesis_prime/world_map/creature_faction
import genesis_prime/world_map/creature_kind
import genesis_prime/world_map/spawn
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import pog
import simplifile

/// Runs the measure.
pub fn main() -> Nil {
  let folder = table_folder.path()
  case table.read(from: folder) {
    Error(error) -> {
      io.println(
        "the client's tables did not load from "
        <> folder
        <> ": "
        <> describe(error)
        <> "; run python3.13 -I setup_check/extract_tables.py",
      )
      dev_exit.halt(1)
    }
    Ok(tables) -> {
      let measurements =
        list.map(engine.all(), fn(declared) {
          measurement.measure(declared, tables)
        })
      let left_out = left_out_report(tables:)
      let named = named_by_tooltips(tables:)
      let spawns = spawn_coverage(tables:)
      io.println(checklist.totals(measurements))
      io.println("")
      io.println(case named {
        Ok(#(count, _)) -> count
        Error(why) -> describe_named_failure(why)
      })
      io.println("")
      io.println(checklist.legend)
      io.println("")
      io.println(checklist.render(measurements))
      io.println("")
      io.println(left_out)
      io.println("")
      io.println(case named {
        Ok(#(_, named_list)) -> named_list
        Error(why) -> describe_named_failure(why)
      })
      io.println("")
      io.println(spawns)
      let found = case named {
        Ok(_) -> breaches(measurements)
        Error(why) ->
          list.append(breaches(measurements), [describe_named_failure(why)])
      }
      case found {
        [] -> Nil
        _ -> {
          list.each(found, io.println)
          dev_exit.halt(1)
        }
      }
    }
  }
}

/// A line for each part of the starting abilities' trees the counts leave out, with
/// why, so a reader can audit the starting abilities' column.
pub fn left_out_report(tables tables: store.Tables) -> String {
  case starting_ability.left_out(tables:) {
    Error(missing) ->
      "Starting abilities, left out of the counts above: not listed, "
      <> string.join(list.map(missing, starting_ability.describe), "; ")
    Ok(parts) ->
      string.join(
        [
          "Starting abilities, left out of the counts above:",
          ..list.map(parts, fn(part) {
            "- " <> starting_ability.describe_left_out(left_out: part)
          })
        ],
        "\n",
      )
  }
}

/// Why the list of tooltip-named spells cannot be made.
type NamedFailure {
  TokenListRefused(tooltip_token.ListError)
  DatabaseUnavailable(dev_database.Failure)
  ProxyTableUnreadable(pog.QueryError)
  ProxiesRefused(List(refusal.Refusal))
  RowsMissing(List(starting_ability.MissingRow))
}

fn describe_named_failure(failure: NamedFailure) -> String {
  case failure {
    TokenListRefused(error) -> tooltip_token.describe_error(error)
    DatabaseUnavailable(failure) ->
      "The tooltip list needs the play database: "
      <> dev_database.describe(failure, "read the server's Proxies")
    ProxyTableUnreadable(error) ->
      "The tooltip list needs the server_proxy table (run the migrations on the play database): "
      <> worker.describe_query_error(error)
    ProxiesRefused(refusals) ->
      "The tooltip list needs Proxies the load takes: "
      <> string.join(list.map(refusals, refusal.describe), "; ")
    RowsMissing(missing) ->
      "The tooltip list needs rows the tables lack: "
      <> string.join(list.map(missing, starting_ability.describe), "; ")
  }
}

/// The count line and the list of the spells the reached spells' tooltips name that no row
/// reaches, or why they cannot be made: the play database, its Proxy rows, the token list
/// or the walk. The reached spells are those of the trees with the server's Proxies
/// planted, as the server's load plants them.
fn named_by_tooltips(
  tables tables: store.Tables,
) -> Result(#(String, String), NamedFailure) {
  named_find(tables:)
  |> result.map(fn(named) {
    #(
      named_unreached.count_line(named:),
      named_unreached.report(tables:, named:),
    )
  })
}

fn named_find(
  tables tables: store.Tables,
) -> Result(named_unreached.Named, NamedFailure) {
  use tokens <- result.try(
    tooltip_token.load() |> result.map_error(TokenListRefused),
  )
  use db <- result.try(
    dev_database.connect() |> result.map_error(DatabaseUnavailable),
  )
  use rows <- result.try(
    content_server_proxy.rows(db) |> result.map_error(ProxyTableUnreadable),
  )
  let plans = spell_plan.plans(tables:)
  use selected <- result.try(
    server_proxy.select(rows:, tables:, plans:)
    |> result.map_error(ProxiesRefused),
  )
  let plans = server_proxy.planted_into(plans:, proxies: selected)
  use reached <- result.try(
    starting_ability.spells_in(tables:, plans:)
    |> result.map_error(RowsMissing),
  )
  use left_out <- result.map(
    starting_ability.left_out(tables:) |> result.map_error(RowsMissing),
  )
  named_unreached.find(
    tables:,
    tokens:,
    reached: list.map(reached, fn(spell) { spell.spell4_id.value }),
    left_out:,
  )
}

/// The coverage of the play database's spawns, a line for each world, or why it
/// cannot be measured, from the client's tables, which hold every table the
/// selection reads.
fn spawn_coverage(tables tables: store.Tables) -> String {
  case dev_database.connect() {
    Error(failure) ->
      "The spawn coverage needs the play database: "
      <> dev_database.describe(failure, "read the spawns")
    Ok(db) ->
      case content_spawn.rows(db) {
        Error(error) ->
          "The spawn coverage needs the spawn table (run the migrations and the import on the play database): "
          <> worker.describe_query_error(error)
        Ok(rows) ->
          case
            rating.build(tables:),
            content_creature_kind.rows(db)
            |> result.map(fn(kind_rows) {
              creature_kind.select(rows: kind_rows, tables:)
            }),
            content_creature_faction.rows(db)
            |> result.map(fn(faction_rows) {
              creature_faction.select(rows: faction_rows, tables:)
            })
          {
            Error(error), _, _ -> rating.describe(error:)
            Ok(_), Error(error), _ ->
              "The spawn coverage needs the creature_kind table: "
              <> worker.describe_query_error(error)
            Ok(_), Ok(Error(refusals)), _ ->
              "The spawn coverage needs creature kinds the load takes: "
              <> string.join(list.map(refusals, refusal.describe), "; ")
            Ok(_), Ok(_), Error(error) ->
              "The spawn coverage needs the creature_faction table: "
              <> worker.describe_query_error(error)
            Ok(_), Ok(_), Ok(Error(refusals)) ->
              "The spawn coverage needs creature factions the load takes: "
              <> string.join(list.map(refusals, refusal.describe), "; ")
            Ok(formulas), Ok(Ok(kinds)), Ok(Ok(factions)) ->
              string.join(
                [
                  "Spawns that start, by world:",
                  ..list.map(
                    spawn.select(
                      rows:,
                      tables:,
                      formulas:,
                      kinds:,
                      factions:,
                      vendors: vendor.none(),
                    ).coverage,
                    fn(coverage) { "- " <> spawn.describe_coverage(coverage:) },
                  )
                ],
                "\n",
              )
          }
      }
  }
}

/// A line for each engine that declares a type no row uses, one for each that
/// both handles a type and lists it as missing or lists as partial a type it does not
/// handle, one for each type it handles with rows no rule reads and no gap stated, and one
/// for each that names a row of a starting ability's tree the client's tables lack.
pub fn breaches(measurements: List(Measurement)) -> List(String) {
  list.flat_map(measurements, fn(measured) {
    case measured {
      Measured(engine:, breaches:, conflicts:, missing_rows:, types:, ..) ->
        list.flatten([
          list.filter_map(types, fn(line) {
            case line.status {
              measurement.HandledWithUnstatedGap(unread_rows:) ->
                Ok(
                  engine.name
                  <> " handles type "
                  <> int.to_string(line.type_number)
                  <> " with "
                  <> int.to_string(unread_rows)
                  <> " of its "
                  <> int.to_string(line.rows)
                  <> " rows not read and states no gap for it",
                )
              measurement.Handled
              | measurement.HandledWithGap(..)
              | measurement.DecodedMissing(..)
              | measurement.NotDecoded -> Error(Nil)
            }
          }),
          case breaches {
            [] -> []
            unused -> [
              engine.name
              <> " declares types no row uses: "
              <> string.join(list.map(unused, int.to_string), ", "),
            ]
          },
          case conflicts {
            [] -> []
            both -> [
              engine.name
              <> " lists as missing a type it handles, or as partial a type it does not handle: "
              <> string.join(list.map(both, int.to_string), ", "),
            ]
          },
          case missing_rows {
            [] -> []
            lacking -> [
              engine.name
              <> " reaches rows the client's tables lack: "
              <> string.join(
                list.map(lacking, fn(row) { starting_ability.describe(row) }),
                "; ",
              ),
            ]
          },
        ])
      measurement.Unmeasured(..) -> []
    }
  })
}

fn describe(error: store.LoadError) -> String {
  case error {
    store.TableFileUnreadable(file:, reason:) ->
      file <> ".tbl cannot be read: " <> simplifile.describe_error(reason)
    store.TableFolderUnreadable(folder:, reason:) ->
      folder <> " cannot be listed: " <> simplifile.describe_error(reason)
    store.TableFileInvalid(table:, ..) ->
      table <> ".tbl is not accepted as the " <> table <> " table"
    store.RowMissing(from_table:, column:, to_table:, id:) ->
      from_table
      <> "."
      <> column
      <> " names "
      <> to_table
      <> " id "
      <> int.to_string(id)
      <> ", which has no row"
    store.DerivationFailed(name:, reason:) ->
      name <> " cannot be built: " <> reason
  }
}
