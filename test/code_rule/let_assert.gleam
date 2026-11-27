//// The let-assert rule: every `let assert` in `src/` and `dev/` carries a
//// message that states why it cannot fail, and no module holds more of them
//// than its row of the ceiling list.

import code_rule/source.{type Breach, type SourceFile}

/// A module on the list: its name as `syntax.module_name` writes it, the
/// number of `let assert` it holds, and its line of the list file (from 1).
pub type Listed {
  Listed(module: String, ceiling: Int, line: Int)
}

/// The list of ceilings.
pub const list_path = "test/code_rule/let_assert_ceilings.txt"

/// The most rows the list may hold.
pub const most_rows = 129

/// The list as its file writes it: `module ceiling` on each line.
pub fn parse_list(text _text: String) -> List(Listed) {
  panic as "the let-assert rule is not written"
}

/// The breaches of the rule over the files and the list.
pub fn breaches(
  files _files: List(SourceFile),
  listed _listed: List(Listed),
  most_rows _most_rows: Int,
) -> List(Breach) {
  panic as "the let-assert rule is not written"
}
