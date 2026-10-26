//// The seeded generator stays out of the server that is released: no module
//// under `src/` imports it, so a server built from `src/` draws its random
//// bytes from the operating system, and a seed can reach a server only through
//// the dev start.

import code_rule/source.{type Breach, type SourceFile}

/// Each import in a file under `src/` of the seeded generator, or of the
/// seeded generator package `prng`, whatever the import is aliased to. A file
/// under `dev/` or `test/` may import them.
pub fn breaches(file _file: SourceFile) -> List(Breach) {
  panic as "shape only: not built"
}
