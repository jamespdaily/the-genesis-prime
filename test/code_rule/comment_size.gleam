//// The comment-size rule: a module's doc comment (`////`) is at most 40 lines
//// and a function's, type's, variant's or constant's doc comment (`///`) at most
//// 10, each line counted as many lines as its columns need at a width of 100, so
//// a cap cannot be met by long lines. A hand-written module of `src` is read; a
//// generated one is not (`level.is_generated`).
////
//// ```
//// each file's comment blocks ──► size (lines at 100 columns, exempt lines left out)
////   over its cap, no row              ─► breach at the block
////   over its cap, larger than its row ─► breach at the block
////   its row, within the cap           ─► breach at the row: leave the list
////   its row, larger than the block    ─► breach at the row: lower it
////   its row, no such block            ─► breach at the row: leave the list
//// the list ──► a row out of order or repeated ─► breach at the row
//// ```
////
//// - The list (`list_path`) holds one `module kind first_line size` row per
////   block over its cap, sorted by those words, where `kind` is `module` or
////   `item` and `first_line` is the block's first line after its marker. A
////   block is its row's when module, kind and first line are the same.
//// - The list can only shrink: a block that grows is a breach, and a block that
////   shrinks or goes lowers or removes its row, so a row is never slack.
//// - Exempt by reason, never counted: the rows of a failure table, because the
////   order-coverage rule reads them (`order_coverage.failure_breaches`) and a
////   row cut from the comment is a failure point lost; and the supervision
////   diagram of `genesis_prime/server`, because it is the one picture of the
////   tree, so every child cut from it is a process the reader cannot find.

import code_rule/level
import code_rule/list_file
import code_rule/order_coverage
import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import gleam/int
import gleam/list
import gleam/string

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

/// One comment block of a file: where it is, which it is, and its size.
pub type Block {
  Block(
    path: String,
    module: String,
    kind: Kind,
    first_line: String,
    line: Int,
    size: Int,
  )
}

/// The list of blocks over their cap.
pub const list_path = "test/code_rule/comment_sizes.txt"

/// The width, in columns, that a line counts as one line at.
pub const width = 100

/// The most lines a module's doc comment holds.
pub const module_cap = 40

/// The most lines a function's or type's doc comment holds.
pub const item_cap = 10

/// The module whose doc comment holds the supervision diagram.
const diagram_module = "genesis_prime/server"

/// The cap of a kind of block.
pub fn cap(kind: Kind) -> Int {
  case kind {
    ModuleDoc -> module_cap
    ItemDoc -> item_cap
  }
}

fn kind_word(kind: Kind) -> String {
  case kind {
    ModuleDoc -> "module"
    ItemDoc -> "item"
  }
}

