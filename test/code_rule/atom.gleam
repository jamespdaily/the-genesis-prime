//// No atom is made from a string, and no term is read from bytes, outside
//// the modules allowed it under `[tools.code_rules]`, so client input can
//// neither fill the atom table nor build terms.

import code_rule/project_file
import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/int
import gleam/list
import gleam/option.{None, Some}

const unsafe_externals = ["binary_to_atom", "list_to_atom", "binary_to_term"]

/// Reads the modules allowed atoms or terms from the text of a Gleam project file.
pub fn allowed(project_file: String) -> List(String) {
  project_file.modules(project_file, "atom_or_term")
}

/// Each call in the file that makes an atom from a string or a term from bytes.
pub fn breaches(
  file file: SourceFile,
  allowed allowed: List(String),
) -> List(Breach) {
  case list.contains(allowed, syntax.module_name(file.path)) {
    True -> []
    False -> {
      let module = syntax.parse(file)
      list.append(create_calls(file, module), unsafe_externals_in(file, module))
      |> list.sort(fn(first, second) { int.compare(first.line, second.line) })
    }
  }
}

/// Each use of `atom.create`, however the atom module is imported.
fn create_calls(file: SourceFile, module: glance.Module) -> List(Breach) {
  let imports =
    list.filter(module.imports, fn(definition) {
      definition.definition.module == "gleam/erlang/atom"
    })
    |> list.map(fn(definition) { definition.definition })
  let qualifiers =
    list.filter_map(imports, fn(import_) {
      case import_.alias {
        None -> Ok("atom")
        Some(glance.Named(name)) -> Ok(name)
        Some(glance.Discarded(_)) -> Error(Nil)
      }
    })
  let unqualified =
    imports
    |> list.flat_map(fn(import_) { import_.unqualified_values })
    |> list.filter(fn(value) { value.name == "create" })
    |> list.map(fn(value) { option.unwrap(value.alias, "create") })
  syntax.references(module)
  |> list.filter_map(fn(reference) {
    case reference {
      syntax.Qualified(location:, qualifier:, name: "create") ->
        case list.contains(qualifiers, qualifier) {
          True -> Ok(breach(file, location.start))
          False -> Error(Nil)
        }
      syntax.Unqualified(location:, name:) ->
        case list.contains(unqualified, name) {
          True -> Ok(breach(file, location.start))
          False -> Error(Nil)
        }
      syntax.Qualified(..) -> Error(Nil)
    }
  })
}

/// Each function that is an external to an Erlang function that makes an atom
/// from a string or reads a term from bytes.
fn unsafe_externals_in(
  file: SourceFile,
  module: glance.Module,
) -> List(Breach) {
  list.flat_map(module.functions, fn(definition) {
    syntax.erlang_externals(definition.attributes)
    |> list.filter(fn(external) {
      external.0 == "erlang" && list.contains(unsafe_externals, external.1)
    })
    |> list.map(fn(_external) {
      breach(file, definition.definition.location.start)
    })
  })
}

fn breach(file: SourceFile, byte_offset: Int) -> Breach {
  Breach(
    path: file.path,
    line: syntax.line_of(file.text, byte_offset),
    rule: "atom or term from outside the server's own values",
  )
}
