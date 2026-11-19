//// The gap-registry rule: a module in `src` that declares `pub fn gaps()` is called by the
//// registry as `<alias>.gaps()`. Each breach is planted once in made-up files; the last
//// test runs the rule over the tree. Expected values are the rule's own: the registry is
//// the one place the measure reads the entries from, so a module it does not call has
//// entries nobody sees.

import code_rule/gap_registry
import code_rule/planted
import code_rule/repository
import code_rule/source.{type SourceFile, Breach}
import gleam/list
import owned_test
import unitest

const module_path = "src/genesis_prime/game/planted_module.gleam"

fn planted_module() -> SourceFile {
  planted.file(module_path, [
    "//// A planted module.",
    "",
    "pub fn gaps() -> List(String) {",
    "  []",
    "}",
  ])
}

fn registry_with(lines: List(String)) -> SourceFile {
  planted.file("dev/genesis_prime/coverage/gaps.gleam", [
    "pub fn registry() -> List(String) {",
    ..lines
  ])
}

pub fn a_module_with_gaps_the_registry_does_not_call_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let breach =
    Breach(
      path: module_path,
      line: 3,
      rule: "a module with gaps the registry does not call",
    )
  assert gap_registry.breaches(
      files: [planted_module()],
      registry: registry_with(["  []", "}"]),
    )
    == [breach]
    as "a module the registry does not import is a breach at its declaration"
  assert gap_registry.breaches(
      files: [planted_module()],
      registry: planted.file("dev/genesis_prime/coverage/gaps.gleam", [
        "import genesis_prime/game/planted_module",
        "",
        "pub fn registry() -> List(String) {",
        "  []",
        "}",
      ]),
    )
    == [breach]
    as "an import with no call of gaps() is a breach"
  assert gap_registry.breaches(
      files: [planted_module()],
      registry: planted.file("dev/genesis_prime/coverage/gaps.gleam", [
        "import genesis_prime/game/planted_module",
        "",
        "pub fn registry() -> List(String) {",
        "  [planted_module.gaps]",
        "}",
      ]),
    )
    == [breach]
    as "a mention of the function that does not call it is a breach"
}

pub fn a_module_the_registry_calls_is_no_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert gap_registry.breaches(
      files: [planted_module()],
      registry: planted.file("dev/genesis_prime/coverage/gaps.gleam", [
        "import genesis_prime/game/planted_module",
        "",
        "pub fn registry() -> List(String) {",
        "  planted_module.gaps()",
        "}",
      ]),
    )
    == []
    as "the call by the module's name"
  assert gap_registry.breaches(
      files: [planted_module()],
      registry: planted.file("dev/genesis_prime/coverage/gaps.gleam", [
        "import genesis_prime/game/planted_module as planted",
        "",
        "pub fn registry() -> List(String) {",
        "  planted.gaps()",
        "}",
      ]),
    )
    == []
    as "the call by the module's alias"
  assert gap_registry.breaches(
      files: [
        planted.file(module_path, [
          "pub fn gaps_of(row: Int) -> List(String) {",
          "  []",
          "}",
          "",
          "fn gaps() -> List(String) {",
          "  []",
          "}",
        ]),
      ],
      registry: registry_with(["  []", "}"]),
    )
    == []
    as "a function with parameters, or a private one, is no declaration of gaps"
}

pub fn every_src_module_that_declares_gaps_is_called_by_the_registry_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  let assert [registry] =
    list.filter(repository.sources(under: ["dev"]), fn(file) {
      file.path == "dev/genesis_prime/coverage/gaps.gleam"
    })
    as "the registry is a file of dev"
  assert gap_registry.breaches(
      files: repository.sources(under: ["src"]),
      registry:,
    )
    == []
}
