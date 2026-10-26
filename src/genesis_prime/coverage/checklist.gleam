//// The coverage measure as Markdown: one checklist per engine, to post on its
//// area issue and on the milestone's issue.

import genesis_prime/coverage/engine.{type EngineDeclaration}
import genesis_prime/coverage/measurement.{
  type Measurement, type TypeLine, Measured, Unmeasured,
}
import gleam/float
import gleam/int
import gleam/list
import gleam/string

/// The Markdown of every engine's measure: a heading, the source and totals,
/// then one line per type, heaviest first: `- [ ] type N: R rows (S%)`, with
/// `[x]` when the engine handles the type.
pub fn render(measurements: List(Measurement)) -> String {
  measurements
  |> list.map(render_engine)
  |> string.join("\n\n")
}

fn render_engine(measurement: Measurement) -> String {
  let heading = heading(measurement.engine)
  case measurement {
    Unmeasured(engine:, needed:) ->
      string.join(
        [
          heading,
          "Evidence: " <> evidence(engine) <> ".",
          "Not measured: " <> needed <> ".",
        ],
        "\n\n",
      )
    Measured(engine:, types:, rows:, zero_values:, ..) -> {
      let handled = list.filter(types, fn(line) { line.handled })
      let handled_rows =
        list.fold(handled, 0, fn(total, line) { total + line.rows })
      let summary =
        count_of(count: rows, singular: "row", plural: "rows")
        <> " over "
        <> count_of(
          count: list.length(types),
          singular: "type",
          plural: "types",
        )
        <> "; "
        <> count_of(
          count: zero_values,
          singular: "zero value",
          plural: "zero values",
        )
        <> " left out; "
        <> int.to_string(list.length(handled))
        <> " of "
        <> int.to_string(list.length(types))
        <> " types handled ("
        <> percent(share_of(handled_rows, rows))
        <> " of rows)"
      string.join(
        [
          heading,
          "Type: "
            <> source_columns(engine)
            <> ". Evidence: "
            <> evidence(engine)
            <> ".",
          summary,
          string.join(list.map(types, type_line), "\n"),
        ],
        "\n\n",
      )
    }
  }
}

fn heading(engine: EngineDeclaration) -> String {
  "## " <> engine_title(engine)
}

fn engine_title(engine: EngineDeclaration) -> String {
  engine.name <> " (#" <> int.to_string(engine.area_issue) <> ")"
}

fn source_columns(engine: EngineDeclaration) -> String {
  case engine.source {
    engine.TableColumns(table:, columns:, ..) ->
      list.map(columns, fn(column) { table <> "." <> column })
      |> string.join(", ")
    engine.Cases(..) | engine.CasesNotRecorded(..) ->
      "the message ids with a case in the client's dispatcher"
  }
}

fn evidence(engine: EngineDeclaration) -> String {
  case engine.source {
    engine.TableColumns(evidence:, ..)
    | engine.Cases(evidence:, ..)
    | engine.CasesNotRecorded(evidence:, ..) -> evidence
  }
}

fn type_line(line: TypeLine) -> String {
  let mark = case line.handled {
    True -> "x"
    False -> " "
  }
  "- ["
  <> mark
  <> "] type "
  <> int.to_string(line.type_number)
  <> ": "
  <> count_of(count: line.rows, singular: "row", plural: "rows")
  <> " ("
  <> percent(line.share)
  <> ")"
}

fn count_of(
  count count: Int,
  singular singular: String,
  plural plural: String,
) -> String {
  case count {
    1 -> "1 " <> singular
    _ -> int.to_string(count) <> " " <> plural
  }
}

fn share_of(part: Int, whole: Int) -> Float {
  case whole {
    0 -> 0.0
    _ -> int.to_float(part) /. int.to_float(whole)
  }
}

/// A share from 0.0 to 1.0 as a percentage to two decimals, such as `12.5%`.
fn percent(share: Float) -> String {
  float.to_string(float.to_precision(share *. 100.0, 2)) <> "%"
}

/// A Markdown table with a row per engine: the types in use, the rows, the
/// zero values left out and the types handled. An engine whose types are not
/// recorded is "not measured".
pub fn totals(measurements: List(Measurement)) -> String {
  let rows =
    list.map(measurements, fn(measurement) {
      case measurement {
        Unmeasured(engine:, ..) ->
          "| " <> engine_title(engine) <> " | not measured | | | |"
        Measured(engine:, types:, rows:, zero_values:, ..) ->
          "| "
          <> engine_title(engine)
          <> " | "
          <> int.to_string(list.length(types))
          <> " | "
          <> int.to_string(rows)
          <> " | "
          <> int.to_string(zero_values)
          <> " | "
          <> int.to_string(list.count(types, fn(line) { line.handled }))
          <> " |"
      }
    })
  string.join(
    [
      "| Engine | Types in use | Rows | Zero values | Types handled |",
      "| --- | --- | --- | --- | --- |",
      ..rows
    ],
    "\n",
  )
}
