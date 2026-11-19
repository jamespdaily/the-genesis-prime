//// Every gap a module states reaches the coverage measure. A module in `src` that
//// declares `pub fn gaps() -> List(gap.Entry)` is listed in the registry
//// (`dev/genesis_prime/coverage/gaps.gleam`): the registry imports it and calls
//// `<alias>.gaps()`. An import alone is a breach, since the entries would never be
//// printed.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/list
import gleam/option.{None, Some}

const rule_name = "a module with gaps the registry does not call"

/// The name of the function a module lists its gaps in.
const function_name = "gaps"

/// Each file that declares `pub fn gaps()` with no parameters and that the registry does
/// not call as `<alias>.gaps()`, at the line of the declaration. A module the registry
/// imports as `as _` is named no way, so it is not called.
pub fn breaches(
  files files: List(SourceFile),
  registry registry: SourceFile,
) -> List(Breach) {
  let registry_module = syntax.parse(registry)
  let called = called_modules(registry_module)
  list.flat_map(files, fn(file) {
    case declaration(file) {
      None -> []
      Some(offset) ->
        case list.contains(called, syntax.module_name(file.path)) {
          True -> []
          False -> [
            Breach(
              path: file.path,
              line: syntax.line_of(file.text, offset),
              rule: rule_name,
            ),
          ]
        }
    }
  })
}

/// The start of the file's `pub fn gaps()`, when it declares one.
fn declaration(file: SourceFile) -> option.Option(Int) {
  let module = syntax.parse(file)
  let found =
    list.find(module.functions, fn(definition) {
      let function = definition.definition
      function.name == function_name
      && function.publicity == glance.Public
      && function.parameters == []
    })
  case found {
    Ok(definition) -> Some(definition.definition.location.start)
    Error(Nil) -> None
  }
}

/// The modules the registry calls `gaps()` of, by their full names: an import whose name
/// in the registry (its alias, or the last segment of its path) is the qualifier of a
/// call of `gaps` with no arguments.
fn called_modules(registry: glance.Module) -> List(String) {
  let qualifiers = called_qualifiers(registry)
  list.filter_map(registry.imports, fn(definition) {
    case syntax.import_name(definition.definition) {
      Some(name) ->
        case list.contains(qualifiers, name) {
          True -> Ok(definition.definition.module)
          False -> Error(Nil)
        }
      None -> Error(Nil)
    }
  })
}

/// The qualifier of every call `qualifier.gaps()` in the registry's functions.
fn called_qualifiers(registry: glance.Module) -> List(String) {
  list.filter_map(syntax.expressions(registry), fn(expression) {
    case expression {
      glance.Call(
        function: glance.FieldAccess(
          container: glance.Variable(name: qualifier, ..),
          label:,
          ..,
        ),
        arguments: [],
        ..,
      )
        if label == function_name
      -> Ok(qualifier)
      glance.Call(..)
      | glance.Int(..)
      | glance.Float(..)
      | glance.String(..)
      | glance.Variable(..)
      | glance.NegateInt(..)
      | glance.NegateBool(..)
      | glance.Block(..)
      | glance.Panic(..)
      | glance.Todo(..)
      | glance.Tuple(..)
      | glance.List(..)
      | glance.Fn(..)
      | glance.RecordUpdate(..)
      | glance.FieldAccess(..)
      | glance.TupleIndex(..)
      | glance.FnCapture(..)
      | glance.BitString(..)
      | glance.Case(..)
      | glance.BinaryOperator(..)
      | glance.Echo(..) -> Error(Nil)
    }
  })
}
