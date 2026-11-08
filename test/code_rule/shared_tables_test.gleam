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
      "import genesis_prime/table/loader/server_table.{read}",
      "import genesis_prime/table/loader/store as table_store",
      "fn through_the_registry() { table.load(from: real.folder()) }",
      "fn through_an_unqualified_load() { read(from: real.folder()) }",
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

pub fn a_function_that_loads_a_table_from_the_fixtures_folder_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    test_module([
      "import fixture_tables",
      "import genesis_prime/table/loader/store",
      "fn load(entry) {",
      "  store.load(under: key, from: fixture_tables.folder, entries: [entry])",
      "}",
    ])
  assert planted.lines(shared_tables.breaches([file])) == [5]
    as "the fixture's folder is loaded only by test/fixture_tables.gleam"
}

pub fn the_module_that_loads_the_fixture_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file(path: shared_tables.fixture_loader_path, lines: [
      "//// The planted fixture load.",
      "import fixture_tables",
      "import genesis_prime/table",
      "fn shared() { table.load(from: fixture_tables.folder) }",
    ])
  assert shared_tables.breaches([file]) == []
    as "the one module allowed to load the committed fixture"
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

pub fn functions_that_do_not_call_each_other_share_nothing_test() -> Nil {
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
    as "the folder is named in one function and a load is made in another that never receives it"
}

pub fn a_function_that_gets_the_folder_from_a_helper_and_loads_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    test_module([
      "import client_tables",
      "import genesis_prime/table/loader/store",
      "fn real() { client_tables.folder() }",
      "fn load_real(entry) {",
      "  store.load(from: real(), entries: [entry])",
      "}",
    ])
  assert planted.lines(shared_tables.breaches([file])) == [6]
    as "the folder reaches the load through a helper of the module, on line 6"
}

pub fn a_helper_that_loads_from_its_parameter_given_the_clients_folder_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    test_module([
      "import client_tables",
      "import genesis_prime/table/loader/store",
      "fn load_from(folder) {",
      "  store.load(from: folder)",
      "}",
      "fn real_tables() {",
      "  load_from(client_tables.folder())",
      "}",
    ])
  assert planted.lines(shared_tables.breaches([file])) == [8]
    as "the call that gives the helper the client's folder is on line 8"
}

pub fn a_helper_that_loads_from_its_parameter_given_a_planted_folder_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    test_module([
      "import genesis_prime/table/loader/store",
      "fn load_from(folder) { store.load(from: folder) }",
      "fn planted(folder) { load_from(folder) }",
    ])
  assert shared_tables.breaches([file]) == []
}

pub fn only_the_lowest_function_that_names_the_folder_and_loads_is_reported_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    test_module([
      "import client_tables",
      "import genesis_prime/table/loader/store",
      "fn load_real() { store.load(from: client_tables.folder()) }",
      "fn a_test() { load_real() }",
    ])
  assert planted.lines(shared_tables.breaches([file])) == [4]
    as "the test that calls the breaching helper is not a second breach"
}

pub fn the_servers_own_table_load_from_the_table_folder_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    test_module([
      "import genesis_prime",
      "fn tables() { genesis_prime.load_tables() }",
    ])
  assert planted.lines(shared_tables.breaches([file])) == [3]
    as "genesis_prime.load_tables loads the server's tables from GENESIS_TABLE_DIR, the folder of the client's real tables"
}

pub fn the_content_only_tables_loaded_from_the_clients_folder_are_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    test_module([
      "import client_tables",
      "import genesis_prime/table/loader/server_table",
      "fn more(tables) {",
      "  server_table.load_content_tables(over: tables, from: client_tables.folder())",
      "}",
    ])
  assert planted.lines(shared_tables.breaches([file])) == [5]
    as "load_content_tables reads the content-only tables from the folder it is given, the client's real one"
}

pub fn the_servers_content_load_from_the_table_folder_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    test_module([
      "import genesis_prime",
      "fn content(tables) { genesis_prime.load_content(tables:) }",
    ])
  assert planted.lines(shared_tables.breaches([file])) == [3]
    as "genesis_prime.load_content loads the content-only tables from GENESIS_TABLE_DIR, the folder of the client's real tables"
}

pub fn no_test_loads_the_clients_tables_outside_the_shared_load_test() -> Nil {
  use <- owned_test.run(20_000)
  use <- unitest.tag("code_rule")
  let breaches = shared_tables.breaches(repository.sources(under: ["test"]))
  assert list.map(breaches, fn(breach) { #(breach.path, breach.line) }) == []
    as "every test reads client_tables.shared() or client_tables.every_table()"
}
