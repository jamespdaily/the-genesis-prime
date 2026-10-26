//// The supplied source rule. Expected values are the issue's test 2 and the
//// reason for it: the released server draws every random byte of the login
//// from the operating system's strong source, so no module under `src/` but
//// `login/random_source.gleam` may build `Supplied`, the source that takes its
//// bytes from a function the caller gives; `dev/` and `test/` may. Each case
//// is planted once in a made-up file, and the real tree is checked last.
//// `random_source` draws from the operating system, so gleam.toml lists it as
//// an effectful module.

import code_rule/planted
import code_rule/purity
import code_rule/repository
import code_rule/supplied_source
import gleam/list
import owned_test
import simplifile

pub fn a_module_in_src_that_builds_supplied_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("src/planted/login.gleam", [
      "import genesis_prime/login/random_source",
      "",
      "pub fn source() -> random_source.RandomSource {",
      "  random_source.Supplied(draw: fn(_draw) { <<0:size(256)>> })",
      "}",
    ])
  assert planted.lines(supplied_source.breaches(file)) == [4]
}

pub fn an_unqualified_use_of_the_constructor_is_a_breach_too_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("src/planted/login.gleam", [
      "import genesis_prime/login/random_source.{type RandomSource, Supplied}",
      "",
      "pub fn source() -> RandomSource {",
      "  Supplied(draw: fn(_draw) { <<0:size(256)>> })",
      "}",
    ])
  assert planted.lines(supplied_source.breaches(file)) == [4]
}

pub fn the_constructor_used_as_a_function_value_or_in_a_constant_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("src/planted/login.gleam", [
      "import genesis_prime/login/random_source",
      "",
      "const fixed = random_source.Supplied(draw: zeroes)",
      "",
      "fn zeroes(_draw) -> BitArray {",
      "  <<0:size(256)>>",
      "}",
      "",
      "pub fn make() -> fn(fn(a) -> BitArray) -> random_source.RandomSource {",
      "  random_source.Supplied",
      "}",
    ])
  assert planted.lines(supplied_source.breaches(file)) == [3, 10]
}

pub fn an_import_of_the_constructor_under_another_name_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("src/planted/login.gleam", [
      "import genesis_prime/login/random_source.{Supplied as Chosen}",
      "",
      "pub fn make() {",
      "  Chosen",
      "}",
    ])
  assert planted.lines(supplied_source.breaches(file)) == [1]
}

pub fn matching_supplied_or_using_the_strong_source_builds_nothing_and_is_no_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("src/planted/login.gleam", [
      "import genesis_prime/login/random_source.{Strong, Supplied}",
      "",
      "pub fn is_strong(source: random_source.RandomSource) -> Bool {",
      "  case source {",
      "    Strong -> True",
      "    Supplied(draw: _) -> False",
      "  }",
      "}",
      "",
      "pub fn strong() -> random_source.RandomSource {",
      "  Strong",
      "}",
    ])
  assert supplied_source.breaches(file) == []
}

pub fn random_source_itself_may_build_supplied_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("src/genesis_prime/login/random_source.gleam", [
      "pub type RandomSource {",
      "  Strong",
      "  Supplied(draw: fn(Int) -> BitArray)",
      "}",
      "",
      "pub fn supplied() -> RandomSource {",
      "  Supplied(draw: fn(_count) { <<>> })",
      "}",
    ])
  assert supplied_source.breaches(file) == []
}

pub fn a_module_in_dev_or_test_may_build_supplied_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    ["dev/genesis_prime/recording/draw_log.gleam", "test/recorded_draws.gleam"],
    fn(path) {
      let file =
        planted.file(path, [
          "import genesis_prime/login/random_source",
          "",
          "pub fn source() -> random_source.RandomSource {",
          "  random_source.Supplied(draw: fn(_draw) { <<0:size(256)>> })",
          "}",
        ])
      assert supplied_source.breaches(file) == []
        as { path <> " may build Supplied" }
    },
  )
}

pub fn no_module_in_src_builds_supplied_outside_random_source_test() -> Nil {
  use <- owned_test.run(5000)
  let files = repository.sources(["src"])
  assert list.flat_map(files, supplied_source.breaches) == []
}

pub fn random_source_is_listed_as_an_effectful_module_because_it_draws_from_the_operating_system_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(project_file) = simplifile.read("gleam.toml")
    as "gleam.toml could not be read"
  assert list.contains(
    purity.allowed(project_file).effectful_modules,
    "genesis_prime/login/random_source",
  )
    as "random_source draws from the operating system, so it has effects and gleam.toml says so"
}
