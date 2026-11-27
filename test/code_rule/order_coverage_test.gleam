//// The order cover rule. Expected value is the rule (Design run A, section 6): each
//// variant of a told type has exactly one row, a row naming a test names a public
//// `_test` function that exists, an order test names its variant, an independent row
//// gives a sentence of reason, and a failure row names a test or says why it cannot
//// happen. Each is shown on planted files.

import code_rule/order_coverage.{
  type Cover, type Row, Independent, Order, Owner, Row,
}
import code_rule/planted
import code_rule/source.{type SourceFile}
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
    as "Alpha is named in the test's file and Beta in a support module it imports; Gamma is named in neither"
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
