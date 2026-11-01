//// No test reads pgo's internals. `pgo` is the Erlang library `pog` runs the
//// database pool on; its processes and their states change with its version,
//// so a test that asks them (as the waiting for a pool to open once did) breaks
//// with the library and proves nothing of the server. A test waits for the
//// database as the server does, by the readiness ask
//// (`genesis_prime/readiness`).
////
//// A test reaches pgo's processes by naming them, in a call (`pgo_pool:...`),
//// a process name (`pgo_pool_sup`) or a module in an external, so any atom of
//// an Erlang helper, and any import, external module or string of a Gleam
//// file, that is `pgo` or starts with `pgo_` is a breach.

import code_rule/erlang_calls
import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import gleam/int
import gleam/list
import gleam/string

const rule_name = "a test that reads pgo's internals"

/// The name of the pool library and the start of its modules' and processes'.
const name = "pgo"

/// Each import of a pgo module, each external to one and each string that
/// names one in a Gleam file.
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
  let strings =
    list.filter(syntax.strings(module), fn(literal) { is_pgo(literal.1) })
    |> list.map(fn(literal) { literal.0 })
  list.flatten([imports, externals, strings])
  |> list.map(fn(offset) {
    Breach(
      path: file.path,
      line: syntax.line_of(file.text, offset),
      rule: rule_name,
    )
  })
  |> list.sort(fn(first, second) { int.compare(first.line, second.line) })
}

/// Each line of an Erlang helper that writes an atom that names a pgo module
/// or process.
pub fn erlang_breaches(file file: SourceFile) -> List(Breach) {
  erlang_calls.atom_lines(file.text, name)
  |> list.map(fn(line) { Breach(path: file.path, line:, rule: rule_name) })
}

/// Whether a name is `pgo` or starts with `pgo_`; `pog`, the Gleam package, and
/// a name that merely starts with the letters are not.
fn is_pgo(candidate: String) -> Bool {
  candidate == name || string.starts_with(candidate, name <> "_")
}
