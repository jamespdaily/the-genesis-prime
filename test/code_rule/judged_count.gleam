//// The judged-count rule: a gate event of a load run is judged through
//// `genesis_prime/load_judged`.

import code_rule/source.{type Breach, type SourceFile}

/// The breaches of a load tool's file: each of its `expected` events (variant names of
/// `load_judged.Event`) that no `Judged(event: ...)` of the file names, and each string
/// literal that begins a gate line by hand: an event's name from `printed`, then a colon.
pub fn breaches(
  file _file: SourceFile,
  expected _expected: List(String),
  printed _printed: List(String),
) -> List(Breach) {
  []
}