/// The list as its file writes it: `module kind first_line size` on each line,
/// the first line being the words between the kind and the size.
pub fn parse_list(text text: String) -> List(Listed) {
  list_file.rows(text:)
  |> list.map(fn(entry) {
    let #(row, line) = entry
    let bad = list_file.bad_row(line:, what: "is not module, kind and size")
    let assert Ok(#(module, rest)) = string.split_once(row, " ") as bad
    let assert Ok(#(word, rest)) = string.split_once(rest, " ") as bad
    let assert Ok(kind) = case word {
      "module" -> Ok(ModuleDoc)
      "item" -> Ok(ItemDoc)
      _ -> Error(Nil)
    }
      as list_file.bad_row(line:, what: "names no kind")
    let assert [last, ..before] = list.reverse(string.split(rest, " ")) as bad
    let assert Ok(size) = int.parse(last)
      as list_file.bad_row(line:, what: "has no size")
    let first_line = string.join(list.reverse(before), " ")
    Listed(module:, kind:, first_line:, size:, line:)
  })
}

/// Which kind of comment a line starts, past its indentation.
fn kind_of(text: String) -> Result(Kind, Nil) {
  let start = string.trim_start(text)
  case string.starts_with(start, "////"), string.starts_with(start, "///") {
    True, _ -> Ok(ModuleDoc)
    False, True -> Ok(ItemDoc)
    False, False -> Error(Nil)
  }
}

/// Every comment block of the file, in order, with its size.
pub fn blocks(file file: SourceFile) -> List(Block) {
  let module = syntax.module_name(file.path)
  let lines =
    string.split(file.text, "\n")
    |> list.index_map(fn(text, index) { #(text, index + 1) })
  blocks_from(lines:, file:, module:)
}

fn blocks_from(
  lines lines: List(#(String, Int)),
  file file: SourceFile,
  module module: String,
) -> List(Block) {
  case lines {
    [] -> []
    [#(text, line), ..rest] ->
      case kind_of(text) {
        Error(Nil) -> blocks_from(lines: rest, file:, module:)
        Ok(kind) -> {
          let run =
            list.take_while(lines, fn(entry) { kind_of(entry.0) == Ok(kind) })
          let after = list.drop(lines, list.length(run))
          let marker = case kind {
            ModuleDoc -> "////"
            ItemDoc -> "///"
          }
          let first_line =
            text
            |> string.trim_start
            |> string.remove_prefix(marker)
            |> string.trim
          let size =
            counted(run: list.map(run, fn(entry) { entry.0 }), module:, kind:)
          [
            Block(path: file.path, module:, kind:, first_line:, line:, size:),
            ..blocks_from(lines: after, file:, module:)
          ]
        }
      }
  }
}

/// The lines a block's text counts as at `width` columns, leaving out the
/// lines exempt by reason: the rows of a failure table, and the fenced diagram
/// of the server module's doc.
fn counted(
  run run: List(String),
  module module: String,
  kind kind: Kind,
) -> Int {
  let #(_, size) =
    list.fold(run, #(Exempt(table: False, fence: False), 0), fn(state, text) {
      let #(inside, size) = state
      let #(inside, exempt) = case kind {
        ModuleDoc -> exempt_line(inside:, text:, module:)
        ItemDoc -> #(inside, False)
      }
      case exempt {
        True -> #(inside, size)
        False -> #(inside, size + lines_at_width(text))
      }
    })
  size
}

/// Whether the walk through a module doc is inside a failure table or inside
/// the fenced diagram.
type Exempt {
  Exempt(table: Bool, fence: Bool)
}

fn exempt_line(
  inside inside: Exempt,
  text text: String,
  module module: String,
) -> #(Exempt, Bool) {
  let start = string.trim_start(text)
  let table = case string.starts_with(start, "//// |") {
    False -> False
    True ->
      inside.table
      || order_coverage.row_cells(start) == ["Point", "What happens"]
  }
  let fenced = module == diagram_module
  let fence_line =
    fenced
    && string.starts_with(string.trim_start(string.drop_start(start, 4)), "```")
  let fence = case fence_line {
    True -> !inside.fence
    False -> inside.fence
  }
  #(Exempt(table:, fence:), table || { fenced && { fence || fence_line } })
}

fn lines_at_width(text: String) -> Int {
  int.max(1, { string.length(text) + width - 1 } / width)
}

/// Each comment block over its cap that the list does not hold at its size,
/// each row whose block is within the cap, smaller than the row or gone, and
/// each row out of order or repeated.
pub fn breaches(
  files files: List(SourceFile),
  listed listed: List(Listed),
) -> List(Breach) {
  let found =
    files
    |> list.filter(fn(file) { !level.is_generated(file) })
    |> list.flat_map(fn(file) { blocks(file:) })
  let of_row = fn(row: Listed) {
    list.find(found, fn(block) {
      block.module == row.module
      && block.kind == row.kind
      && block.first_line == row.first_line
    })
  }
  let at_blocks =
    list.filter_map(found, fn(block) {
      let row =
        list.find(listed, fn(row) {
          row.module == block.module
          && row.kind == block.kind
          && row.first_line == block.first_line
        })
      case block.size > cap(block.kind), row {
        False, _ -> Error(Nil)
        True, Error(Nil) ->
          Ok(block_breach(block, " is over its cap and not on the list"))
        True, Ok(row) if block.size > row.size ->
          Ok(block_breach(
            block,
            " grew past its row of " <> int.to_string(row.size),
          ))
        True, Ok(_) -> Error(Nil)
      }
    })
  let at_rows =
    list.filter_map(listed, fn(row) {
      case of_row(row) {
        Error(Nil) ->
          Ok(row_breach(row, " is the row of a block that is gone: delete it"))
        Ok(block) ->
          case block.size <= cap(row.kind), block.size < row.size {
            True, _ ->
              Ok(row_breach(
                row,
                " is within its cap of "
                  <> int.to_string(cap(row.kind))
                  <> ": delete the row",
              ))
            False, True ->
              Ok(row_breach(
                row,
                " is down to "
                  <> int.to_string(block.size)
                  <> ": write it, so the row is no slack",
              ))
            False, False -> Error(Nil)
          }
      }
    })
  let disordered =
    list_file.disordered(
      rows: listed,
      compare: fn(before, row) { string.compare(row_key(before), row_key(row)) },
      path: list_path,
      line: fn(row) { row.line },
      name: row_key,
      what: "is out of order or repeated in the list",
    )
  list.flatten([at_blocks, at_rows, disordered])
}

fn row_key(row: Listed) -> String {
  row.module <> " " <> kind_word(row.kind) <> " " <> row.first_line
}

fn block_breach(block: Block, what: String) -> Breach {
  Breach(
    path: block.path,
    line: block.line,
    rule: kind_word(block.kind)
      <> " comment `"
      <> block.first_line
      <> "` of "
      <> int.to_string(block.size)
      <> " lines at "
      <> int.to_string(width)
      <> " columns (at most "
      <> int.to_string(cap(block.kind))
      <> ")"
      <> what
      <> " ("
      <> list_path
      <> ")",
  )
}

fn row_breach(row: Listed, what: String) -> Breach {
  list_file.breach(path: list_path, line: row.line, name: row_key(row), what:)
}
