//// The dev-module rule: every module in `dev/` is used by a check (`check`),
//// a test or a CI job (`.github/workflows`), or the allow-list below names it
//// with an open issue. Expected values are the cleanup issue's rule: a tool
//// nothing runs is deleted, so an unused module is a breach and an unused
//// module that waits on a decision says which issue holds it.
////
//// A module is used when a test imports it, a runner runs it with `-m`, or a
//// used module of `dev/` imports it; a comment in a runner does not use it.

import code_rule/dev_module
import code_rule/planted
import code_rule/repository
import code_rule/source.{type SourceFile, SourceFile}
import gleam/list
import gleam/string
import owned_test
import simplifile
import unitest

/// Modules of `dev/` that no check, test or CI job uses, each with the open
/// issue that decides whether it gets one or is deleted.
const allowed = [
  #("genesis_prime/coverage", 47),
  #("genesis_prime/record", 119),
]

fn module_file(module: String, imports: List(String)) -> SourceFile {
  planted.file(path: "dev/" <> module <> ".gleam", lines: [
    "//// A planted module.",
    ..list.map(imports, fn(imported) { "import " <> imported })
  ])
}

fn test_importing(module: String) -> SourceFile {
  planted.file(path: "test/planted_test.gleam", lines: ["import " <> module])
}

fn runner(lines: List(String)) -> SourceFile {
  planted.file(path: "check", lines:)
}

fn unused_modules(
  dev dev: List(SourceFile),
  tests tests: List(SourceFile),
  runners runners: List(SourceFile),
  allowed allowed: List(#(String, Int)),
) -> List(String) {
  dev_module.breaches(dev:, tests:, runners:, allowed:)
  |> list.map(fn(breach) { breach.rule })
}

pub fn a_module_that_nothing_uses_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let dev = [
    module_file("genesis_prime/used", []),
    module_file("genesis_prime/orphan", []),
  ]
  let breaches =
    dev_module.breaches(
      dev:,
      tests: [test_importing("genesis_prime/used")],
      runners: [],
      allowed: [],
    )
  let assert [breach] = breaches as "expected exactly one breach"
  assert breach.path == "dev/genesis_prime/orphan.gleam"
  assert string.ends_with(breach.rule, "genesis_prime/orphan")
}

pub fn a_module_a_test_imports_is_used_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let tests = [test_importing("genesis_prime/tool.{type Tool}")]
  assert unused_modules(
      dev: [module_file("genesis_prime/tool", [])],
      tests:,
      runners: [],
      allowed: [],
    )
    == []
}

pub fn a_module_a_runner_runs_with_dash_m_is_used_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let runners = [runner(["gleam run -m genesis_prime/tool check"])]
  assert unused_modules(
      dev: [module_file("genesis_prime/tool", [])],
      tests: [],
      runners:,
      allowed: [],
    )
    == []
}

pub fn a_module_only_a_runner_comment_names_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let runners = [runner(["  # gleam run -m genesis_prime/tool check"])]
  assert list.length(
      unused_modules(
        dev: [module_file("genesis_prime/tool", [])],
        tests: [],
        runners:,
        allowed: [],
      ),
    )
    == 1
}

pub fn a_module_a_used_module_imports_is_used_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let dev = [
    module_file("genesis_prime/tool", ["genesis_prime/tool/part"]),
    module_file("genesis_prime/tool/part", ["genesis_prime/tool/detail"]),
    module_file("genesis_prime/tool/detail", []),
  ]
  assert unused_modules(
      dev:,
      tests: [test_importing("genesis_prime/tool")],
      runners: [],
      allowed: [],
    )
    == []
}

pub fn a_module_only_an_unused_module_imports_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let dev = [
    module_file("genesis_prime/orphan", ["genesis_prime/orphan/part"]),
    module_file("genesis_prime/orphan/part", []),
  ]
  assert list.length(unused_modules(dev:, tests: [], runners: [], allowed: []))
    == 2
}

pub fn a_longer_module_name_does_not_use_a_shorter_one_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let dev = [
    module_file("genesis_prime/table", []),
    module_file("genesis_prime/table_generator", []),
  ]
  let breaches =
    dev_module.breaches(
      dev:,
      tests: [test_importing("genesis_prime/table_generator")],
      runners: [],
      allowed: [],
    )
  let assert [breach] = breaches as "expected exactly one breach"
  assert breach.path == "dev/genesis_prime/table.gleam"
}

pub fn a_module_on_the_allow_list_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert unused_modules(
      dev: [module_file("genesis_prime/waiting", [])],
      tests: [],
      runners: [],
      allowed: [#("genesis_prime/waiting", 129)],
    )
    == []
}

pub fn an_allow_list_entry_for_a_module_that_is_gone_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let breaches =
    dev_module.breaches(
      dev: [module_file("genesis_prime/used", [])],
      tests: [test_importing("genesis_prime/used")],
      runners: [],
      allowed: [#("genesis_prime/gone", 129)],
    )
  let assert [breach] = breaches as "expected exactly one breach"
  assert string.ends_with(breach.rule, "genesis_prime/gone")
}

pub fn every_module_in_dev_is_used_or_allowed_with_an_issue_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  let dev = source.files("dev")
  assert list.length(dev) >= 5 as "the dev modules were not found"
  let runners =
    repository.tracked_paths()
    |> list.filter(fn(path) {
      path == "check" || string.starts_with(path, ".github/workflows/")
    })
    |> list.map(fn(path) { SourceFile(path:, text: read(path)) })
  assert list.length(runners) >= 2
    as "the check and the workflows were not found"
  assert dev_module.breaches(
      dev:,
      tests: repository.sources(under: ["test"]),
      runners:,
      allowed:,
    )
    == []
}

fn read(path: String) -> String {
  let assert Ok(text) = simplifile.read(path) as { "could not read " <> path }
  text
}

pub fn a_commented_out_import_does_not_use_a_module_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let tests = [
    planted.file(path: "test/planted_test.gleam", lines: [
      "// import genesis_prime/tool",
    ]),
  ]
  assert unused_modules(
      dev: [module_file("genesis_prime/tool", [])],
      tests:,
      runners: [],
      allowed: [],
    )
    == [
      "a module in dev/ that no check, test or CI job uses: genesis_prime/tool",
    ]
}

pub fn a_run_after_a_comment_mark_on_a_runner_line_does_not_use_a_module_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert unused_modules(
      dev: [module_file("genesis_prime/tool", [])],
      tests: [],
      runners: [runner(["echo skipped # gleam run -m genesis_prime/tool"])],
      allowed: [],
    )
    == [
      "a module in dev/ that no check, test or CI job uses: genesis_prime/tool",
    ]
}
