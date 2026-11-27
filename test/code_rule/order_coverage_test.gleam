//// The order cover rule. Expected value is the rule (Design run A, section 6): each
//// variant of a told type has exactly one row, a row naming a test names a public
//// `_test` function that exists, an order test names its variant, an independent row
//// gives a sentence of reason, and a failure row names a test or says why it cannot
//// happen. Each is shown on planted files.

import code_rule/list_file
import code_rule/order_coverage.{
  type Cover, type Row, Independent, Order, Owner, Row,
}
import code_rule/order_coverage_rows
import code_rule/planted
import code_rule/repository
import code_rule/source.{type SourceFile}
import gleam/list
import gleam/string
import owned_test
import unitest

const kinds = #("genesis_prime/thing", "Kind")

const reason = "the relation does not read the kind"

/// A planted type of three variants.
fn kind_file() -> SourceFile {
  planted.file(path: "src/genesis_prime/thing.gleam", lines: [
    "pub type Kind {",
    "  Alpha",
    "  Beta",
    "  Gamma",
    "}",
  ])
}

/// A test file that names `Alpha` in a public test, holds a private function ending
/// `_test` and a public one that does not, and imports a support module naming `Beta`.
fn test_files() -> List(SourceFile) {
  [
    planted.file(path: "test/thing_order_test.gleam", lines: [
      "import thing_support",
      "pub fn alpha_comes_first_test() {",
      "  Alpha",
      "}",
      "fn hidden_test() {",
      "  Alpha",
      "}",
      "pub fn helper() {",
      "  Alpha",
      "}",
    ]),
    planted.file(path: "test/thing_support.gleam", lines: [
      "pub fn scene() {",
      "  Beta",
      "  GammaRay(Alphabet)",
      "}",
    ]),
  ]
}

fn sources() -> List(SourceFile) {
  [kind_file(), ..test_files()]
}

fn row(variants: List(String), cover: Cover) -> Row {
  Row(module: "genesis_prime/thing", type_name: "Kind", variants:, cover:)
}

fn breaches(rows: List(Row)) -> List(String) {
  order_coverage.breaches(rows:, told: [kinds], sources: sources())
}

pub fn a_variant_with_no_order_row_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert breaches([])
    == ["no row for Alpha", "no row for Beta", "no row for Gamma"]
    as "a told type with no rows has a breach for each of its variants"
  assert breaches([
      row(["Alpha", "Beta"], Order("thing_order_test.alpha_comes_first_test")),
      row(["Gamma"], Independent(reason)),
    ])
    == []
    as "a variant in a row is no breach for a missing row"
}

pub fn a_row_for_no_variant_or_a_variant_in_two_rows_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert breaches([
      row(["Alpha", "Gamma"], Independent(reason)),
      row(["Beta", "Delta"], Independent(reason)),
    ])
    == ["a row for no variant: Delta"]
    as "a row naming a name that is no variant of its type is found"
  assert breaches([
      row(["Alpha", "Beta", "Gamma"], Independent(reason)),
      row(["Gamma"], Independent(reason)),
    ])
    == ["in two rows: Gamma"]
    as "a variant in two rows is found once"
}

pub fn an_order_or_owner_row_whose_test_is_missing_or_private_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert breaches([
      row(["Alpha"], Owner("thing_order_test.missing_test")),
      row(["Beta"], Owner("thing_order_test.hidden_test")),
      row(["Gamma"], Owner("no_such_module.alpha_comes_first_test")),
    ])
    == [
      "the test is missing or private: thing_order_test.missing_test",
      "the test is missing or private: thing_order_test.hidden_test",
      "the test is missing or private: no_such_module.alpha_comes_first_test",
    ]
    as "a test absent from its file, private, or in no module is found"
  assert breaches([
      row(["Alpha"], Owner("thing_order_test.helper")),
      row(["Beta", "Gamma"], Independent(reason)),
    ])
    == ["the test is missing or private: thing_order_test.helper"]
    as "a public function not ending in _test is no test"
  assert breaches([
      row(["Alpha"], Owner("thing_order_test.alpha_comes_first_test")),
      row(["Beta", "Gamma"], Independent(reason)),
    ])
    == []
    as "a public test that exists passes"
}

pub fn an_order_row_whose_test_never_names_its_variant_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert breaches([
      row(
        ["Alpha", "Beta", "Gamma"],
        Order("thing_order_test.alpha_comes_first_test"),
      ),
    ])
    == ["the test never names Gamma: thing_order_test.alpha_comes_first_test"]
    as "Alpha is named in the test's file and Beta in a support module it imports; Gamma is named in neither, though GammaRay is, so a name that is part of a longer one is not the name"
}

pub fn an_independent_row_without_a_sentence_of_reason_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert breaches([
      row(["Alpha"], Independent("")),
      row(["Beta"], Independent("none")),
      row(["Gamma"], Independent("not read")),
    ])
    == [
      "the reason is no sentence: Alpha",
      "the reason is no sentence: Beta",
      "the reason is no sentence: Gamma",
    ]
    as "an empty reason, a one-word reason and a two-word reason are each found"
  assert breaches([
      row(
        ["Alpha", "Beta", "Gamma"],
        Independent("the relation never reads it"),
      ),
    ])
    == []
    as "a sentence of reason passes"
}

