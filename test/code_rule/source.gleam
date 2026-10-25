//// The repository's Gleam source, read for the code-rule tests.

/// One source file: its path from the repository root, and its text.
pub type SourceFile {
  SourceFile(path: String, text: String)
}

/// A place where a file breaks a code rule.
pub type Breach {
  Breach(path: String, line: Int, rule: String)
}

/// Every `.gleam` file under a directory, sorted by path.
pub fn files(under directory: String) -> List(SourceFile) {
  todo as "body in the build commit"
}
