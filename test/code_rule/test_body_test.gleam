//// The test-body rule. Expected values are the rule of the writing-tests
//// skill and the helper's contract: each test runs in its own owned process,
//// so every public function ending in `_test` starts with
//// `use <- owned_test.run(`, whatever the deadline. Private functions and
//// public functions whose names do not end in `_test` are not tests. The
//// breach is reported at the function's line. Every case is planted in a
//// made-up file.

import code_rule/planted
import code_rule/repository
import code_rule/test_body
import gleam/list
import owned_test

pub fn a_test_that_starts_inside_the_helper_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("test/planted_test.gleam", [
      "import owned_test",
      "",
      "pub fn short_test() {",
      "  use <- owned_test.run(5000)",
      "  assert 1 == 1",
      "}",
      "",
      "pub fn long_test() {",
      "  use <- owned_test.run(60_000)",
      "  assert 1 == 1",
      "}",
    ])
  assert test_body.breaches(file) == []
}

pub fn a_public_test_that_does_not_start_inside_the_helper_is_a_breach_at_its_line_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("test/planted_test.gleam", [
      "import owned_test",
      "",
      "pub fn bare_test() {",
      "  assert 1 == 1",
      "}",
      "",
      "pub fn late_test() {",
      "  let value = 1",
      "  use <- owned_test.run(5000)",
      "  assert value == 1",
      "}",
      "",
      "pub fn other_helper_test() {",
      "  use <- other.run(5000)",
      "  assert 1 == 1",
      "}",
      "",
      "pub fn conforming_test() {",
      "  use <- owned_test.run(5000)",
      "  assert 1 == 1",
      "}",
    ])
  assert planted.lines(test_body.breaches(file)) == [3, 7, 13]
}

pub fn a_breach_names_the_file_it_is_in_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("test/planted_test.gleam", [
      "pub fn bare_test() {",
      "  assert 1 == 1",
      "}",
    ])
  let assert [breach] = test_body.breaches(file)
    as "expected exactly one breach"
  assert breach.path == "test/planted_test.gleam"
}

pub fn a_private_function_and_a_public_function_that_is_not_a_test_are_ignored_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("test/planted_test.gleam", [
      "fn private_test() {",
      "  assert 1 == 1",
      "}",
      "",
      "pub fn helper() {",
      "  assert 1 == 1",
      "}",
      "",
      "pub fn test_prefix() {",
      "  assert 1 == 1",
      "}",
      "",
      "pub fn main() {",
      "  Nil",
      "}",
    ])
  assert test_body.breaches(file) == []
}

pub fn every_test_in_the_test_directory_starts_inside_the_helper_test() -> Nil {
  // Deadline: the body took 159 to 173 ms in three runs alone, so 5 s is more
  // than 3 times that.
  use <- owned_test.run(5000)
  let files = repository.sources(["test"])
  assert list.flat_map(files, test_body.breaches) == []
}
