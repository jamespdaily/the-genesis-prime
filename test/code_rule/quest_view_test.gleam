//// The quest view rules (`code_rule/quest_view`): which modules may import the
//// quest log and which may build a view. The cases are planted; the real-tree
//// tests run the rules over the real `src`, `dev` and `test`.

import code_rule/level.{type Level, Character, Link, Map, Shared, Unit}
import code_rule/planted
import code_rule/quest_view
import code_rule/repository
import code_rule/source
import gleam/int
import gleam/list
import gleam/string
import owned_test
import unitest

fn importing_the_log(module: String) -> source.SourceFile {
  planted.file("src/" <> module <> ".gleam", [
    "//// A planted module.", "import genesis_prime/game/quest_log",
    "import gleam/list",
  ])
}

fn rows(modules: List(#(String, Level))) -> List(level.Row) {
  list.index_map(modules, fn(module, index) {
    level.Row(module: module.0, level: module.1, line: index + 1)
  })
}

fn breach_summary(breaches: List(source.Breach)) -> String {
  breaches
  |> list.map(fn(breach) {
    breach.path <> ":" <> int.to_string(breach.line) <> " " <> breach.rule
  })
  |> string.join("\n")
}

pub fn a_unit_map_or_shared_module_importing_the_quest_log_fails_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let table =
    rows([
      #("planted/character", Character),
      #("planted/link", Link),
      #("planted/map", Map),
      #("planted/shared", Shared),
      #("planted/unit", Unit),
    ])
  list.each(
    [
      #("planted/unit", [2], "a unit module imports the quest log"),
      #("planted/map", [2], "a map module imports the quest log"),
      #("planted/shared", [2], "a shared module imports the quest log"),
      #("planted/character", [], "a character module may import it"),
      #("planted/link", [], "a link module, which holds the log, may import it"),
    ],
    fn(row) {
      let #(module, expected, reason) = row
      let file = importing_the_log(module)
      let breaches = quest_view.log_import_breaches(files: [file], rows: table)
      assert planted.lines(breaches) == expected as reason
      assert list.all(breaches, fn(breach) { breach.path == file.path })
        as { reason <> ": the breach is at the importing file" }
    },
  )
}

pub fn no_unit_map_or_shared_module_of_the_real_tree_imports_the_quest_log_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  let breaches =
    quest_view.log_import_breaches(
      files: repository.sources(under: ["src"]),
      rows: level.parse_rows(source.read(level.list_path)),
    )
  assert breaches == [] as breach_summary(breaches)
}

pub fn the_quest_view_is_built_only_by_the_quest_log_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  let calling = fn(path, import_line, call) {
    planted.file("src/" <> path <> ".gleam", [
      "//// A planted module.",
      import_line,
      "pub fn view() {",
      "  " <> call,
      "}",
    ])
  }
  list.each(
    [
      #(
        calling(
          "planted/character",
          "import genesis_prime/shared/quest_view",
          "quest_view.of(entries: dict.new())",
        ),
        [4],
        "a call through the module's name",
      ),
      #(
        calling(
          "planted/aliased",
          "import genesis_prime/shared/quest_view as snapshot",
          "snapshot.of(entries: dict.new())",
        ),
        [4],
        "a call through an alias",
      ),
      #(
        calling(
          "planted/unqualified",
          "import genesis_prime/shared/quest_view.{of}",
          "of(entries: dict.new())",
        ),
        [4],
        "a call of an unqualified import",
      ),
      #(
        calling(
          "genesis_prime/game/quest_log",
          "import genesis_prime/shared/quest_view",
          "quest_view.of(entries: dict.new())",
        ),
        [],
        "the quest log builds its view",
      ),
      #(
        calling(
          "planted/reader",
          "import genesis_prime/shared/quest_view",
          "quest_view.state(view:, quest:)",
        ),
        [],
        "a read of a view builds none",
      ),
    ],
    fn(row) {
      let #(file, expected, reason) = row
      assert planted.lines(quest_view.view_builder_breaches(files: [file]))
        == expected
        as reason
    },
  )
  let breaches =
    quest_view.view_builder_breaches(
      files: repository.sources(under: ["src", "dev", "test"]),
    )
  assert breaches == [] as breach_summary(breaches)
}