pub fn a_failure_row_that_names_no_test_and_no_reason_or_a_missing_test_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file(path: "src/genesis_prime/thing.gleam", lines: [
      "//// | Point | What happens |",
      "//// |---|---|",
      "//// | the first dies | dropped (`thing_order_test.alpha_comes_first_test`) |",
      "//// | the second dies | dropped, and nothing more |",
      "//// | the third dies | cannot happen: the registry finds no process |",
      "//// | the fourth dies | dropped (`thing_order_test.missing_test`) |",
      "//// | the fifth dies | cannot happen |",
      "//// | the sixth dies | dropped (`thing_order_test.hidden_test`) |",
      "//// | the seventh dies | cannot happen: never |",
      "////",
      "//// | other | not a failure row |",
    ])
  assert order_coverage.failure_breaches(file:, sources: sources())
    == [
      "a failure row names no test and no reason: the second dies",
      "a failure row names a missing or private test: thing_order_test.missing_test",
      "a failure row names no test and no reason: the fifth dies",
      "a failure row names a missing or private test: thing_order_test.hidden_test",
      "a failure row names no test and no reason: the seventh dies",
    ]
    as "a row with a public test that exists or a reason of a sentence passes; a row with neither, one with a missing test, one with a private test and one whose reason is a single word are found"
}

pub fn the_connections_timers_are_read_from_the_arms_that_tell_them_apart_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file(path: "src/genesis_prime/game/connection.gleam", lines: [
      "pub fn timer_due(session, now, timer) {",
      "  case timer {",
      "    _ if timer == connection_state.save_timer -> first(session)",
      "    _ if timer == connection_state.expiry_timer -> second(session)",
      "    _ if timer == other.not_named_as_one -> third(session)",
      "    _ -> other_timer_fired(session, now, timer)",
      "  }",
      "}",
      "",
      "pub fn other_timer_fired(session, now, timer) {",
      "  case cast_state.owns(timer), strike.owns(timer) {",
      "    True, _ -> first(session)",
      "    False, True -> second(session)",
      "    False, False -> claim(session)",
      "  }",
      "}",
      "",
      "pub fn unrelated(timer) {",
      "  case connection_state.stray_timer == timer, timer.owns(timer) {",
      "    _, _ -> Nil",
      "  }",
      "}",
    ])
  assert order_coverage.connection_timers(file:)
    == ["save_timer", "expiry_timer", "cast_state", "strike", "claim"]
    as "the timers timer_due compares with, the module of each owns check of other_timer_fired and the claim are found, and a name that is not a timer, and a function of another name, are not"
}

pub fn a_failure_row_naming_no_type_or_variant_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file(path: "src/genesis_prime/world_map/thing.gleam", lines: [
      "//// | Point | What happens |",
      "//// |---|---|",
      "//// | `Seen(V, g)` reaches it | `Alpha` is dropped, `Missing` is not, `True` is the prelude's |",
      "//// | the `Gone` notice | `Beta(Alpha)`, and `lower_case` and `a_function(g)` are no names of a type |",
      "",
      "//// | `Other` | not a failure row |",
    ])
  assert order_coverage.unknown_names(file:, sources: sources())
    == [
      "a failure row names no type or variant: Seen",
      "a failure row names no type or variant: Missing",
      "a failure row names no type or variant: Gone",
    ]
    as "a CamelCase name in a backtick that no file of src declares is found once; a single capital, a prelude name, a declared variant and a lowercase name are not, and a table of another shape is not read"
}

const map_path = "src/genesis_prime/world_map/map.gleam"

const without_test_path = "test/code_rule/failure_rows_without_test.txt"

fn real_sources() -> List(SourceFile) {
  repository.sources(under: ["src", "test"])
}

pub fn every_variant_of_the_told_kinds_has_exactly_one_valid_order_row_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.tag("code_rule")
  assert order_coverage.breaches(
      rows: order_coverage_rows.rows(),
      told: order_coverage_rows.told(),
      sources: real_sources(),
    )
    == []
    as "each variant of the types the map and the processes tell each other is in one row, whose test exists, is public and names it, or whose reason is a sentence"
}

pub fn each_input_family_of_the_relation_table_is_read_from_its_type_and_covered_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.tag("code_rule")
  let sources = real_sources()
  let families = order_coverage_rows.families(sources:)
  assert list.all(families, fn(family) { family.1 != [] })
    as "each family is read from the source: a type that is no longer there, or an arm no longer found, would leave one with no member"
  assert order_coverage.breaches_of(
      rows: order_coverage_rows.family_rows(),
      families:,
      sources:,
    )
    == []
    as "each member of each family is in one row, whose test exists, is public and names it, or whose reason is a sentence"
}

pub fn every_row_of_the_maps_failure_tables_names_a_test_or_why_it_cannot_happen_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.tag("code_rule")
  let sources = real_sources()
  let assert Ok(map_file) =
    list.find(sources, fn(file) { file.path == map_path })
  // Rows whose behaviour is described and has no test yet are listed by their point in
  // the list file; a row not on it must name a test or say why it cannot happen, and a
  // row on it must still name neither, so the list only shrinks.
  let without_test =
    list_file.rows(text: source.read(without_test_path))
    |> list.map(fn(row) {
      "a failure row names no test and no reason: " <> row.0
    })
  assert list.sort(
      order_coverage.failure_breaches(file: map_file, sources:),
      string.compare,
    )
    == list.sort(without_test, string.compare)
    as "each row of the map's failure tables names a public test that exists or says cannot happen with its reason, but the rows of the list, which each still name neither"
}

pub fn every_type_name_in_a_failure_row_is_a_type_or_variant_in_src_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.tag("code_rule")
  let sources = real_sources()
  let assert Ok(map_file) =
    list.find(sources, fn(file) { file.path == map_path })
  assert order_coverage.unknown_names(file: map_file, sources:) == []
    as "each CamelCase name in a backtick of a failure row is a type or a variant declared in src"
}
