//// A rule module is pure: it imports no process, OTP, database or logging
//// module, and its externals call only Erlang functions on the allow-list.
//// Modules with effects are listed under `[tools.code_rules]` in gleam.toml.

import code_rule/project_file
import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import gleam/int
import gleam/list
import gleam/string

/// The modules allowed effects and the Erlang functions a rule may call,
/// read from the Gleam project file.
pub type Allowed {
  Allowed(effectful_modules: List(String), pure_erlang: List(String))
}

/// Modules a rule may not import, each also covering the modules under it:
/// processes, OTP, databases and logging.
const effectful_imports = [
  "gleam/erlang/process",
  "gleam/erlang/port",
  "gleam/erlang/node",
  "gleam/erlang/application",
  "gleam/otp",
  "pog",
  "squirrel",
  "logging",
]

/// Reads the allow-lists from the text of a Gleam project file. An entry of
/// `pure_erlang` is written `module:function`.
pub fn allowed(project_file: String) -> Allowed {
  Allowed(
    effectful_modules: project_file.modules(project_file, "effectful_modules"),
    pure_erlang: project_file.strings(project_file, "pure_erlang"),
  )
}

/// Each import or external in the file that breaks the rule.
pub fn breaches(
  file file: SourceFile,
  allowed allowed: Allowed,
) -> List(Breach) {
  case list.contains(allowed.effectful_modules, syntax.module_name(file.path)) {
    True -> []
    False -> {
      let module = syntax.parse(file)
      let imports =
        list.filter_map(module.imports, fn(definition) {
          case is_effectful(definition.definition.module) {
            True ->
              Ok(breach(
                file:,
                byte_offset: definition.definition.location.start,
                what: "imports " <> definition.definition.module,
              ))
            False -> Error(Nil)
          }
        })
      let externals =
        list.flat_map(module.functions, fn(definition) {
          syntax.erlang_externals(definition.attributes)
          |> list.map(fn(external) { external.0 <> ":" <> external.1 })
          |> list.filter(fn(call) { !list.contains(allowed.pure_erlang, call) })
          |> list.map(fn(call) {
            breach(
              file:,
              byte_offset: definition.definition.location.start,
              what: "calls " <> call <> ", which is not on the pure allow-list",
            )
          })
        })
      list.append(imports, externals)
      |> list.sort(fn(first, second) { int.compare(first.line, second.line) })
    }
  }
}

fn is_effectful(module: String) -> Bool {
  list.any(effectful_imports, fn(banned) {
    module == banned || string.starts_with(module, banned <> "/")
  })
}

fn breach(
  file file: SourceFile,
  byte_offset byte_offset: Int,
  what what: String,
) -> Breach {
  Breach(
    path: file.path,
    line: syntax.line_of(file.text, byte_offset),
    rule: "a rule that " <> what,
  )
}
