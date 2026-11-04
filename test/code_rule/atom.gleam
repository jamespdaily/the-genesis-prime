//// No atom is made from a string, and no term is read from bytes, outside
//// the modules allowed it under `[tools.code_rules]`, so client input can
//// neither fill the atom table nor build terms. Gleam modules are read for
//// `atom.create` and externals; Erlang helpers for the calls themselves.

import code_rule/erlang_calls
import code_rule/project_file
import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/int
import gleam/list

const unsafe_externals = ["binary_to_atom", "list_to_atom", "binary_to_term"]

const rule_name = "atom or term from outside the server's own values"

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
  syntax.references_to(module:, from: ["gleam/erlang/atom"], named: ["create"])
  |> list.map(fn(reference) {
    breach(file, syntax.location_of(reference).start)
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
    rule: rule_name,
  )
}

/// Each line of an Erlang helper that calls or refers to a BIF that makes an
/// atom from a string or reads a term from bytes, unless its module is
/// allowed (code_rule/erlang_calls).
pub fn erlang_breaches(
  file file: SourceFile,
  allowed allowed: List(String),
) -> List(Breach) {
  case list.contains(allowed, syntax.module_name(file.path)) {
    True -> []
    False ->
      erlang_calls.lines(
        file.text,
        list.map(unsafe_externals, erlang_calls.Target("erlang", _)),
      )
      |> list.map(fn(line) { Breach(path: file.path, line:, rule: rule_name) })
  }
}
