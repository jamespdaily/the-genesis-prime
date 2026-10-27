//// The domain rule. Expected values are the folder-tree issue's plan and test
//// list: one top-level folder or module under `src/genesis_prime/` per game
//// domain, each listed under `[tools.code_rules]` in the Gleam project file
//// with its reason, as `effectful_modules` is (test 1: every top-level folder
//// or module is a listed domain; test 4: every listed domain has a reason).
//// This follows the writing-gleam skill, Modules: "Name and split modules by
//// game domain". A domain is listed as the module path of its folder or
//// module, `genesis_prime/server`; the root module `src/genesis_prime.gleam`
//// is the package's entry point and under no domain. Every breach is planted
//// in a made-up file.

import code_rule/domain.{Domain}
import code_rule/planted
import code_rule/repository
import gleam/list
import gleam/string
import owned_test
import simplifile
import unitest

fn listed() -> List(domain.Domain) {
  [
    Domain(module: "genesis_prime/server", reason: "the top supervisor"),
    Domain(module: "genesis_prime/map", reason: "the map process"),
  ]
}

fn read(path: String) -> String {
  let assert Ok(text) = simplifile.read(path) as { "could not read " <> path }
  text
}

pub fn the_domains_are_read_with_their_reasons_from_the_project_file_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let project_file =
    string.join(
      [
        "name = \"planted\"",
        "",
        "[tools.code_rules]",
        "effectful_modules = [",
        "  { module = \"genesis_prime/server\", reason = \"the top supervisor\" },",
        "]",
        "domains = [",
        "  { module = \"genesis_prime/server\", reason = \"the top supervisor\" },",
        "  { module = \"genesis_prime/map\", reason = \"the map process\" },",
        "]",
      ],
      "\n",
    )
  assert domain.domains(project_file) == listed()
}

pub fn a_project_file_with_no_domains_lists_none_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert domain.domains("name = \"planted\"\n") == []
}

pub fn a_folder_that_is_not_a_listed_domain_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("src/genesis_prime/weather/forecast.gleam", [
      "pub fn today() -> Int {",
      "  1",
      "}",
    ])
  let assert [breach] = domain.unlisted([file], listed())
    as "expected exactly one breach"
  assert breach.path == "src/genesis_prime/weather/forecast.gleam"
  assert breach.line == 1
  assert string.contains(breach.rule, "genesis_prime/weather")
}

pub fn a_module_that_is_not_a_listed_domain_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("src/genesis_prime/weather.gleam", ["pub const a = 1"])
  let assert [breach] = domain.unlisted([file], listed())
    as "expected exactly one breach"
  assert breach.path == "src/genesis_prime/weather.gleam"
  assert string.contains(breach.rule, "genesis_prime/weather")
}

pub fn a_domain_name_that_only_starts_like_a_listed_domain_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let files = [
    planted.file("src/genesis_prime/server_extra.gleam", ["pub const a = 1"]),
    planted.file("src/genesis_prime/maps/tile.gleam", ["pub const a = 1"]),
  ]
  assert list.map(domain.unlisted(files, listed()), fn(breach) { breach.path })
    == [
      "src/genesis_prime/server_extra.gleam",
      "src/genesis_prime/maps/tile.gleam",
    ]
}

pub fn a_file_in_a_listed_domain_at_any_depth_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let files = [
    planted.file("src/genesis_prime/server.gleam", ["pub const a = 1"]),
    planted.file("src/genesis_prime/server/supervisor.gleam", [
      "pub const a = 1",
    ]),
    planted.file("src/genesis_prime/map/zone/tile.gleam", ["pub const a = 1"]),
  ]
  assert domain.unlisted(files, listed()) == []
}

pub fn the_root_module_is_under_no_domain_and_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file = planted.file("src/genesis_prime.gleam", ["pub fn main() { Nil }"])
  assert domain.unlisted([file], listed()) == []
}

pub fn no_folder_or_module_under_src_is_outside_the_listed_domains_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let domains = domain.domains(read("gleam.toml"))
  assert domains != [] as "no domain is listed in gleam.toml"
  assert domain.unlisted(repository.sources(["src"]), domains) == []
}

pub fn a_listed_domain_with_an_empty_reason_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let domains = [
    Domain(module: "genesis_prime/server", reason: "the top supervisor"),
    Domain(module: "genesis_prime/map", reason: ""),
    Domain(module: "genesis_prime/login", reason: "   "),
  ]
  assert domain.unexplained(domains)
    == ["genesis_prime/map", "genesis_prime/login"]
}

pub fn a_listed_domain_with_a_reason_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert domain.unexplained(listed()) == []
}

pub fn every_domain_listed_in_the_project_file_has_a_reason_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let domains = domain.domains(read("gleam.toml"))
  assert domains != [] as "no domain is listed in gleam.toml"
  assert domain.unexplained(domains) == []
}
