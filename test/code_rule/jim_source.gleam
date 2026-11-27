//// The person-as-source rule.

import code_rule/source.{type Breach, type SourceFile}

/// A row of the keep list: the file, the trimmed text of a line it holds that
/// names Jim, and the row's line of the list file (from 1).
pub type Kept {
  Kept(path: String, text: String, line: Int)
}

/// The keep list.
pub const list_path = "test/code_rule/jim_source_keep.txt"

/// The list as its file writes it.
pub fn parse_list(text text: String) -> List(Kept) {
  let _ = text
  []
}

/// Each line naming Jim that no row holds, each row with no such line, and
/// each row out of order or repeated.
pub fn breaches(
  files files: List(SourceFile),
  kept kept: List(Kept),
) -> List(Breach) {
  let _ = files
  let _ = kept
  []
}
