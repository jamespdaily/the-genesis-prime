//// The relay table rule. Expected value is the rule: `genesis_prime/world_map/relay` is
//// the one table of what a creature tells a player and a player tells a creature through
//// the map, so each variant of `Payload` and of `Inbound` has a row in the module's doc
//// table (its kind, destination check and source check) and one arm of its own in
//// `kind_of` or `inbound_kind_of`, which gives that kind. A variant with no row or no arm
//// of its own, and a row for no variant, is a breach. The rule is shown on a planted file,
//// then read over the real one.

import code_rule/planted
import code_rule/source.{type SourceFile, SourceFile}
import code_rule/syntax
import glance
import gleam/bool
import gleam/list
import gleam/result
import gleam/string
import owned_test
import unitest

const relay_path = "src/genesis_prime/world_map/relay.gleam"

/// The types the table has a row for each variant of, with the function that gives each
/// variant's kind.
const tables = [#("Payload", "kind_of"), #("Inbound", "inbound_kind_of")]

/// The names of the variants of the table's types.
fn variants(file file: SourceFile) -> List(String) {
  syntax.parse(file).custom_types
  |> list.filter(fn(definition) {
    list.any(tables, fn(table) { table.0 == definition.definition.name })
  })
  |> list.flat_map(fn(definition) {
    list.map(definition.definition.variants, fn(variant) { variant.name })
  })
}

/// The names the module's doc table has a row for: the backticked first cell of each
/// row of the module's `////` lines.
fn tabled(file file: SourceFile) -> List(String) {
  string.split(file.text, "\n")
  |> list.filter_map(fn(line) {
    case string.starts_with(line, "//// | `") {
      True ->
        case string.split(string.drop_start(line, 8), "`") {
          [name, ..] -> Ok(name)
          [] -> Error(Nil)
        }
      False -> Error(Nil)
    }
  })
}

/// The variants each arm of the kind functions names, one list for each arm.
fn arms(file file: SourceFile) -> List(List(String)) {
  syntax.parse(file).functions
  |> list.filter(fn(definition) {
    list.any(tables, fn(table) { table.1 == definition.definition.name })
  })
  |> list.flat_map(fn(definition) { definition.definition.body })
  |> list.flat_map(fn(statement) {
    case statement {
      glance.Expression(glance.Case(clauses:, ..)) ->
        list.map(clauses, fn(clause) {
          list.flatten(clause.patterns)
          |> list.filter_map(constructor_of)
        })
      glance.Expression(_)
      | glance.Use(..)
      | glance.Assignment(..)
      | glance.Assert(..) -> []
    }
  })
}

/// The variant a pattern names, when it names one.
fn constructor_of(pattern: glance.Pattern) -> Result(String, Nil) {
  case pattern {
    glance.PatternVariant(constructor:, ..) -> Ok(constructor)
    glance.PatternInt(..)
    | glance.PatternFloat(..)
    | glance.PatternString(..)
    | glance.PatternDiscard(..)
    | glance.PatternVariable(..)
    | glance.PatternTuple(..)
    | glance.PatternList(..)
    | glance.PatternAssignment(..)
    | glance.PatternConcatenate(..)
    | glance.PatternBitString(..) -> Error(Nil)
  }
}

/// Whether the source-check cell of each `Inbound` row of the doc table says there is
/// none (it starts "none"), by the variant's name.
fn tabled_without_sender_check(file file: SourceFile) -> List(#(String, Bool)) {
  let inbound = inbound_variants(file:)
  string.split(file.text, "\n")
  |> list.filter_map(fn(line) {
    use <- bool.guard(
      when: !string.starts_with(line, "//// | `"),
      return: Error(Nil),
    )
    use name <- result.try(
      string.split(string.drop_start(line, 8), "`") |> list.first,
    )
    use source <- result.map(
      string.split(string.trim_end(line), " | ") |> list.last,
    )
    #(name, string.starts_with(source, "none"))
  })
  |> list.filter(fn(row) { list.contains(inbound, row.0) })
}

/// The `Inbound` variants of the file.
fn inbound_variants(file file: SourceFile) -> List(String) {
  syntax.parse(file).custom_types
  |> list.filter(fn(definition) { definition.definition.name == "Inbound" })
  |> list.flat_map(fn(definition) {
    list.map(definition.definition.variants, fn(variant) { variant.name })
  })
}

/// Whether the arm of each variant in `inbound_kind_of` gives `NoSenderCheck`, by the
/// variant's name: read from the line that follows each `Name(..) ->`.
fn armed_without_sender_check(file file: SourceFile) -> List(#(String, Bool)) {
  let lines =
    string.split(file.text, "\n")
    |> list.drop_while(fn(line) {
      !string.starts_with(line, "pub fn inbound_kind_of")
    })
  list.zip(lines, list.drop(lines, 1))
  |> list.filter_map(fn(pair) {
    let #(line, next) = pair
    case string.ends_with(string.trim(line), "(..) ->") {
      True ->
        Ok(#(
          string.replace(string.trim(line), "(..) ->", ""),
          string.contains(next, "source: NoSenderCheck"),
        ))
      False -> Error(Nil)
    }
  })
}

