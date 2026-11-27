//// The levels rule: every hand-written module of `src` has one row in the
//// levels table, and a module of an enforced level imports no level its row
//// of the matrix forbids. The cases are planted; the real-tree tests run the
//// rule over the real `src/` and the real table.

import code_rule/level.{
  type Level, Character, Data, Host, Link, Map, Platform, Row, Shared, Unit,
}
import code_rule/planted
import code_rule/repository
import code_rule/source.{type SourceFile}
import gleam/int
import gleam/list
import gleam/string
import owned_test
import unitest

/// A planted module of `src` with the named imports, one to a line from
/// line 1.
fn module_file(name: String, imports: List(String)) -> SourceFile {
  planted.file(
    "src/" <> name <> ".gleam",
    list.map(imports, fn(module) { "import " <> module }),
  )
}

/// The planted rows of the modules, in order, one to a line from line 1.
fn rows(modules: List(#(String, Level))) -> List(level.Row) {
  list.index_map(modules, fn(module, index) {
    Row(module: module.0, level: module.1, line: index + 1)
  })
}

/// Whether the file's path is a hand-written module of the repository:
/// not generated message, table or SQL code.
fn is_hand_written(path: String) -> Bool {
  !string.contains(path, "/message/")
  && !string.contains(path, "/table/")
  && !string.ends_with(path, "/sql.gleam")
}

pub fn every_hand_written_module_is_in_the_levels_table_once_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  let files = repository.sources(under: ["src"])
  let table = level.parse_rows(source.read(level.list_path))
  let breaches = level.table_breaches(files:, rows: table)
  assert breaches == []
    as {
      int.to_string(list.length(breaches))
      <> " breaches, the first: "
      <> string.inspect(list.first(breaches))
    }
  let tree_modules =
    files
    |> list.filter(fn(file) { is_hand_written(file.path) })
    |> list.map(fn(file) {
      file.path
      |> string.remove_prefix("src/")
      |> string.remove_suffix(".gleam")
    })
    |> list.sort(string.compare)
  assert list.map(table, fn(row) { row.module }) == tree_modules
    as "the table's modules differ from the files of src"
}

pub fn a_levels_table_row_for_a_deleted_module_fails_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let present = module_file("genesis_prime/present", [])
  let breaches =
    level.table_breaches(
      files: [present],
      rows: rows([
        #("genesis_prime/gone", Data),
        #("genesis_prime/present", Data),
      ]),
    )
  assert planted.lines(breaches) == [1]
  assert list.all(breaches, fn(breach) { breach.path == level.list_path })
    as "the breach is at the table"
}

pub fn an_unlisted_module_and_a_repeated_or_disordered_row_fail_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let first = module_file("genesis_prime/a", [])
  let second = module_file("genesis_prime/b", [])
  list.each(
    [
      #(
        [first, second],
        [#("genesis_prime/a", Data)],
        [1],
        "a module with no row",
      ),
      #(
        [first],
        [#("genesis_prime/a", Data), #("genesis_prime/a", Data)],
        [2],
        "a repeated row",
      ),
      #(
        [first, second],
        [#("genesis_prime/b", Data), #("genesis_prime/a", Data)],
        [2],
        "a row out of order",
      ),
      #(
        [first, second],
        [#("genesis_prime/a", Data), #("genesis_prime/b", Data)],
        [],
        "in order, one row each",
      ),
    ],
    fn(row) {
      let #(files, table, expected, reason) = row
      assert planted.lines(level.table_breaches(files:, rows: rows(table)))
        == expected
        as reason
    },
  )
}

pub fn a_module_importing_a_level_the_matrix_forbids_fails_when_that_level_is_enforced_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let table =
    rows([
      #("genesis_prime/reader", Data),
      #("genesis_prime/runner", Platform),
      #("genesis_prime/rules", Shared),
      #("genesis_prime/server", Platform),
    ])
  list.each(
    [
      #(
        module_file("genesis_prime/reader", [
          "gleam/list", "genesis_prime/server",
        ]),
        [2],
        "a data module imports a platform module",
      ),
      #(
        module_file("genesis_prime/runner", [
          "genesis_prime/server", "genesis_prime/rules",
        ]),
        [2],
        "a platform module imports a shared module",
      ),
      #(
        module_file("genesis_prime/runner", [
          "genesis_prime/reader", "genesis_prime/server",
        ]),
        [],
        "a platform module imports data and platform",
      ),
    ],
    fn(row) {
      let #(file, expected, reason) = row
      let breaches =
        level.import_breaches(files: [file], rows: table, enforced: [
          Data,
          Platform,
        ])
      assert planted.lines(breaches) == expected as reason
      assert list.all(breaches, fn(breach) { breach.path == file.path })
        as { reason <> ": the breach is at the importing file" }
    },
  )
}

