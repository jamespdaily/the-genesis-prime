//// The shared-tables rule. A test that loads a real table puts its rows in the
//// VM's literal area beside the one load every test shares, and a run that
//// holds too many copies at once crashes the VM, so a function of a test
//// module that passes the client's folder to a table load is a breach. Every
//// breach is planted in made-up files; the last test runs the rule over the
//// repository's tests.

import code_rule/planted
import code_rule/repository
import code_rule/shared_tables
import code_rule/source.{type SourceFile}
import gleam/list
import owned_test
import unitest

fn test_module(lines: List(String)) -> SourceFile {
  planted.file(path: "test/some_test.gleam", lines: [
    "//// A planted test module.",
    ..lines
  ])
}

pub fn a_function_that_loads_a_table_from_the_clients_folder_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    test_module([
      "import client_tables",
      "import genesis_prime/table/loader/store",
      "fn load(entry) {",
      "  store.load(under: key, from: client_tables.folder(), entries: [entry])",
      "}",
    ])
  assert planted.lines(shared_tables.breaches([file])) == [5]
    as "the load is on line 5, where the folder is passed to it"
}

pub fn each_way_to_name_the_load_and_the_folder_is_found_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    test_module([
      "import client_tables as real",
      "import genesis_prime/table",
      "import genesis_prime/table/loader/server_table.{load_under}",
      "import genesis_prime/table/loader/store as table_store",
      "fn through_the_registry() { table.load(from: real.folder()) }",
      "fn through_an_unqualified_load() { load_under(from: real.folder()) }",
      "fn through_an_alias() { table_store.load_for_server(from: real.folder()) }",
    ])
  assert planted.lines(shared_tables.breaches([file])) == [6, 7, 8]
    as "a module's last segment, its alias and an unqualified import each name the load"
}

pub fn the_unqualified_folder_is_found_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    test_module([
      "import client_tables.{folder}",
      "import genesis_prime/table/loader/store",
      "fn load() { store.load(from: folder()) }",
    ])
  assert planted.lines(shared_tables.breaches([file])) == [4]
}

pub fn the_module_that_makes_the_shared_load_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file(path: shared_tables.loader_path, lines: [
      "//// The planted shared load.",
      "import client_tables",
      "import genesis_prime/table",
      "fn every_table() { table.load(from: client_tables.folder()) }",
    ])
  assert shared_tables.breaches([file]) == []
    as "the one module allowed to load the client's real tables"
}

pub fn a_function_that_reads_the_folder_without_loading_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    test_module([
      "import client_tables",
      "import genesis_prime/table/loader/store",
      "fn run_the_tool() { table_rows.run(folder: client_tables.folder()) }",
      "fn load_planted(folder) { store.load(from: folder) }",
    ])
  assert shared_tables.breaches([file]) == []
    as "the folder goes to a tool that reads bytes, and a planted folder goes to the load: no real table enters persistent terms"
}

pub fn a_load_in_a_function_that_never_names_the_folder_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    test_module([
      "import client_tables",
      "import genesis_prime/table/loader/store",
      "fn folder_of_the_run() { client_tables.folder() }",
      "fn planted_load(folder) { store.load(from: folder) }",
    ])
  assert shared_tables.breaches([file]) == []
    as "each function is read alone: naming the folder in one and loading in another is not a real load of its own"
}

pub fn no_test_loads_the_clients_tables_outside_the_shared_load_test() -> Nil {
  use <- owned_test.run(20_000)
  use <- unitest.tag("code_rule")
  let breaches = shared_tables.breaches(repository.sources(under: ["test"]))
  assert list.map(breaches, fn(breach) { #(breach.path, breach.line) }) == []
    as "every test reads client_tables.shared() or client_tables.every_table()"
}
