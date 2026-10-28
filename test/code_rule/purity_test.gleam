//// The purity rule. Expected values are the rules in CLAUDE.md (a rule is a
//// pure function; only modules listed under `[tools.code_rules]` have
//// effects) and in the writing-gleam skill, Packages (an Erlang external
//// states an exact type). A module is named by its path under `src/`, so
//// `src/planted/rule.gleam` is `planted/rule`. An entry of `pure_erlang` is
//// written `module:function`, for example `erlang:abs`. Every breach is
//// planted in a made-up file.

import code_rule/planted
import code_rule/purity.{Allowed}
import code_rule/repository
import code_rule/source.{SourceFile}
import gleam/list
import gleam/string
import owned_test
import simplifile
import unitest

fn nothing_allowed() -> purity.Allowed {
  Allowed(effectful_modules: [], pure_erlang: [])
}

fn importing(module: String) -> List(String) {
  [
    "//// A planted module.",
    "",
    "import gleam/list",
    "import " <> module,
    "",
    "pub fn size() -> Int {",
    "  list.length([])",
    "}",
  ]
}

pub fn the_allow_lists_are_read_from_the_project_file_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let project_file =
    string.join(
      [
        "name = \"planted\"",
        "",
        "[tools.code_rules]",
        "effectful_modules = [",
        "  { module = \"planted/server\", reason = \"the top supervisor\" },",
        "  { module = \"planted/socket\", reason = \"owns a socket\" },",
        "]",
        "pure_erlang = [\"erlang:abs\", \"lists:reverse\"]",
        "atom_or_term = []",
      ],
      "\n",
    )
  assert purity.allowed(project_file)
    == Allowed(
      effectful_modules: ["planted/server", "planted/socket"],
      pure_erlang: ["erlang:abs", "lists:reverse"],
    )
}

pub fn a_module_not_listed_as_effectful_that_imports_a_process_otp_database_or_logging_module_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let modules = [
    "gleam/erlang/process",
    "gleam/erlang/process.{type Pid}",
    "gleam/otp/actor",
    "gleam/otp/static_supervisor",
    "pog",
    "logging",
  ]
  list.each(modules, fn(module) {
    let file = planted.file("src/planted/rule.gleam", importing(module))
    assert planted.lines(purity.breaches(file, nothing_allowed())) == [4]
      as { "no breach for importing " <> module }
  })
}

pub fn a_rule_that_sends_a_message_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("src/planted/rule.gleam", [
      "import gleam/erlang/process.{type Subject}",
      "",
      "pub fn announce(subject: Subject(Int)) -> Nil {",
      "  process.send(subject, 1)",
      "}",
    ])
  assert planted.lines(purity.breaches(file, nothing_allowed())) == [1]
}

pub fn a_module_listed_as_effectful_may_import_what_a_rule_may_not_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let allowed = Allowed(effectful_modules: ["planted/server"], pure_erlang: [])
  let file =
    planted.file("src/planted/server.gleam", [
      "import gleam/erlang/process",
      "import gleam/otp/actor",
      "import pog",
      "import logging",
      "@external(erlang, \"erlang\", \"monotonic_time\") pub fn clock() -> Int",
    ])
  assert purity.breaches(file, allowed) == []
}

pub fn a_rule_that_imports_no_effectful_module_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("src/planted/rule.gleam", [
      "import gleam/dict",
      "import gleam/erlang/atom",
      "import gleam/list",
      "import gleam/option.{type Option}",
      "import planted/other",
      "",
      "pub fn size() -> Int {",
      "  list.length([])",
      "}",
    ])
  assert purity.breaches(file, nothing_allowed()) == []
}

pub fn an_external_to_an_erlang_function_off_the_allow_list_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("src/planted/rule.gleam", [
      "//// A planted rule that reads the clock.",
      "",
      "@external(erlang, \"erlang\", \"monotonic_time\") pub fn clock() -> Int",
    ])
  assert planted.lines(purity.breaches(file, nothing_allowed())) == [3]
}

pub fn an_external_to_an_erlang_function_on_the_allow_list_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let allowed = Allowed(effectful_modules: [], pure_erlang: ["erlang:abs"])
  let file =
    planted.file("src/planted/rule.gleam", [
      "@external(erlang, \"erlang\", \"abs\") pub fn absolute(a: Int) -> Int",
      "@external(erlang, \"erlang\", \"monotonic_time\") pub fn clock() -> Int",
    ])
  assert planted.lines(purity.breaches(file, allowed)) == [2]
}

pub fn each_breach_is_reported_at_its_own_line_in_order_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("src/planted/rule.gleam", [
      "import gleam/list",
      "import gleam/erlang/process",
      "@external(erlang, \"erlang\", \"monotonic_time\") pub fn clock() -> Int",
      "import logging",
    ])
  assert planted.lines(purity.breaches(file, nothing_allowed())) == [2, 3, 4]
}

pub fn no_module_in_src_breaks_the_rule_with_the_real_project_file_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let assert Ok(project_file) = simplifile.read("gleam.toml")
    as "gleam.toml could not be read"
  let allowed = purity.allowed(project_file)
  let files = repository.sources(["src"])
  assert list.flat_map(files, purity.breaches(_, allowed)) == []
}

pub fn the_game_connection_rule_and_the_features_it_holds_are_pure_rules_the_check_covers_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let assert Ok(project_file) = simplifile.read("gleam.toml")
    as "gleam.toml could not be read"
  let allowed = purity.allowed(project_file)
  let rules = [
    "src/genesis_prime/game/connection.gleam",
    "src/genesis_prime/game/character_select.gleam",
    "src/genesis_prime/game/character_creation.gleam",
    "src/genesis_prime/game/character_name.gleam",
    "src/genesis_prime/game/appearance.gleam",
  ]
  let files =
    list.filter(repository.sources(["src"]), fn(file) {
      list.contains(rules, file.path)
    })
  assert list.length(files) == 5
    as "every module is among the files the purity rule reads"
  assert list.flat_map(files, purity.breaches(_, allowed)) == []
    as "CLAUDE.md: every game and connection decision is a rule, a pure function"
  // The harness can fail: the same modules with a process import are breaches.
  list.each(files, fn(file) {
    let with_effect =
      SourceFile(
        path: file.path,
        text: file.text <> "\nimport gleam/erlang/process\n",
      )
    assert list.length(purity.breaches(with_effect, allowed)) == 1
      as { file.path <> " must be checked, not listed as effectful" }
  })
}
