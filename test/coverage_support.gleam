//// What the coverage tests share: a fact file's keys, the engine declarations by
//// name, and the run's measures of the client's tables.

import client_tables
import database_support
import genesis_prime/coverage/engine.{type EngineDeclaration, type Missing}
import genesis_prime/coverage/measurement.{
  type Measurement, type TypeLine, HandledWithGap, Measured,
}
import genesis_prime/coverage/starting_ability.{type LeftOut}
import gleam/int
import gleam/list
import gleam/string
import simplifile

/// Whether the fact file's text holds a record under `key`.
pub fn has_record(facts facts: String, key key: String) -> Bool {
  string.contains(facts, "[\"" <> key <> "\"]")
}

/// The text of the client's fact file, read once for the run.
pub fn fact_file() -> String {
  database_support.once("coverage_fact_file", fn() {
    let assert Ok(text) =
      simplifile.read(
        ".claude/skills/decoding-the-client/references/client-facts.toml",
      )
      as "the fact file is in the repository"
    text
  })
}

/// Checks each gap in `gaps` (the partial or the missing list of `declared`): it states a
/// reason, cites a record the fact file holds, and the engine handles its type exactly
/// when `handled` is True.
pub fn assert_gaps_stated(
  declared declared: EngineDeclaration,
  gaps gaps: List(Missing),
  handled handled: Bool,
) -> Nil {
  let facts = fact_file()
  list.each(gaps, fn(gap) {
    let label = declared.name <> " type " <> int.to_string(gap.type_number)
    assert gap.reason != "" as { label <> ": a reason" }
    assert has_record(facts:, key: gap.fact_key)
      as { label <> ": the fact file holds no record " <> gap.fact_key }
    assert engine.handles(engine: declared, type_number: gap.type_number)
      == handled
      as { label <> ": the engine's handling disagrees with the list it is in" }
  })
}

/// The engine declaration named `name`.
pub fn engine_named(name: String) -> EngineDeclaration {
  let assert Ok(found) =
    list.find(engine.all(), fn(declaration) { declaration.name == name })
    as { "no engine is named " <> name }
  found
}

/// The measure of the engine named `engine_name` over the client's tables, taken once
/// per run and shared by every test that reads it. Callers sit behind
/// `client_tables.present()`: it reads `client_tables.every_table()`, which panics under
/// `GENESIS_NO_CLIENT=1`. A test that measures a changed declaration calls
/// `measurement.measure` itself.
pub fn measured(engine_name: String) -> Measurement {
  database_support.once("coverage_measured_" <> engine_name, fn() {
    measurement.measure(engine_named(engine_name), client_tables.every_table())
  })
}

/// The parts of the starting abilities' trees the measure leaves out, over the client's
/// tables, taken once per run (`starting_ability.left_out` takes over a second). Callers
/// sit behind `client_tables.present()`, as for `measured`.
pub fn left_out() -> List(LeftOut) {
  database_support.once("coverage_left_out", fn() {
    let assert Ok(parts) =
      starting_ability.left_out(tables: client_tables.every_table())
      as "the client's tables hold the rows the walk names"
    parts
  })
}

/// The line of type `type_number` in the cached measure of the engine named
/// `engine_name`, after checking it is handled with a stated gap and that its counts
/// are bounded by its rows: `0 <= unread <= rows` and
/// `starting_unread <= starting_abilities <= rows`. The gap's reason and fact key are
/// copied from the declaration by `measurement.status_of`, so they are not compared.
/// Callers sit behind `client_tables.present()`, as for `measured`.
pub fn partial_line(
  engine_name engine_name: String,
  type_number type_number: Int,
) -> TypeLine {
  let label = engine_name <> " type " <> int.to_string(type_number)
  let assert Measured(types:, ..) = measured(engine_name)
    as "the engine's source is a table"
  let assert Ok(line) =
    list.find(types, fn(line) { line.type_number == type_number })
    as { label <> " is in use" }
  let assert HandledWithGap(unread_rows:, ..) = line.status
    as { label <> " is handled with a stated gap" }
  assert unread_rows >= 0 && unread_rows <= line.rows
    as { label <> ": the unread rows are within its rows" }
  assert line.starting_unread <= line.starting_abilities
    && line.starting_abilities <= line.rows
    as {
      label <> ": the starting rows are within its rows, the unread among them"
    }
  line
}
