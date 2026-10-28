//// The repository's Gleam source, read for the code-rule tests.

import gleam/list
import gleam/string
import simplifile

/// One source file: its path from the repository root, and its text.
pub type SourceFile {
  SourceFile(path: String, text: String)
}

/// A place where a file breaks a code rule.
pub type Breach {
  Breach(path: String, line: Int, rule: String)
}

/// The text of a file, which a test cannot go on without.
pub fn read(path: String) -> String {
  let assert Ok(text) = simplifile.read(path) as { "could not read " <> path }
  text
}

/// Every `.gleam` file under a directory, sorted by path.
pub fn files(under directory: String) -> List(SourceFile) {
  let assert Ok(paths) = simplifile.get_files(directory)
    as { "the directory could not be listed: " <> directory }
  paths
  |> list.filter(string.ends_with(_, ".gleam"))
  |> list.sort(string.compare)
  |> list.map(fn(path) { SourceFile(path:, text: read(path)) })
}
