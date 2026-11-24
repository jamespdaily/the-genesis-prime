//// Every test that reads a gap registry is tagged `gaps`, so `./check fast` runs it.
//// A test reads one when it calls `<module>.gaps()` or `gaps.registry()`, itself or
//// through a function of its own file (followed to any depth). A helper in another
//// file is not followed, nor is the registry module imported under another name than
//// `gaps`, a `gaps` function imported unqualified, or one passed as a value without a
//// call; none occurs in `test/`.

import code_rule/gap_registry
import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/int
import gleam/list
import gleam/set.{type Set}
import gleam/string

/// The tag `./check fast` runs.
const tag = "gaps"

/// Each public test function of the file that reads a gap registry and carries no
/// `gaps` tag, at the line of its definition.
pub fn breaches(file: SourceFile) -> List(Breach) {
  let module = syntax.parse(file)
  let readers = reader_names(module)
  module.functions
  |> list.sort(fn(first, second) {
    int.compare(
      first.definition.location.start,
      second.definition.location.start,
    )
  })
  |> list.filter(fn(definition) {
    let function = definition.definition
    is_test(function)
    && reads_gaps(module:, definition:, readers:)
    && !list.contains(list.flat_map(function.body, syntax.tags_of), tag)
  })
  |> list.map(fn(definition) {
    Breach(
      path: file.path,
      line: syntax.line_of(file.text, definition.definition.location.start),
      rule: "a test that reads a gap registry and is not tagged `gaps`",
    )
  })
}

fn is_test(function: glance.Function) -> Bool {
  function.publicity == glance.Public
  && string.ends_with(function.name, "_test")
}

/// The names of the functions of the module that are not tests and read a gap
/// registry, directly or through another such function.
fn reader_names(module: glance.Module) -> Set(String) {
  let helpers =
    list.filter(module.functions, fn(definition) {
      !is_test(definition.definition)
    })
  grow(module:, helpers:, found: set.new())
}

fn grow(
  module module: glance.Module,
  helpers helpers: List(glance.Definition(glance.Function)),
  found found: Set(String),
) -> Set(String) {
  let next =
    helpers
    |> list.filter(fn(definition) {
      reads_gaps(module:, definition:, readers: found)
    })
    |> list.map(fn(definition) { definition.definition.name })
    |> set.from_list
  case set.size(next) == set.size(found) {
    True -> found
    False -> grow(module:, helpers:, found: next)
  }
}

/// Whether the function calls a gap registry or a function in `readers`. A registry is
/// read by a call of a module's `gaps()` (see `gap_registry.called_qualifiers`) or of
/// `gaps.registry()`, both with no arguments.
fn reads_gaps(
  module module: glance.Module,
  definition definition: glance.Definition(glance.Function),
  readers readers: Set(String),
) -> Bool {
  let function_module = glance.Module(..module, functions: [definition])
  gap_registry.called_qualifiers(function_module) != []
  || list.any(syntax.calls(function_module), fn(call) {
    case call {
      syntax.Call(
        called: syntax.CalledThroughVariable(
          variable: "gaps",
          label: "registry",
        ),
        arguments: [],
        ..,
      ) -> True
      syntax.Call(called: syntax.CalledByName(name:), ..) ->
        set.contains(readers, name)
      syntax.Call(..) -> False
    }
  })
}
