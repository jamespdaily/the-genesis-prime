//// The seeded generator stays out of the server that is released: no module
//// under `src/` imports it, so a server built from `src/` draws its random
//// bytes from the operating system, and a seed can reach a server only through
//// the dev start.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import gleam/int
import gleam/list
import gleam/string

/// The seeded generators: the dev module that holds ours and the package of
/// them in the dependency tree. Each also covers the modules under it.
const seeded_modules = ["genesis_prime/seeded_random", "prng"]

/// Each import in a file under `src/` of a seeded generator, whatever the
/// import is aliased to. A file under `dev/` or `test/` may import them.
pub fn breaches(file file: SourceFile) -> List(Breach) {
  case string.starts_with(file.path, "src/") {
    False -> []
    True ->
      syntax.parse(file).imports
      |> list.filter_map(fn(definition) {
        let import_ = definition.definition
        case is_seeded(import_.module) {
          True ->
            Ok(Breach(
              path: file.path,
              line: syntax.line_of(file.text, import_.location.start),
              rule: "imports the seeded generator " <> import_.module,
            ))
          False -> Error(Nil)
        }
      })
      |> list.sort(fn(first, second) { int.compare(first.line, second.line) })
  }
}

fn is_seeded(module: String) -> Bool {
  list.any(seeded_modules, fn(seeded) {
    module == seeded || string.starts_with(module, seeded <> "/")
  })
}
