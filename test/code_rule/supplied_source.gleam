//// Only the strong random source reaches the released server: no module under
//// `src/` builds a `Supplied` source except `login/random_source.gleam`, which
//// defines it. The compiler already refuses `src/` importing a module of
//// `dev/`, so the one way left to put draws of the caller's choosing into the
//// server is to build the constructor in `src/`.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

/// The module that defines `Supplied`, and the only one under `src/` that may
/// build it.
const defining_module = "genesis_prime/login/random_source"

/// The constructor the rule watches.
const constructor = "Supplied"

/// Each place in a file under `src/`, other than `login/random_source.gleam`,
/// that builds a `Supplied` source: a call or a use of the constructor, written
/// bare or with the module's name, and an import of it under another name.
/// Matching it in a pattern builds nothing, and a file under `dev/` or `test/`
/// may build it.
pub fn breaches(file file: SourceFile) -> List(Breach) {
  case
    string.starts_with(file.path, "src/")
    && syntax.module_name(file.path) != defining_module
  {
    False -> []
    True -> {
      let module = syntax.parse(file)
      let imports =
        list.filter(module.imports, fn(definition) {
          definition.definition.module == defining_module
        })
      let qualifiers = list.filter_map(imports, qualifier)
      let bare_names = list.flat_map(imports, bare_names)
      let uses =
        list.append(
          syntax.references(module),
          syntax.constant_references(module),
        )
        |> list.filter_map(use_breach(
          file:,
          qualifiers:,
          bare_names:,
          reference: _,
        ))
      list.append(
        list.filter_map(imports, renamed_breach(file:, definition: _)),
        uses,
      )
      |> list.sort(fn(first, second) { int.compare(first.line, second.line) })
    }
  }
}

/// The breach of an import that brings the constructor in under another name,
/// at the import.
fn renamed_breach(
  file file: SourceFile,
  definition definition: glance.Definition(glance.Import),
) -> Result(Breach, Nil) {
  let import_ = definition.definition
  let renamed =
    list.any(import_.unqualified_values, fn(value) {
      value.name == constructor && value.alias != None
    })
  case renamed {
    True ->
      Ok(breach(
        file:,
        offset: import_.location.start,
        what: "imports " <> constructor <> " under another name",
      ))
    False -> Error(Nil)
  }
}

/// The breach of a reference that names the constructor: qualified by a name
/// the defining module is imported as, or bare under a name it was imported by.
fn use_breach(
  file file: SourceFile,
  qualifiers qualifiers: List(String),
  bare_names bare_names: List(String),
  reference reference: syntax.Reference,
) -> Result(Breach, Nil) {
  let named = case reference {
    syntax.Qualified(location:, qualifier:, name:) ->
      case name == constructor && list.contains(qualifiers, qualifier) {
        True -> Ok(location)
        False -> Error(Nil)
      }
    syntax.Unqualified(location:, name:) ->
      case list.contains(bare_names, name) {
        True -> Ok(location)
        False -> Error(Nil)
      }
  }
  result.map(named, fn(location) {
    breach(
      file:,
      offset: location.start,
      what: "builds "
        <> constructor
        <> ", the random source of a caller's choosing",
    )
  })
}

/// The name an import of the defining module is used by in a qualified
/// reference: its alias, or its last segment.
fn qualifier(
  definition: glance.Definition(glance.Import),
) -> Result(String, Nil) {
  let import_ = definition.definition
  case import_.alias {
    Some(glance.Named(name)) -> Ok(name)
    Some(glance.Discarded(_)) -> Error(Nil)
    None -> list.last(string.split(import_.module, "/"))
  }
}

/// The names the constructor has in a file by an unqualified import of it.
fn bare_names(definition: glance.Definition(glance.Import)) -> List(String) {
  list.filter_map(definition.definition.unqualified_values, fn(value) {
    case value.name == constructor {
      True -> Ok(option.unwrap(value.alias, value.name))
      False -> Error(Nil)
    }
  })
}

fn breach(
  file file: SourceFile,
  offset offset: Int,
  what what: String,
) -> Breach {
  Breach(path: file.path, line: syntax.line_of(file.text, offset), rule: what)
}
