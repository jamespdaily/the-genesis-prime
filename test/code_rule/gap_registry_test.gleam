//// The gap-registry rule: a module in `src` that declares `pub fn gaps()` is called by the
//// registry as `<alias>.gaps()`. Each breach is planted once in made-up files; the last
//// tests run the rule over the tree and over the modules the schema generates. Expected values are the rule's own: the registry is
//// the one place the measure reads the entries from, so a module it does not call has
//// entries nobody sees.

import code_rule/gap_registry
import code_rule/planted
import code_rule/repository
import code_rule/source.{type SourceFile, Breach, SourceFile}
import genesis_prime/message_generator
import gleam/list
import gleam/string
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
  assert gap_registry.breaches(
      files: [planted_module()],
      registry: planted.file("dev/genesis_prime/coverage/gaps.gleam", [
        "import genesis_prime/game/planted_module",
        "",
        "pub fn registry() -> List(String) {",
        "  planted_module.gaps(1)",
        "}",
      ]),
    )
    == [breach]
    as "a call of gaps with an argument is no call of the function that takes none"
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

pub fn the_registry_calls_the_gaps_of_every_generated_message_module_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  let generated_path = "src/genesis_prime/message/planted_message.gleam"
  let generated_module =
    planted.file(generated_path, [
      message_generator.generated_marker
        <> " by `genesis_prime/generate_messages`;",
      "//// never edited by hand.",
      "",
      "import genesis_prime/gap",
      "",
      "/// What this message's codec leaves unhandled, which the coverage measure prints.",
      "pub fn gaps() -> List(gap.Entry) {",
      "  []",
      "}",
    ])
  assert gap_registry.breaches(
      files: [generated_module],
      registry: registry_with(["  []", "}"]),
    )
    == [
      Breach(
        path: generated_path,
        line: 7,
        rule: "a module with gaps the registry does not call",
      ),
    ]
    as "a generated module the registry does not call is a breach at its declaration"
  assert gap_registry.breaches(
      files: [generated_module],
      registry: planted.file("dev/genesis_prime/coverage/gaps.gleam", [
        "import genesis_prime/message/planted_message",
        "",
        "pub fn registry() -> List(String) {",
        "  planted_message.gaps()",
        "}",
      ]),
    )
    == []
    as "a generated module the registry calls is no breach"
  let assert Ok(files) = message_generator.generated_files()
    as "the schema generates its modules"
  let with_gaps =
    list.filter_map(files, fn(file) {
      case string.contains(file.text, "\npub fn gaps() -> List(gap.Entry) {") {
        True -> Ok(SourceFile(path: file.path, text: file.text))
        False -> Error(Nil)
      }
    })
  assert list.length(with_gaps) >= 10
    as "the real schema gives ten messages and records gaps"
  let assert [registry] =
    list.filter(repository.sources(under: ["dev"]), fn(file) {
      file.path == "dev/genesis_prime/coverage/gaps.gleam"
    })
    as "the registry is a file of dev"
  assert gap_registry.breaches(files: with_gaps, registry:) == []
    as "the registry calls the gaps of every module the generator writes with one"
}
