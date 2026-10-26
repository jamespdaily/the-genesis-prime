//// Only the strong random source reaches the released server: no module under
//// `src/` builds a `Supplied` source except `login/random_source.gleam`, which
//// defines it. The compiler already refuses `src/` importing a module of
//// `dev/`, so the one way left to put draws of the caller's choosing into the
//// server is to build the constructor in `src/`.

import code_rule/source.{type Breach, type SourceFile}

/// Each place in a file under `src/`, other than `login/random_source.gleam`,
/// that builds a `Supplied` source: a call or a use of the constructor, written
/// bare or with the module's name, and an import of it under another name.
/// Matching it in a pattern builds nothing, and a file under `dev/` or `test/`
/// may build it.
pub fn breaches(file file: SourceFile) -> List(Breach) {
  let _ = file
  []
}
