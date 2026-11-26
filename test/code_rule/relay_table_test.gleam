//// The relay table rule. Expected value is the rule: `genesis_prime/world_map/relay` is
//// the one table of what a creature tells a player and a player tells a creature through
//// the map, so each variant of `Payload` and of `Inbound` has a row in the module's doc
//// table (its kind, destination check and source check) and one arm of its own in
//// `kind_of` or `inbound_kind_of`, which gives that kind. A variant with no row or no arm
//// of its own, a row for no variant, an `Inbound` arm whose `source:` is not a bare
//// variant, and an arm whose `NoSenderCheck` differs from its row's "none", is a breach. The rule is shown on a planted file,
//// then read over the real one.

import code_rule/planted
import code_rule/source.{type SourceFile, SourceFile}
import code_rule/syntax
import glance
import gleam/bool
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import owned_test
import unitest

const relay_path = "src/genesis_prime/world_map/relay.gleam"

/// The types the table has a row for each variant of, with the function that gives each
/// variant's kind. `Landing` is what a player's connection lands on another through the map.
const tables = [
  #("Payload", "kind_of"),
  #("Inbound", "inbound_kind_of"),
  #("Landing", "landing_kind_of"),
]

/// The names of the variants of the custom types called `type_names`.
fn variants_of(
  file file: SourceFile,
  type_names type_names: List(String),
) -> List(String) {
  syntax.parse(file).custom_types
  |> list.filter(fn(definition) {
    list.contains(type_names, definition.definition.name)
  })
  |> list.flat_map(fn(definition) {
    list.map(definition.definition.variants, fn(variant) { variant.name })
  })
}

/// The names of the variants of the table's types.
fn variants(file file: SourceFile) -> List(String) {
  variants_of(file:, type_names: list.map(tables, fn(table) { table.0 }))
}

/// The rows of the module's doc table: the backticked first cell and the last cell of
/// each row of the module's `////` lines.
fn table_rows(file file: SourceFile) -> List(#(String, String)) {
  string.split(file.text, "\n")
  |> list.filter_map(fn(line) {
    use <- bool.guard(
      when: !string.starts_with(line, "//// | `"),
      return: Error(Nil),
    )
    use name <- result.try(
      string.split(string.drop_start(line, 8), "`") |> list.first,
    )
    use last <- result.map(
      string.split(string.trim_end(line), " | ") |> list.last,
    )
    #(name, last)
  })
}

/// The names the module's doc table has a row for.
fn tabled(file file: SourceFile) -> List(String) {
  list.map(table_rows(file:), fn(row) { row.0 })
}

/// The arms of the kind functions, one clause for each arm, with its function's name.
fn clauses(file file: SourceFile) -> List(#(String, glance.Clause)) {
  syntax.parse(file).functions
  |> list.filter(fn(definition) {
    list.any(tables, fn(table) { table.1 == definition.definition.name })
  })
  |> list.flat_map(fn(definition) {
    list.flat_map(definition.definition.body, fn(statement) {
      case statement {
        glance.Expression(glance.Case(clauses:, ..)) ->
          list.map(clauses, fn(clause) { #(definition.definition.name, clause) })
        glance.Expression(_)
        | glance.Use(..)
        | glance.Assignment(..)
        | glance.Assert(..) -> []
      }
    })
  })
}

/// The variants a clause's patterns name.
fn named_by(clause clause: glance.Clause) -> List(String) {
  list.flatten(clause.patterns)
  |> list.filter_map(constructor_of)
}

/// The variants each arm of the kind functions names, one list for each arm.
fn arms(file file: SourceFile) -> List(List(String)) {
  list.map(clauses(file:), fn(entry) { named_by(clause: entry.1) })
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
  let inbound = variants_of(file:, type_names: ["Inbound"])
  table_rows(file:)
  |> list.filter(fn(row) { list.contains(inbound, row.0) })
  |> list.map(fn(row) { #(row.0, string.starts_with(row.1, "none")) })
}

/// Whether each arm of `inbound_kind_of` gives `NoSenderCheck` as the `source:` of its
/// `InboundKind`, by the variant's name; an arm whose body is not an `InboundKind(...)`
/// call with a `source:` that is a bare variant is `Error(Nil)`, unread.
fn armed_without_sender_check(
  file file: SourceFile,
) -> List(#(String, Result(Bool, Nil))) {
  list.filter(clauses(file:), fn(entry) { entry.0 == "inbound_kind_of" })
  |> list.flat_map(fn(entry) {
    let checked = case entry.1.body {
      glance.Call(arguments:, ..) ->
        case
          syntax.argument(
            arguments:,
            label: "source",
            position: syntax.LastArgument,
          )
        {
          Some(glance.Variable(name:, ..)) -> Ok(name == "NoSenderCheck")
          Some(_) | None -> Error(Nil)
        }
      _ -> Error(Nil)
    }
    list.map(named_by(clause: entry.1), fn(name) { #(name, checked) })
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
    list.filter_map(variants_of(file:, type_names: ["Inbound"]), fn(name) {
      case list.key_find(armed_without_sender_check(file:), name) {
        Error(Nil) -> Error(Nil)
        Ok(Error(Nil)) ->
          Ok("the source check of " <> name <> " cannot be read from its arm")
        Ok(Ok(armed)) ->
          case list.key_find(tabled_without_sender_check(file:), name) {
            Ok(tabled) if tabled != armed ->
              Ok(
                "the source check of "
                <> name
                <> " differs between its row and its arm",
              )
            Ok(_) | Error(Nil) -> Error(Nil)
          }
      }
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
      "      // a comment between the pattern and the body",
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
      "the source check of TargetMoved cannot be read from its arm",
      "the source check of Despawn cannot be read from its arm",
    ]
    as "a variant of either type with no row, a row for no variant, a variant sharing an arm, a row whose source check is not its arm's and an arm whose source check is no bare variant are each found"
  assert breaches(file: SourceFile(
      path: relay_path,
      text: source.read(relay_path),
    ))
    == []
    as "each payload, each inbound tell and each landing of the relay has a row in the table and an arm of its own in its kind function"
  assert list.filter(
      variants(file: SourceFile(path: relay_path, text: source.read(relay_path))),
      fn(name) { name == "Move" || name == "Moving" },
    )
    == []
    as "a move is no relayed payload: the mover tells its viewers itself"
}
