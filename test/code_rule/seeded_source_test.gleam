//// The seeded generator rule. Expected values are the issue's test 2 and the
//// reason for it: the released server draws from the operating system's
//// strong source, so a module under `src/` may not import the seeded
//// generator (`genesis_prime/seeded_random`, which lives in `dev/`) or the
//// package of seeded generators `prng`; `dev/` and `test/` may. Each case is
//// planted once in a made-up file, and the real tree is checked last.

import code_rule/planted
import code_rule/repository
import code_rule/seeded_source
import gleam/list
import owned_test

pub fn a_module_in_src_that_imports_the_seeded_generator_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("src/planted/login.gleam", [
      "import genesis_prime/seeded_random",
      "",
      "pub fn secret() -> BitArray {",
      "  seeded_random.bytes(state: 1, count: 32).0",
      "}",
    ])
  assert planted.lines(seeded_source.breaches(file)) == [1]
}

pub fn an_aliased_or_unqualified_import_is_a_breach_too_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("src/planted/login.gleam", [
      "import genesis_prime/seeded_random as random",
      "import genesis_prime/seeded_random.{bytes}",
      "",
      "pub fn secret() -> BitArray {",
      "  bytes(state: 1, count: 32).0",
      "}",
    ])
  assert planted.lines(seeded_source.breaches(file)) == [1, 2]
}

pub fn a_module_in_src_that_imports_the_prng_package_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("src/planted/login.gleam", [
      "import prng/random",
      "import prng/seed",
      "import prng",
    ])
  assert planted.lines(seeded_source.breaches(file)) == [1, 2, 3]
}

pub fn a_module_in_src_that_imports_another_random_module_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("src/planted/login.gleam", [
      "import gleam/crypto",
      "import genesis_prime/login/random_source",
      "import genesis_prime/seeded_randomness_notes",
    ])
  assert seeded_source.breaches(file) == []
}

pub fn a_module_in_dev_or_test_may_import_the_seeded_generator_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      "dev/planted/start.gleam", "test/planted_test.gleam",
      "test/planted/support.gleam",
    ],
    fn(path) {
      let file =
        planted.file(path, [
          "import genesis_prime/seeded_random",
          "import prng/random",
        ])
      assert seeded_source.breaches(file) == []
        as { path <> " may import the seeded generator" }
    },
  )
}

pub fn no_module_in_src_imports_the_seeded_generator_test() -> Nil {
  use <- owned_test.run(5000)
  let files = repository.sources(["src"])
  assert list.flat_map(files, seeded_source.breaches) == []
}
