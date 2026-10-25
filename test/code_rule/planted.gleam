//// Planted source for the code-rule tests: files made up in the test, never
//// read from disk.

import code_rule/source.{type Breach, type SourceFile, SourceFile}
import gleam/list
import gleam/string

/// A planted file at a made-up path, its lines joined by newlines, so a test
/// states each line number by counting its list.
pub fn file(path path: String, lines lines: List(String)) -> SourceFile {
  SourceFile(path:, text: string.join(lines, "\n") <> "\n")
}

/// The lines of the breaches, in the order reported.
pub fn lines(breaches: List(Breach)) -> List(Int) {
  list.map(breaches, fn(breach) { breach.line })
}
