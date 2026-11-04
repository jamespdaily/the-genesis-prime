//// The owned-keys rule. A test module that loads tables or writes content terms
//// makes its keys with `owned_key`, so a body that ends with terms under them
//// fails. Every breach is planted in made-up files; the last test runs the rule
//// over the repository's tests.

import code_rule/owned_keys
import code_rule/planted
import code_rule/repository
import code_rule/source.{type SourceFile}
import gleam/list
import owned_test
import unitest

fn test_module(path: String, lines: List(String)) -> SourceFile {
  planted.file(path:, lines: ["//// A planted test module.", ..lines])
}

pub fn a_reference_made_for_a_load_without_owned_key_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    test_module("test/some_test.gleam", [
      "import genesis_prime/table/loader/store",
      "import gleam/erlang/reference",
      "fn load(folder, entry) {",
      "  store.load(under: reference.new(), from: folder, entries: [entry])",
      "}",
    ])
  assert planted.lines(owned_keys.breaches([file])) == [5]
    as "the reference is made on line 5, for the load beside it"
}

pub fn a_store_key_made_for_content_terms_without_owned_key_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    test_module("test/some_test.gleam", [
      "import genesis_prime/table/loader/store as table_store",
      "fn put() {",
      "  let key = table_store.new_key()",
      "  table_store.put_content(key:, table: \"T\", id: 1, value: 1)",
      "}",
    ])
  assert planted.lines(owned_keys.breaches([file])) == [4]
    as "the key is made on line 4, for the content term written under it"
}

pub fn a_store_key_made_for_the_content_load_is_a_breach_in_a_module_that_never_calls_put_content_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    test_module("test/some_test.gleam", [
      "import genesis_prime/content",
      "import genesis_prime/table/loader/store",
      "fn load(tables, pool) {",
      "  content.load(tables:, pool:, key: store.new_key())",
      "}",
    ])
  assert planted.lines(owned_keys.breaches([file])) == [5]
    as "the content load writes terms under the key made on line 5"
}

pub fn a_store_key_made_for_the_spawn_terms_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    test_module("test/some_test.gleam", [
      "import genesis_prime/content/spawn as content_spawn",
      "import genesis_prime/table/loader/store",
      "fn put(spawns) {",
      "  content_spawn.put_world(key: store.new_key(), world_id: 1, spawns:)",
      "}",
    ])
  assert planted.lines(owned_keys.breaches([file])) == [5]
    as "the spawn terms are written under the key made on line 5"
}

pub fn a_key_made_with_owned_key_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    test_module("test/some_test.gleam", [
      "import genesis_prime/table/loader/store",
      "import owned_key",
      "fn load(folder, entry) {",
      "  store.load(under: owned_key.new(), from: folder, entries: [entry])",
      "}",
    ])
  assert owned_keys.breaches([file]) == []
}

pub fn a_module_that_loads_nothing_may_make_any_reference_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    test_module("test/some_test.gleam", [
      "import gleam/erlang/reference",
      "fn make() { reference.new() }",
    ])
  assert owned_keys.breaches([file]) == []
}

pub fn the_modules_that_make_the_shared_loads_are_not_read_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let lines = [
    "import genesis_prime/table/loader/store",
    "import gleam/erlang/reference",
    "fn load(folder, entry) {",
    "  store.load(under: reference.new(), from: folder, entries: [entry])",
    "}",
  ]
  assert owned_keys.breaches([
      test_module("test/client_tables.gleam", lines),
      test_module("test/character_tables.gleam", lines),
    ])
    == []
}

pub fn no_test_makes_a_key_for_its_loads_without_owned_key_test() -> Nil {
  use <- owned_test.run(20_000)
  use <- unitest.tag("code_rule")
  let breaches = owned_keys.breaches(repository.sources(under: ["test"]))
  assert list.map(breaches, fn(breach) { #(breach.path, breach.line) }) == []
    as "every key a test makes for a load or a content table is made with owned_key"
}
