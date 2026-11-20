//// The registry-tag rule. Expected values are the rule of the check: the tests that
//// compare a hand-kept list with a registry of the whole server run in `./check fast`
//// by their tag, so each of the core modules below keeps one tagged `registry`.
//// The breaches are planted in made-up files; the last test runs the rule over the
//// tree.

import code_rule/planted
import code_rule/registry
import code_rule/repository
import code_rule/source.{type Breach, type SourceFile, Breach}
import gleam/list
import owned_test
import unitest

/// The test modules whose registry test `./check fast` runs.
const core_modules = [
  "test/server_table_test.gleam", "test/fixture_tables_test.gleam",
  "test/character_tables_test.gleam", "test/wire_fixture_test.gleam",
  "test/message_codec_test.gleam", "test/client_message_test.gleam",
  "test/game_connection_account_claim_test.gleam", "test/real_start_test.gleam",
  "test/server_test.gleam", "test/activate_test.gleam",
  "test/spell_plan_activate_test.gleam",
]

fn module_with(body: List(String)) -> SourceFile {
  planted.file(
    "test/planted_test.gleam",
    list.append(["import owned_test", "import unitest", ""], body),
  )
}

fn breaches_of(body: List(String)) -> List(Breach) {
  registry.breaches(files: [module_with(body)], modules: [
    "test/planted_test.gleam",
  ])
}

pub fn a_module_without_a_public_test_tagged_registry_is_a_breach_naming_it_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let tagged = [
    "pub fn a_list_matches_test() {",
    "  use <- owned_test.run(5000)",
    "  use <- unitest.tag(\"registry\")",
    "  assert 1 == 1",
    "}",
  ]
  let cases = [
    #("a tagged test is no breach", tagged, 0),
    #(
      "a tagged test among untagged ones is no breach",
      list.append(
        ["pub fn other_test() {", "  use <- owned_test.run(5000)", "}", ""],
        tagged,
      ),
      0,
    ),
    #(
      "a module with no tag is a breach",
      ["pub fn a_list_matches_test() {", "  use <- owned_test.run(5000)", "}"],
      1,
    ),
    #(
      "another tag is no registry tag",
      [
        "pub fn a_list_matches_test() {",
        "  use <- owned_test.run(5000)",
        "  use <- unitest.tag(\"serial\")",
        "}",
      ],
      1,
    ),
    #(
      "a private function is no test",
      ["fn a_list_matches_test() {", "  use <- unitest.tag(\"registry\")", "}"],
      1,
    ),
    #(
      "a public function not ending in _test is no test",
      ["pub fn a_list_matches() {", "  use <- unitest.tag(\"registry\")", "}"],
      1,
    ),
  ]
  list.each(cases, fn(row) {
    let #(reason, body, expected) = row
    assert list.length(breaches_of(body)) == expected as reason
  })
  let assert [breach] = breaches_of(["pub fn a_list_matches_test() {", "}"])
    as "an untagged module is one breach"
  assert breach.path == "test/planted_test.gleam"
}

pub fn a_named_module_that_is_not_among_the_files_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert registry.breaches(files: [], modules: ["test/missing_test.gleam"])
    == [
      Breach(
        path: "test/missing_test.gleam",
        line: 1,
        rule: "the registry test module is missing",
      ),
    ]
}

pub fn each_core_registry_module_has_a_test_tagged_registry_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  assert registry.breaches(
      files: repository.sources(under: ["test"]),
      modules: core_modules,
    )
    == []
}
