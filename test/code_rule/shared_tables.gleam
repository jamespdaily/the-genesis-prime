//// The client's real tables are loaded into persistent terms once per test
//// run, by `test/client_tables.gleam`, and every test reads that load. A
//// loaded table sits in the VM's literal area, a fixed 1 GB region, and the
//// 384 tables take 609 MB of it, so a test that loads a real table again, even
//// one table, puts its rows there beside them, and erased terms are freed only
//// after a purge: a run then crashes with `literal_alloc: Cannot allocate`.
////
//// A function of a test module is a breach when it gets the client's table
//// folder (`client_tables.folder()`, or `genesis_prime.load_tables()`, which
//// reads the same folder) and reaches a table load (`load` of
//// `genesis_prime/table` or of the loader's store, `load_under`, `load_for_server`
//// or `load_more`, `load_content_tables`, or `genesis_prime.load_tables()` or
//// `genesis_prime.load_content()`, which loads the content-only tables from the
//// same folder). Both may be one call
//// away: a function of the same module that returns the folder, or that loads
//// from its parameter, counts as the folder or the load. Only the lowest such
//// function is reported, not the functions that call it. Modules are read one
//// at a time, so a helper in another test module that loads from the folder
//// it is given is not followed. `test/client_tables.gleam` itself is the one
//// place allowed to load.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/dict
import gleam/int
import gleam/list
import gleam/set.{type Set}

/// The path of the one module that loads the client's real tables.
pub const loader_path = "test/client_tables.gleam"

const folder_module = "client_tables"

const folder_function = "folder"

pub const loading_modules = [
  "genesis_prime/table",
  "genesis_prime/table/loader/store",
  "genesis_prime/table/loader/server_table",
]

pub const loading_functions = [
  "load", "load_under", "load_for_server", "load_more", "load_content_tables",
]

const real_load_module = "genesis_prime"

const real_load_functions = ["load_tables", "load_content"]

/// Each function in the files, outside `test/client_tables.gleam`, that gets
/// the client's table folder and calls a table load, reported at the first
/// load or call to a function that loads, in order of line.
pub fn breaches(files: List(SourceFile)) -> List(Breach) {
  files
  |> list.filter(fn(file) { file.path != loader_path })
  |> list.flat_map(fn(file) {
    list.sort(file_breaches(file), fn(first, second) {
      int.compare(first.line, second.line)
    })
  })
}

/// What one function of a module does, as far as its own text shows.
type Function {
  Function(
    name: String,
    gets_folder: Bool,
    loads: List(glance.Span),
    callees: List(#(String, glance.Span)),
  )
}

fn file_breaches(file: SourceFile) -> List(Breach) {
  let module = syntax.parse(file)
  let functions = list.map(module.functions, describe(module, _))
  let names = set.from_list(list.map(functions, fn(function) { function.name }))
  let calls =
    dict.from_list(
      list.map(functions, fn(function) {
        #(function.name, list.map(function.callees, fn(call) { call.0 }))
      }),
    )
  let folders =
    reaching(
      calls:,
      from: list.filter_map(functions, fn(function) {
        case function.gets_folder {
          True -> Ok(function.name)
          False -> Error(Nil)
        }
      }),
    )
  let loaders =
    reaching(
      calls:,
      from: list.filter_map(functions, fn(function) {
        case function.loads {
          [_, ..] -> Ok(function.name)
          [] -> Error(Nil)
        }
      }),
    )
  let both = set.intersection(folders, loaders)
  list.filter_map(functions, fn(function) {
    let calls_one_below =
      list.any(function.callees, fn(call) {
        set.contains(both, call.0) && call.0 != function.name
      })
    case set.contains(both, function.name) && !calls_one_below {
      False -> Error(Nil)
      True ->
        case first_load(function:, loading: loaders, names:) {
          Ok(span) ->
            Ok(Breach(
              path: file.path,
              line: syntax.line_of(file.text, span.start),
              rule: "a function gets the client's table folder and loads tables from it; read the tables from `client_tables.shared()` or `client_tables.every_table()`",
            ))
          Error(Nil) -> Error(Nil)
        }
    }
  })
}

/// The first place the function loads: a load of its own, or a call to a
/// function of the module that loads.
fn first_load(
  function function: Function,
  loading loading: Set(String),
  names names: Set(String),
) -> Result(glance.Span, Nil) {
  let calls =
    list.filter_map(function.callees, fn(call) {
      case set.contains(loading, call.0) && set.contains(names, call.0) {
        True -> Ok(call.1)
        False -> Error(Nil)
      }
    })
  list.append(function.loads, calls)
  |> list.sort(fn(first, second) { int.compare(first.start, second.start) })
  |> list.first
}

fn describe(
  module: glance.Module,
  definition: glance.Definition(glance.Function),
) -> Function {
  let function = definition.definition
  let alone = glance.Module(..module, functions: [definition])
  let real_loads =
    syntax.references_to(
      alone,
      from: [real_load_module],
      named: real_load_functions,
    )
  let folder =
    syntax.references_to(alone, from: [folder_module], named: [folder_function])
  let loads =
    syntax.references_to(alone, from: loading_modules, named: loading_functions)
  let callees =
    list.filter_map(syntax.references(alone), fn(reference) {
      case reference {
        syntax.Unqualified(location:, name:) -> Ok(#(name, location))
        syntax.Qualified(..) -> Error(Nil)
      }
    })
  Function(
    name: function.name,
    gets_folder: folder != [] || real_loads != [],
    loads: list.map(list.append(loads, real_loads), syntax.location_of),
    callees:,
  )
}

/// The names in `from` and every function that calls one of them, directly or
/// through other functions of the module.
fn reaching(
  calls calls: dict.Dict(String, List(String)),
  from names: List(String),
) -> Set(String) {
  grow(calls, set.from_list(names))
}

fn grow(
  calls: dict.Dict(String, List(String)),
  reached: Set(String),
) -> Set(String) {
  let larger =
    dict.fold(calls, reached, fn(acc, name, callees) {
      case list.any(callees, set.contains(reached, _)) {
        True -> set.insert(acc, name)
        False -> acc
      }
    })
  case set.size(larger) == set.size(reached) {
    True -> reached
    False -> grow(calls, larger)
  }
}