pub fn a_level_that_is_not_enforced_reports_no_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let table =
    rows([
      #("genesis_prime/reader", Data),
      #("genesis_prime/server", Platform),
      #("genesis_prime/body", Unit),
      #("genesis_prime/shell", Host),
    ])
  let reader = module_file("genesis_prime/reader", ["genesis_prime/server"])
  let shell = module_file("genesis_prime/shell", ["genesis_prime/body"])
  assert planted.lines(
      level.import_breaches(files: [reader], rows: table, enforced: [Platform]),
    )
    == []
    as "data is not enforced"
  assert planted.lines(
      level.import_breaches(files: [reader, shell], rows: table, enforced: [
        Data,
        Platform,
      ]),
    )
    == [1]
    as "the host imports every level, so only data breaks"
}

pub fn a_level_may_import_only_the_message_modules_of_the_levels_it_talks_to_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let table =
    rows([
      #("genesis_prime/link/rule", Link),
      #("genesis_prime/character/rule", Character),
      #("genesis_prime/character/message", Character),
      #("genesis_prime/character/state", Character),
      #("genesis_prime/unit/message", Unit),
      #("genesis_prime/map/rule", Map),
    ])
  list.each(
    [
      #(
        "genesis_prime/link/rule",
        "genesis_prime/character/message",
        [],
        "link to character message",
      ),
      #(
        "genesis_prime/link/rule",
        "genesis_prime/character/state",
        [1],
        "link to character state",
      ),
      #(
        "genesis_prime/character/rule",
        "genesis_prime/unit/message",
        [],
        "character to unit message",
      ),
      #(
        "genesis_prime/character/rule",
        "genesis_prime/character/state",
        [],
        "a level's own module",
      ),
      #(
        "genesis_prime/map/rule",
        "genesis_prime/character/message",
        [1],
        "map to character message",
      ),
    ],
    fn(row) {
      let #(from, to, expected, reason) = row
      assert planted.lines(level.import_breaches(
          files: [module_file(from, [to])],
          rows: table,
          enforced: level.all_levels(),
        ))
        == expected
        as reason
    },
  )
  assert list.all(level.all_levels(), fn(each) {
    list.all(level.contract(each), string.starts_with(_, "genesis_prime/"))
  })
    as "a contract module is named in full"
}

pub fn an_import_is_read_from_a_planted_module_with_aliases_and_a_type_list_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("src/planted.gleam", [
      "//// A module.", "import a/b.{type C} as d", "import gleam/list",
      "import e/f.{g}",
    ])
  assert level.imports_of(file:)
    == [#(2, "a/b"), #(3, "gleam/list"), #(4, "e/f")]
}

/// The lines of this module's doc comment that start with `prefix`, with the
/// `//// ` and the prefix removed.
fn doc_lines(prefix: String) -> List(String) {
  source.read("test/code_rule/level.gleam")
  |> string.split("\n")
  |> list.filter_map(fn(line) {
    case string.starts_with(line, "//// " <> prefix) {
      True -> Ok(string.remove_prefix(line, "//// " <> prefix))
      False -> Error(Nil)
    }
  })
}

fn words(text: String) -> List(String) {
  text |> string.split(" ") |> list.filter(fn(word) { word != "" })
}

pub fn the_enforced_set_equals_the_levels_the_doc_names_as_enforced_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let assert [named] = doc_lines("Enforced levels:")
    as "the doc names the enforced levels on one line"
  assert list.sort(words(named), string.compare)
    == list.sort(list.map(level.enforced, level.name), string.compare)
}

pub fn the_levels_diagram_and_the_matrix_agree_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let diagram = doc_lines("level ")
  assert list.length(diagram) == list.length(level.all_levels())
    as "the diagram has one line for each level"
  list.each(level.all_levels(), fn(each) {
    let assert Ok(line) =
      list.find(diagram, fn(line) {
        string.starts_with(line, level.name(each) <> " ")
      })
      as { "the diagram has no line for " <> level.name(each) }
    let assert [imports, messages] =
      line
      |> string.remove_prefix(level.name(each))
      |> string.split(" messages of")
      as { "the diagram line of " <> level.name(each) <> " is malformed" }
    let names = fn(levels) {
      list.sort(list.map(levels, level.name), string.compare)
    }
    assert list.sort(list.drop(words(imports), 1), string.compare)
      == names(level.imported_levels(each))
      as { level.name(each) <> " imports" }
    assert list.sort(words(messages), string.compare)
      == names(level.message_levels(each))
      as { level.name(each) <> " messages" }
  })
}

pub fn the_real_tree_imports_no_level_its_matrix_row_forbids_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  let breaches =
    level.import_breaches(
      files: repository.sources(under: ["src"]),
      rows: level.parse_rows(source.read(level.list_path)),
      enforced: level.enforced,
    )
  assert breaches == []
    as {
      int.to_string(list.length(breaches))
      <> " breaches, the first: "
      <> string.inspect(list.first(breaches))
    }
}
