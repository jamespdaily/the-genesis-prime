//// The coverage measure as Markdown: one checklist per engine, to post on its
//// area issue and on the milestone's issue.

import genesis_prime/coverage/engine.{type EngineDeclaration}
import genesis_prime/coverage/measurement.{
  type Measurement, type TypeLine, DecodedMissing, Handled, Measured, NotDecoded,
  Unmeasured,
}
import gleam/float
import gleam/int
import gleam/list
import gleam/string

/// What the marks of a type line say.
pub const legend =
  "Marks: [x] handled by a rule of the server; [~] the client's code was read for the type and the server does not handle it (what it lacks, and the fact file's key); [ ] the client's code was not read for the type. \"In the starting abilities\": the rows of the type among the spells the 18 level-1 abilities' trees reach, gated children included."

/// The Markdown of every engine's measure: a heading, the source and totals,
/// then one line per type, heaviest first: `- [ ] type N: R rows (S%)`, with
/// `[x]` when the engine handles the type and `[~]` when the client's code was
/// read for it and the engine does not handle it, followed by what it lacks and
/// the fact file's key. A type the starting abilities use has the rows it has
/// among them on its line.
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
      let handled = list.filter(types, fn(line) { line.status == Handled })
      let missing =
        list.count(types, fn(line) {
          case line.status {
            DecodedMissing(..) -> True
            Handled | NotDecoded -> False
          }
        })
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
        <> case missing {
          0 -> ""
          _ -> "; " <> int.to_string(missing) <> " decoded and missing"
        }
        <> starting_summary(types)
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
      "the message ids the client sends to the server, one row for each id"
  }
}

fn evidence(engine: EngineDeclaration) -> String {
  case engine.source {
    engine.TableColumns(evidence:, ..)
    | engine.Cases(evidence:, ..)
    | engine.CasesNotRecorded(evidence:, ..) -> evidence
  }
}

/// The starting abilities' rows the engine handles, over all of theirs, when the
/// engine's types are used by them: `; starting abilities: H of R rows handled`.
fn starting_summary(types: List(TypeLine)) -> String {
  let #(handled, all) = starting_rows(types)
  case all {
    0 -> ""
    _ ->
      "; starting abilities: "
      <> int.to_string(handled)
      <> " of "
      <> int.to_string(all)
      <> " rows handled"
  }
}

/// The rows the starting abilities hold of the handled types, and of all types.
fn starting_rows(types: List(TypeLine)) -> #(Int, Int) {
  list.fold(types, #(0, 0), fn(totals, line) {
    let #(handled, all) = totals
    case line.status {
      Handled -> #(
        handled + line.starting_abilities,
        all + line.starting_abilities,
      )
      DecodedMissing(..) | NotDecoded -> #(
        handled,
        all + line.starting_abilities,
      )
    }
  })
}

fn type_line(line: TypeLine) -> String {
  let mark = case line.status {
    Handled -> "x"
    DecodedMissing(..) -> "~"
    NotDecoded -> " "
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
  <> case line.starting_abilities {
    0 -> ""
    rows ->
      ", "
      <> count_of(count: rows, singular: "row", plural: "rows")
      <> " in the starting abilities"
  }
  <> case line.status {
    DecodedMissing(reason:, fact_key:) ->
      "; decoded, not handled: " <> reason <> " (" <> fact_key <> ")"
    Handled | NotDecoded -> ""
  }
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
/// zero values left out, the types handled and the starting abilities' rows
/// handled. An engine whose types are not recorded is "not measured".
pub fn totals(measurements: List(Measurement)) -> String {
  let rows =
    list.map(measurements, fn(measurement) {
      case measurement {
        Unmeasured(engine:, ..) ->
          "| " <> engine_title(engine) <> " | not measured | | | | |"
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
          <> int.to_string(
            list.count(types, fn(line) { line.status == Handled }),
          )
          <> " | "
          <> starting_column(types)
          <> " |"
      }
    })
  string.join(
    [
      "| Engine | Types in use | Rows | Zero values | Types handled | Starting abilities' rows handled |",
      "| --- | --- | --- | --- | --- | --- |",
      ..rows
    ],
    "\n",
  )
}

/// `H of R` for the starting abilities' rows, or nothing for an engine they do not
/// use.
fn starting_column(types: List(TypeLine)) -> String {
  let #(handled, all) = starting_rows(types)
  case all {
    0 -> ""
    _ -> int.to_string(handled) <> " of " <> int.to_string(all)
  }
}
