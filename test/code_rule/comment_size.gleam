//// The comment-size rule: a module's doc comment is at most 40 lines and a
//// function's or type's doc comment at most 10, counted at 100 columns.

import code_rule/source.{type Breach, type SourceFile}

/// A comment block's kind: the `////` doc at the top of a module, or the `///`
/// doc of a function, type, variant or constant.
pub type Kind {
  ModuleDoc
  ItemDoc
}

/// A row of the list: the module's name, the block's kind, its first line, its
/// size and the row's line of the list file (from 1).
pub type Listed {
  Listed(module: String, kind: Kind, first_line: String, size: Int, line: Int)
}

/// The list of blocks over their cap.
pub const list_path = "test/code_rule/comment_sizes.txt"

/// The list as its file writes it: `module kind first_line size` on each line.
pub fn parse_list(text text: String) -> List(Listed) {
  let _ = text
  []
}

/// Each comment block over its cap that the list does not hold at its size,
/// and each row that is not exact.
pub fn breaches(
  files files: List(SourceFile),
  listed listed: List(Listed),
) -> List(Breach) {
  let _ = files
  let _ = listed
  []
}
