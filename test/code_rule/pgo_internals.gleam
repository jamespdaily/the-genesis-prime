//// No test reads pgo's internals. `pgo` is the Erlang library `pog` runs the
//// database pool on; its processes and their states change with its version,
//// so a test that asks them (as the waiting for a pool to open once did) breaks
//// with the library and proves nothing of the server. A test waits for the
//// database as the server does, by the readiness ask
//// (`genesis_prime/readiness`).
////
//// A Gleam file breaches by importing a module whose name starts with `pgo`, or
//// by an `@external(erlang, ...)` whose module does; an Erlang helper breaches
//// by qualifying a call or a type by such a module.

import code_rule/erlang_calls
import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import gleam/int
import gleam/list
import gleam/string

const rule_name = "a test that reads pgo's internals"

/// The prefix of the modules of the pool library.
const prefix = "pgo"

/// Each import of a pgo module and each external to one in a Gleam file.
pub fn breaches(file file: SourceFile) -> List(Breach) {
  let module = syntax.parse(file)
  let imports =
    list.filter(module.imports, fn(definition) {
      is_pgo(definition.definition.module)
    })
    |> list.map(fn(definition) { definition.definition.location.start })
  let externals =
    list.filter(module.functions, fn(definition) {
      syntax.erlang_externals(definition.attributes)
      |> list.any(fn(external) { is_pgo(external.0) })
    })
    |> list.map(fn(definition) { definition.definition.location.start })
  list.append(imports, externals)
  |> list.map(fn(offset) {
    Breach(
      path: file.path,
      line: syntax.line_of(file.text, offset),
      rule: rule_name,
    )
  })
  |> list.sort(fn(first, second) { int.compare(first.line, second.line) })
}

/// Each line of an Erlang helper that qualifies a name by a pgo module.
pub fn erlang_breaches(file file: SourceFile) -> List(Breach) {
  erlang_calls.qualifier_lines(file.text, prefix)
  |> list.map(fn(line) { Breach(path: file.path, line:, rule: rule_name) })
}

/// Whether a module's name is `pgo` or starts with `pgo_`; `pog`, the Gleam
/// package, is not.
fn is_pgo(module: String) -> Bool {
  module == prefix || string.starts_with(module, prefix <> "_")
}
