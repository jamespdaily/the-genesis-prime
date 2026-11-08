//// A test makes its keys with `owned_key`, so `owned_test.run` fails a test
//// whose body ends with terms still stored under them. A term left in the VM's
//// literal area is room taken from every later test, and the area is a fixed
//// 1 GiB region that a run fills (`literal_alloc: Cannot allocate`).
////
//// - **Every `store.new_key()` is a breach**, whatever the module does with the
////   key: it may write content terms through `store.put_content`, through the
////   content load (`content.load(key:)`) or through `content_spawn.put_world`.
//// - **`reference.new()` is a breach in a module that loads tables or writes
////   content with the store**, where the reference is a load's key: a test's
////   tables are a value on its own heap (`store.read`, `store.edit`), and a stored
////   load is made only by the shared modules. A module that makes a reference
////   for anything else may.
//// - Six modules are not read. `test/client_tables.gleam`, `test/fixture_tables.gleam`
////   and `test/character_tables.gleam` make the values every test shares for the
////   run (`database_support.once`), which are stored once and never erased.
////   `test/owned_key.gleam` makes the keys, and `test/owned_key_test.gleam` tests
////   a key made without it. `test/table_load_test.gleam` tests the load itself:
////   its failing loads run under a reference of their own and store nothing.
//// - Modules are read one at a time, so a key a helper in another module makes
////   and returns is not followed.

import code_rule/shared_tables
import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import gleam/int
import gleam/list
import gleam/order
import gleam/string

const exempt_paths = [
  "test/client_tables.gleam", "test/fixture_tables.gleam",
  "test/character_tables.gleam", "test/owned_key.gleam",
  "test/owned_key_test.gleam", "test/table_load_test.gleam",
]

const store_module = "genesis_prime/table/loader/store"

/// Each reference to the store's `new_key`, and each to `reference.new` in a
/// module that loads tables or writes content terms with the store, at the line
/// of the reference.
pub fn breaches(files: List(SourceFile)) -> List(Breach) {
  files
  |> list.filter(fn(file) { !list.contains(exempt_paths, file.path) })
  |> list.flat_map(fn(file) {
    let module = syntax.parse(file)
    let loads =
      syntax.references_to(
        module,
        from: shared_tables.loading_modules,
        named: shared_tables.loading_functions,
      )
    let content =
      syntax.references_to(module, from: [store_module], named: ["put_content"])
    let references = case list.append(loads, content) {
      [] -> []
      [_, ..] ->
        syntax.references_to(module, from: ["gleam/erlang/reference"], named: [
          "new",
        ])
    }
    list.append(
      references,
      syntax.references_to(module, from: [store_module], named: ["new_key"]),
    )
    |> list.map(fn(reference) {
      Breach(
        path: file.path,
        line: syntax.line_of(file.text, syntax.location_of(reference).start),
        rule: "a test makes its content keys with `owned_key.new_key()` or `owned_key.new_fixture_key()`, so a body that ends with terms under them fails, and stores no load of its own: `store.read` and `store.edit` build its tables on its heap",
      )
    })
  })
  |> list.sort(fn(first, second) {
    string.compare(first.path, second.path)
    |> order.break_tie(int.compare(first.line, second.line))
  })
}
