//// The gap-test tag rule. Expected values are the rule of `./check fast`: it runs the
//// tests tagged `gaps`, so every test that reads a gap registry carries the tag. A test
//// reads one when it calls `<module>.gaps()` or `gaps.registry()`, itself or through a
//// helper of its own file. Every case is planted in a made-up file.

import code_rule/gap_test_tag
import code_rule/planted
import code_rule/repository
import gleam/list
import owned_test
import unitest

pub fn a_test_that_calls_a_modules_gaps_without_the_tag_is_a_breach_at_its_line_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("test/planted_test.gleam", [
      "import owned_test",
      "import unitest",
      "",
      "pub fn untagged_test() {",
      "  use <- owned_test.run(5000)",
      "  assert cast_cost.gaps() != []",
      "}",
      "",
      "pub fn other_tag_test() {",
      "  use <- owned_test.run(5000)",
      "  use <- unitest.tag(\"coverage\")",
      "  assert cast_cost.gaps() != []",
      "}",
    ])
  assert planted.lines(gap_test_tag.breaches(file)) == [4, 9]
}

pub fn a_test_that_calls_the_registry_without_the_tag_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("test/planted_test.gleam", [
      "pub fn registry_test() {",
      "  use <- owned_test.run(5000)",
      "  assert list.any(gaps.registry(), fn(entry) { entry.area == \"Casting\" })",
      "}",
    ])
  assert planted.lines(gap_test_tag.breaches(file)) == [1]
}

pub fn a_test_that_reads_gaps_through_a_helper_of_its_file_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("test/planted_test.gleam", [
      "fn gaps_of_the_cast() {",
      "  cast_cost.gaps()",
      "}",
      "",
      "fn the_cast_entries() {",
      "  gaps_of_the_cast()",
      "}",
      "",
      "fn unrelated() {",
      "  [1]",
      "}",
      "",
      "pub fn through_two_helpers_test() {",
      "  use <- owned_test.run(5000)",
      "  assert the_cast_entries() != []",
      "}",
      "",
      "pub fn through_an_unrelated_helper_test() {",
      "  use <- owned_test.run(5000)",
      "  assert unrelated() != []",
      "}",
    ])
  assert planted.lines(gap_test_tag.breaches(file)) == [13]
}

pub fn a_call_that_is_not_the_registrys_function_is_no_read_of_a_gap_registry_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  list.each(
    [
      #("cast_cost.gaps()", True, "a call of a module's gaps with no arguments"),
      #("gaps.registry()", True, "the registry's own function"),
      #(
        "cast_cost.gaps(1)",
        False,
        "gaps() takes no arguments, so a call with one is another function",
      ),
      #(
        "gaps.registry(1)",
        False,
        "registry() takes no arguments, so a call with one is another function",
      ),
      #(
        "cast_cost.inner.gaps()",
        False,
        "a function of a field is no module's gaps",
      ),
      #("cast_cost.registry()", False, "registry() of another module"),
      #("gaps()", False, "a local function of the same name is no module's"),
    ],
    fn(row) {
      let #(call, reads, reason) = row
      let file =
        planted.file("test/planted_test.gleam", [
          "pub fn row_test() {",
          "  assert " <> call <> " != []",
          "}",
        ])
      assert planted.lines(gap_test_tag.breaches(file))
        == case reads {
          True -> [1]
          False -> []
        }
        as reason
    },
  )
}

pub fn a_test_tagged_gaps_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("test/planted_test.gleam", [
      "pub fn one_tag_test() {",
      "  use <- owned_test.run(5000)",
      "  use <- unitest.tag(\"gaps\")",
      "  assert cast_cost.gaps() != []",
      "}",
      "",
      "pub fn several_tags_test() {",
      "  use <- owned_test.run(5000)",
      "  use <- unitest.tags([\"registry\", \"gaps\"])",
      "  assert gaps.registry() != []",
      "}",
    ])
  assert gap_test_tag.breaches(file) == []
}

pub fn a_function_that_is_not_a_public_test_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("test/planted_test.gleam", [
      "fn private_test() {",
      "  cast_cost.gaps()",
      "}",
      "",
      "pub fn helper() {",
      "  cast_cost.gaps()",
      "}",
    ])
  assert gap_test_tag.breaches(file) == []
}

pub fn every_test_in_the_test_directory_that_reads_a_gap_registry_is_tagged_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let files = repository.sources(["test"])
  assert list.flat_map(files, gap_test_tag.breaches) == []
}
