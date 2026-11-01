//// The server-table rule. Expected values are the step's rule: the server
//// loads only the tables its rules read, so a module outside the table folder
//// that reads a table the server's list lacks is a breach (a new engine adds
//// its table to the list), and so is a listed table nothing reads. A table
//// is listed when the list calls its module's `entry()`, and read when a
//// module imports it. A table module is a module the generated registry
//// imports, outside the loader's folder, so the typed ids and the loader are
//// not tables. The registry, the folder's own modules and the list itself do
//// not count as readers. Every breach is planted in made-up files; the last
//// test runs the rule over the repository.

import code_rule/planted
import code_rule/repository
import code_rule/server_table
import code_rule/source.{type SourceFile}
import gleam/list
import owned_test
import unitest

fn registry() -> SourceFile {
  planted.file(path: server_table.registry_path, lines: [
    "//// A planted registry.",
    "import genesis_prime/table/creature2",
    "import genesis_prime/table/loader/store",
    "import genesis_prime/table/spell4",
    "import genesis_prime/table/world",
  ])
}

/// A list that imports each table and calls its `entry()`.
fn listing(tables: List(String)) -> SourceFile {
  listing_of(imports: tables, entries: tables)
}

/// A list that imports some tables and calls the `entry()` of some.
fn listing_of(
  imports imports: List(String),
  entries entries: List(String),
) -> SourceFile {
  planted.file(path: server_table.list_path, lines: [
    "//// A planted list.",
    "import genesis_prime/table/loader/store",
    ..list.flatten([
      list.map(imports, fn(table) { "import genesis_prime/table/" <> table }),
      ["pub fn entries() {", "  ["],
      list.map(entries, fn(table) { "    " <> table <> ".entry()," }),
      ["  ]", "}"],
    ])
  ])
}

fn reader(path: String, imports: List(String)) -> SourceFile {
  planted.file(path:, lines: [
    "//// A planted rule.",
    ..list.map(imports, fn(module) { "import " <> module })
  ])
}

pub fn a_module_reading_a_table_the_list_lacks_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let breaches =
    server_table.breaches([
      registry(),
      listing(["creature2"]),
      reader("src/genesis_prime/game/creature.gleam", [
        "genesis_prime/table/creature2",
      ]),
      reader("src/genesis_prime/game/spell.gleam", [
        "genesis_prime/message/frame",
        "genesis_prime/table/spell4",
      ]),
    ])
  assert list.map(breaches, fn(breach) { #(breach.path, breach.line) })
    == [#("src/genesis_prime/game/spell.gleam", 3)]
    as "the import of Spell4, which the list lacks, is on line 3 of the module that reads it"
}

pub fn a_listed_table_that_no_module_reads_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let breaches =
    server_table.breaches([
      registry(),
      listing(["creature2", "world"]),
      reader("src/genesis_prime/game/creature.gleam", [
        "genesis_prime/table/creature2",
      ]),
    ])
  assert list.map(breaches, fn(breach) { #(breach.path, breach.line) })
    == [#(server_table.list_path, 1)]
    as "World is listed and nothing outside the table folder reads it"
}

pub fn a_table_the_list_imports_without_calling_its_entry_is_not_listed_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let breaches =
    server_table.breaches([
      registry(),
      listing_of(imports: ["creature2", "spell4"], entries: ["creature2"]),
      reader("src/genesis_prime/game/creature.gleam", [
        "genesis_prime/table/creature2",
      ]),
      reader("src/genesis_prime/game/spell.gleam", [
        "genesis_prime/table/spell4",
      ]),
    ])
  assert list.map(breaches, fn(breach) { #(breach.path, breach.line) })
    == [#("src/genesis_prime/game/spell.gleam", 2)]
    as "the list imports Spell4 and never calls its entry(), so the server does not load it and the module that reads it breaches"
}

pub fn a_listed_entry_called_through_an_alias_is_listed_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let aliased =
    planted.file(path: server_table.list_path, lines: [
      "//// A planted list.",
      "import genesis_prime/table/creature2 as creature",
      "pub fn entries() { [creature.entry()] }",
    ])
  assert server_table.breaches([
      registry(),
      aliased,
      reader("src/genesis_prime/game/creature.gleam", [
        "genesis_prime/table/creature2",
      ]),
    ])
    == []
    as "an alias names the module the call goes to"
}

pub fn a_list_that_is_the_tables_read_has_no_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert server_table.breaches([
      registry(),
      listing(["creature2", "spell4"]),
      reader("src/genesis_prime/game/creature.gleam", [
        "genesis_prime/table/creature2",
        "genesis_prime/table/loader/store",
      ]),
      reader("src/genesis_prime/game/spell.gleam", [
        "genesis_prime/table/spell4",
        "genesis_prime/table/creature2",
      ]),
    ])
    == []
}

pub fn the_loader_the_table_folder_and_the_registry_are_not_readers_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let breaches =
    server_table.breaches([
      registry(),
      listing(["creature2"]),
      reader("src/genesis_prime/game/creature.gleam", [
        "genesis_prime/table/creature2",
      ]),
      reader("src/genesis_prime/table/loader/requirement.gleam", [
        "genesis_prime/table/world",
      ]),
      reader("src/genesis_prime/table/spell4.gleam", [
        "genesis_prime/table/world",
      ]),
      reader("src/genesis_prime/table.gleam", ["genesis_prime/table/world"]),
    ])
  assert breaches == []
    as "the registry and the modules under the table folder import tables without any rule reading them"
}

pub fn a_module_that_is_not_a_table_is_not_a_read_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert server_table.breaches([
      registry(),
      listing(["creature2"]),
      reader("src/genesis_prime/game/creature.gleam", [
        "genesis_prime/table/creature2",
        "genesis_prime/table/id",
      ]),
    ])
    == []
    as "the typed ids are not in the registry, so they are not a table"
}

pub fn a_missing_list_or_registry_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let missing_list = server_table.breaches([registry()])
  assert list.map(missing_list, fn(breach) { breach.path })
    == [server_table.list_path]
  let missing_registry = server_table.breaches([listing([])])
  assert list.map(missing_registry, fn(breach) { breach.path })
    == [server_table.registry_path]
}

pub fn the_servers_table_list_is_the_tables_the_repository_reads_test() -> Nil {
  use <- owned_test.run(20_000)
  use <- unitest.tag("code_rule")
  let files = repository.sources(under: ["src"])
  assert server_table.breaches(files) == []
}
