//// The relay table rule. Expected value is the rule: `genesis_prime/world_map/relay` is
//// the one table of what a creature tells a player through its map, so each variant of
//// `Payload` has a row in the module's doc table (its kind, destination check and source
//// check) and one arm of its own in `kind_of`, which gives that kind. A variant with no
//// row or no arm of its own, and a row for no variant, is a breach. The rule is shown on
//// a planted file, then read over the real one.

import code_rule/planted
import code_rule/source.{type SourceFile, SourceFile}
import code_rule/syntax
import glance
import gleam/list
import gleam/string
import owned_test
import unitest

const relay_path = "src/genesis_prime/world_map/relay.gleam"

/// The names of the variants of the type `Payload`.
fn variants(file file: SourceFile) -> List(String) {
  syntax.parse(file).custom_types
  |> list.filter(fn(definition) { definition.definition.name == "Payload" })
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

/// The variants each arm of `kind_of` names, one list for each arm.
fn arms(file file: SourceFile) -> List(List(String)) {
  syntax.parse(file).functions
  |> list.filter(fn(definition) { definition.definition.name == "kind_of" })
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
      |> list.map(fn(name) { "no arm of its own in kind_of for " <> name }),
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
      "",
      "pub type Payload {",
      "  News(a: Int)",
      "  Struck(a: Int)",
      "  Credit(a: Int)",
      "}",
      "",
      "pub fn kind_of(payload: Payload) -> Int {",
      "  case payload {",
      "    News(..) -> 1",
      "    Struck(..) | Credit(..) -> 2",
      "  }",
      "}",
    ])
  assert breaches(file: planted_file)
    == [
      "no table row for Struck",
      "no table row for Credit",
      "a table row for no variant: Gone",
      "no arm of its own in kind_of for Struck",
      "no arm of its own in kind_of for Credit",
    ]
    as "a variant with no row, a row for no variant and a variant sharing an arm are each found"
  assert breaches(file: SourceFile(
      path: relay_path,
      text: source.read(relay_path),
    ))
    == []
    as "each payload of the relay has a row in the table and an arm of its own in kind_of"
}
