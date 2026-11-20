//// The registry-tag rule. Expected values are the rule of the check: the tests that
//// compare a hand-kept list with a registry of the whole server run in `./check fast`
//// by their tag, so each test named below keeps its `registry` tag. The
//// breaches are planted in made-up files; the last test runs the rule over the tree.

import code_rule/planted
import code_rule/registry.{RegistryTest}
import code_rule/repository
import code_rule/source.{type Breach, type SourceFile, Breach}
import gleam/list
import owned_test
import unitest

/// The tests `./check fast` runs by their tag, one per entry: the test module and the
/// start of the test's name (the table counts in two names change, so those two are
/// named by their start).
const registry_tests = [
  RegistryTest("test/server_table_test.gleam", "the_servers_tables_are_the_"),
  RegistryTest(
    "test/fixture_tables_test.gleam",
    "the_content_tables_are_committed_and_each_root_reaches_a_committed_row_test",
  ),
  RegistryTest(
    "test/character_tables_test.gleam",
    "the_content_tables_are_the_content_load_of_the_committed_files_over_the_shared_load_test",
  ),
  RegistryTest(
    "test/wire_fixture_test.gleam",
    "the_fixtures_columns_are_the_tables_columns_but_created_at_test",
  ),
  RegistryTest(
    "test/message_codec_test.gleam",
    "the_schema_generates_one_module_for_each_message_and_record_and_the_client_and_server_message_modules_test",
  ),
  RegistryTest(
    "test/client_message_test.gleam",
    "every_message_the_client_sends_reaches_its_own_decoder_test",
  ),
  RegistryTest(
    "test/game_connection_account_claim_test.gleam",
    "the_game_rule_names_the_client_messages_it_takes_test",
  ),
  RegistryTest(
    "test/real_start_test.gleam",
    "a_folder_with_no_tables_ends_the_node_before_its_ready_line_test",
  ),
  RegistryTest(
    "test/server_test.gleam",
    "the_servers_own_settings_let_the_tree_restart_",
  ),
  RegistryTest(
    "test/activate_test.gleam",
    "every_client_side_interaction_activate_spell_is_planned_or_names_its_gap_test",
  ),
  RegistryTest(
    "test/spell_plan_activate_test.gleam",
    "every_activate_spell_has_a_plan_or_a_reason_test",
  ),
  RegistryTest(
    "test/client_tables_test.gleam",
    "the_shared_load_holds_rows_of_every_table_the_servers_list_names_test",
  ),
  RegistryTest(
    "test/account_store_test.gleam",
    "every_constraint_the_worker_maps_exists_in_the_schema_by_that_name_test",
  ),
  RegistryTest(
    "test/game_number_test.gleam",
    "a_migrated_database_holds_the_seeded_numbers_test",
  ),
  RegistryTest(
    "test/auth_connection_test.gleam",
    "the_auth_rule_names_the_client_messages_it_takes_test",
  ),
  RegistryTest(
    "test/network_message_test.gleam",
    "the_network_layer_takes_exactly_the_ids_it_names_among_those_the_client_sends_test",
  ),
  RegistryTest(
    "test/objective_kind_test.gleam",
    "objective_kind_has_a_variant_for_every_type_the_real_tables_use_that_the_code_reads_test",
  ),
  RegistryTest(
    "test/objective_cast_tables_test.gleam",
    "the_cast_objectives_without_a_spell_are_the_known_six_test",
  ),
  RegistryTest(
    "test/objective_cast_tables_test.gleam",
    "every_targeted_rows_cast_conditions_are_read_but_the_known_eleven_test",
  ),
  RegistryTest(
    "test/sitting_test.gleam",
    "the_servers_own_settings_record_nothing_and_a_sitting_turns_it_on_test",
  ),
]

fn module_with(body: List(String)) -> SourceFile {
  planted.file(
    "test/planted_test.gleam",
    list.append(["import owned_test", "import unitest", ""], body),
  )
}

fn breaches_of(body: List(String)) -> List(Breach) {
  registry.breaches(files: [module_with(body)], tests: [
    RegistryTest("test/planted_test.gleam", "a_list_matches_"),
  ])
}

pub fn a_named_test_not_tagged_registry_is_a_breach_naming_its_module_test() -> Nil {
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
      "a tag in the tags list is no breach",
      [
        "pub fn a_list_matches_test() {",
        "  use <- unitest.tags([\"dev_tool\", \"registry\"])",
        "}",
      ],
      0,
    ),
    #(
      "a test whose name starts with the named start is the named test",
      [
        "pub fn a_list_matches_3_times_test() {",
        "  use <- unitest.tag(\"registry\")",
        "}",
      ],
      0,
    ),
    #(
      "a module with no tag is a breach",
      ["pub fn a_list_matches_test() {", "  use <- owned_test.run(5000)", "}"],
      1,
    ),
    #(
      "the tag on another test of the module is a breach",
      [
        "pub fn another_list_matches_test() {",
        "  use <- unitest.tag(\"registry\")",
        "}",
        "",
        "pub fn a_list_matches_test() {",
        "}",
      ],
      1,
    ),
    #(
      "the named test missing from a module is a breach",
      ["pub fn other_test() {", "  use <- unitest.tag(\"registry\")", "}"],
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
      "a tags list without registry is a breach",
      [
        "pub fn a_list_matches_test() {",
        "  use <- unitest.tags([\"dev_tool\", \"coverage\"])",
        "}",
      ],
      1,
    ),
    #(
      "a tag in a comment is a breach",
      [
        "pub fn a_list_matches_test() {",
        "  // use <- unitest.tag(\"registry\")",
        "}",
      ],
      1,
    ),
    #(
      "a tag in a string is a breach",
      [
        "pub fn a_list_matches_test() {",
        "  let _ = \"use <- unitest.tag(\\\"registry\\\")\"",
        "}",
      ],
      1,
    ),
    #(
      "a tag in a nested function is a breach",
      [
        "pub fn a_list_matches_test() {",
        "  fn() { unitest.tag(\"registry\", fn() { Nil }) }",
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
  assert registry.breaches(files: [], tests: [
      RegistryTest("test/missing_test.gleam", "a_list_matches_"),
    ])
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
      tests: registry_tests,
    )
    == []
}
