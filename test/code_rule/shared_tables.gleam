//// The client's real tables are loaded into persistent terms once per test
//// run, by `test/client_tables.gleam`, and every test reads that load. A
//// loaded table sits in the VM's literal area, a fixed 1 GB region, and the
//// 384 tables take 609 MB of it, so a test that loads a real table again, even
//// one table, puts its rows there beside them, and erased terms are freed only
//// after a purge: a run then crashes with `literal_alloc: Cannot allocate`.
////
//// A function of a test module that passes `client_tables.folder()` to a
//// table load (`load` of `genesis_prime/table`, of the loader's store, or
//// `load_under` or `load_for_server`) is a breach, wherever the load is
//// imported from and however the modules are aliased. `test/client_tables.gleam`
//// itself is the one place allowed to.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string

/// The path of the one module that loads the client's real tables.
pub const loader_path = "test/client_tables.gleam"

const folder_module = "client_tables"

const folder_function = "folder"

const loading_modules = [
  "genesis_prime/table",
  "genesis_prime/table/loader/store",
  "genesis_prime/table/loader/server_table",
]

const loading_functions = ["load", "load_under", "load_for_server"]

/// Each function in the files, outside `test/client_tables.gleam`, that names
/// the client's table folder and calls a table load, reported at the load.
pub fn breaches(files: List(SourceFile)) -> List(Breach) {
  files
  |> list.filter(fn(file) { file.path != loader_path })
  |> list.flat_map(fn(file) {
    list.sort(file_breaches(file), fn(first, second) {
      int.compare(first.line, second.line)
    })
  })
}

fn file_breaches(file: SourceFile) -> List(Breach) {
  let module = syntax.parse(file)
  let folder = names_in(module, [folder_module], [folder_function])
  let loads = names_in(module, loading_modules, loading_functions)
  list.flat_map(module.functions, fn(definition) {
    let references =
      syntax.references(glance.Module(..module, functions: [definition]))
    case list.any(references, is_one_of(_, folder)) {
      False -> []
      True ->
        references
        |> list.filter(is_one_of(_, loads))
        |> list.map(fn(load) {
          Breach(
            path: file.path,
            line: syntax.line_of(file.text, location_of(load).start),
            rule: "a function passes the client's table folder to a table load; read the tables from `client_tables.shared()` or `client_tables.every_table()`",
          )
        })
    }
  })
}

/// The ways the module can write a function of the given modules: through a
/// module name (its last segment, or its alias) and through an unqualified
/// import.
type Names {
  Names(
    qualifiers: List(String),
    unqualified: List(String),
    functions: List(String),
  )
}

fn names_in(
  module: glance.Module,
  modules: List(String),
  functions: List(String),
) -> Names {
  let imports =
    list.filter_map(module.imports, fn(definition) {
      let import_ = definition.definition
      case list.contains(modules, import_.module) {
        True -> Ok(import_)
        False -> Error(Nil)
      }
    })
  let qualifiers =
    list.filter_map(imports, fn(import_) {
      case import_.alias {
        None -> Ok(last_segment(import_.module))
        Some(glance.Named(alias)) -> Ok(alias)
        Some(glance.Discarded(_)) -> Error(Nil)
      }
    })
  let unqualified =
    imports
    |> list.flat_map(fn(import_) { import_.unqualified_values })
    |> list.filter(fn(value) { list.contains(functions, value.name) })
    |> list.map(fn(value) { option.unwrap(value.alias, value.name) })
  Names(qualifiers:, unqualified:, functions:)
}

fn last_segment(module: String) -> String {
  case list.last(string.split(module, "/")) {
    Ok(segment) -> segment
    Error(Nil) -> module
  }
}

fn is_one_of(reference: syntax.Reference, names: Names) -> Bool {
  case reference {
    syntax.Qualified(qualifier:, name:, ..) ->
      list.contains(names.qualifiers, qualifier)
      && list.contains(names.functions, name)
    syntax.Unqualified(name:, ..) -> list.contains(names.unqualified, name)
  }
}

fn location_of(reference: syntax.Reference) -> glance.Span {
  case reference {
    syntax.Qualified(location:, ..) -> location
    syntax.Unqualified(location:, ..) -> location
  }
}