/// What the file breaks: a variant with no table row, a row for no variant, and a
/// variant that has no arm of its own in `kind_of`.
fn breaches(file file: SourceFile) -> List(String) {
  let named = variants(file:)
  let rows = tabled(file:)
  let arms = arms(file:)
  list.flatten([
    list.filter(named, fn(name) { !list.contains(rows, name) })
      |> list.map(fn(name) { "no table row for " <> name }),
    list.filter(rows, fn(name) { !list.contains(named, name) })
      |> list.map(fn(name) { "a table row for no variant: " <> name }),
    list.filter(named, fn(name) { !list.contains(arms, [name]) })
      |> list.map(fn(name) {
        "no arm of its own in its kind function for " <> name
      }),
    list.filter(tabled_without_sender_check(file:), fn(row) {
      list.key_find(armed_without_sender_check(file:), row.0)
      |> result.map(fn(armed) { armed != row.1 })
      == Ok(True)
    })
      |> list.map(fn(row) {
        "the source check of "
        <> row.0
        <> " differs between its row and its arm"
      }),
  ])
}

pub fn the_relay_table_has_one_row_for_each_payload_and_each_row_names_its_destination_and_source_check_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let planted_file =
    planted.file(path: relay_path, lines: [
      "//// | Payload | Kind | Destination check | Source check |",
      "//// |---|---|---|---|",
      "//// | `News` | news | stay | none |",
      "//// | `Gone` | a row for no variant | stay | none |",
      "//// | `Strike` | a player's strike | the creature | the sender is a player of the map |",
      "",
      "pub type Payload {",
      "  News(a: Int)",
      "  Struck(a: Int)",
      "  Credit(a: Int)",
      "}",
      "",
      "pub type Inbound {",
      "  Strike(a: Int)",
      "  TargetMoved(a: Int)",
      "  Despawn(a: Int)",
      "}",
      "",
      "pub fn kind_of(payload: Payload) -> Int {",
      "  case payload {",
      "    News(..) -> 1",
      "    Struck(..) | Credit(..) -> 2",
      "  }",
      "}",
      "",
      "pub fn inbound_kind_of(inbound: Inbound) -> Int {",
      "  case inbound {",
      "    Strike(..) ->",
      "      InboundKind(destination: RunningCreature, source: NoSenderCheck)",
      "    TargetMoved(..) | Despawn(..) -> 2",
      "  }",
      "}",
    ])
  assert breaches(file: planted_file)
    == [
      "no table row for TargetMoved",
      "no table row for Despawn",
      "no table row for Struck",
      "no table row for Credit",
      "a table row for no variant: Gone",
      "no arm of its own in its kind function for TargetMoved",
      "no arm of its own in its kind function for Despawn",
      "no arm of its own in its kind function for Struck",
      "no arm of its own in its kind function for Credit",
      "the source check of Strike differs between its row and its arm",
    ]
    as "a variant of either type with no row, a row for no variant, a variant sharing an arm and a row whose source check is not its arm's are each found"
  assert breaches(file: SourceFile(
      path: relay_path,
      text: source.read(relay_path),
    ))
    == []
    as "each payload and each inbound tell of the relay has a row in the table and an arm of its own in its kind function"
}
