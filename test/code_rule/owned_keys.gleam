//// A test module that loads tables or writes content terms makes its keys with
//// `owned_key`, so `owned_test.run` fails a test whose body ends with terms
//// still stored under them. A term left in the VM's literal area is room taken
//// from every later test, and the area is a fixed 1 GiB region that a run fills
//// (`literal_alloc: Cannot allocate`), so a key made with `reference.new()` or
//// the store's `new_key()` in a module that loads is a breach.
////
//// - The modules read are the ones that reach a table load (`shared_tables`'
////   lists, and the store's `put_content`); a module that never loads may make
////   any reference.
//// - Four modules are not read. `test/client_tables.gleam` and
////   `test/character_tables.gleam` make the loads every test shares for the run
////   (`database_support.once`), which are never erased. `test/owned_key.gleam`
////   makes the keys, and `test/owned_key_test.gleam` tests a key made without it.
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
  "test/client_tables.gleam", "test/character_tables.gleam",
  "test/owned_key.gleam", "test/owned_key_test.gleam",
]

const store_module = "genesis_prime/table/loader/store"

/// Each reference to `reference.new` or the store's `new_key`, in a module that
/// loads tables or writes content terms, at the line of the reference.
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
    case list.append(loads, content) {
      [] -> []
      [_, ..] ->
        list.append(
          syntax.references_to(module, from: ["gleam/erlang/reference"], named: [
            "new",
          ]),
          syntax.references_to(module, from: [store_module], named: ["new_key"]),
        )
        |> list.map(fn(reference) {
          Breach(
            path: file.path,
            line: syntax.line_of(file.text, syntax.location_of(reference).start),
            rule: "a test module that loads tables makes its keys with `owned_key.new()` or `owned_key.new_key()`, so a body that ends with terms under them fails",
          )
        })
    }
  })
  |> list.sort(fn(first, second) {
    string.compare(first.path, second.path)
    |> order.break_tie(int.compare(first.line, second.line))
  })
}
