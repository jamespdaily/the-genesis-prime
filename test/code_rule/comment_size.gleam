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
//// - A module's doc is all the file's `////` lines, and an item's doc runs on over
////   blank lines, as Gleam joins them.
//// - Exempt by reason, never counted: the lines order coverage reads as a failure
////   table (`order_coverage.failure_table_lines`: the header and the two-cell rows
////   under it), because a row cut from the comment is a failure point lost; and
////   the closed fence of `genesis_prime/server`'s doc that opens with
////   `server supervisor`, because it is the one picture of the tree, so every child
////   cut from it is a process the reader cannot find.

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

/// Every comment block of the file with its size: the module doc, which is all the
/// file's `////` lines, then each item doc, which is a run of `///` lines that blank
/// lines do not end, as Gleam joins them.
pub fn blocks(file file: SourceFile) -> List(Block) {
  let module = syntax.module_name(file.path)
  let lines =
    string.split(file.text, "\n")
    |> list.index_map(fn(text, index) { #(text, index + 1) })
  let module_lines =
    list.filter(lines, fn(entry) { kind_of(entry.0) == Ok(ModuleDoc) })
  let exempt = case module == diagram_module {
    True -> diagram_lines(module_lines)
    False -> []
  }
  let exempt = list.append(exempt, order_coverage.failure_table_lines(file:))
  let module_block = case module_lines {
    [] -> []
    run -> [block_of(run:, file:, module:, kind: ModuleDoc, exempt:)]
  }
  list.append(module_block, item_blocks(lines:, file:, module:))
}

fn item_blocks(
  lines lines: List(#(String, Int)),
  file file: SourceFile,
  module module: String,
) -> List(Block) {
  case lines {
    [] -> []
    [#(text, _), ..rest] ->
      case kind_of(text) {
        Ok(ItemDoc) -> {
          let #(run, after) = item_run(lines)
          [
            block_of(run:, file:, module:, kind: ItemDoc, exempt: []),
            ..item_blocks(lines: after, file:, module:)
          ]
        }
        Ok(ModuleDoc) | Error(Nil) -> item_blocks(lines: rest, file:, module:)
      }
  }
}

/// The `///` lines from the head of the lines, continued past blank lines when
/// another `///` line follows them, and the lines after.
fn item_run(
  lines: List(#(String, Int)),
) -> #(List(#(String, Int)), List(#(String, Int))) {
  let #(run, after) =
    list.split_while(lines, fn(entry) { kind_of(entry.0) == Ok(ItemDoc) })
  let past_blanks =
    list.drop_while(after, fn(entry) { string.trim(entry.0) == "" })
  case past_blanks {
    [#(text, _), ..] ->
      case kind_of(text) {
        Ok(ItemDoc) -> {
          let #(more, rest) = item_run(past_blanks)
          #(list.append(run, more), rest)
        }
        Ok(ModuleDoc) | Error(Nil) -> #(run, after)
      }
    [] -> #(run, after)
  }
}

fn block_of(
  run run: List(#(String, Int)),
  file file: SourceFile,
  module module: String,
  kind kind: Kind,
  exempt exempt: List(Int),
) -> Block {
  let assert [#(text, line), ..] = run as "a block has a first line"
  let size =
    list.fold(run, 0, fn(size, entry) {
      case list.contains(exempt, entry.1) {
        True -> size
        False -> size + lines_at_width(entry.0)
      }
    })
  Block(
    path: file.path,
    module:,
    kind:,
    first_line: doc_text(text),
    line:,
    size:,
  )
}

/// A doc line's text past its indentation and marker, trimmed.
fn doc_text(text: String) -> String {
  let start = string.trim_start(text)
  let marker = case string.starts_with(start, "////") {
    True -> "////"
    False -> "///"
  }
  start |> string.remove_prefix(marker) |> string.trim
}

/// The lines (from 1) of the fenced blocks of a module doc that are the supervision
/// diagram: a closed fence whose first line is the root, `server supervisor`. A
/// fence never closed, or holding anything else, is not exempt.
fn diagram_lines(lines: List(#(String, Int))) -> List(Int) {
  case lines {
    [] -> []
    [#(text, number), ..rest] ->
      case is_fence(text) {
        False -> diagram_lines(rest)
        True -> fence_lines(open: number, rest:)
      }
  }
}

/// The lines of the fence opened at `open` if it is closed and holds the
/// supervision tree, and the diagram lines after it.
fn fence_lines(open open: Int, rest rest: List(#(String, Int))) -> List(Int) {
  let #(inside, after) =
    list.split_while(rest, fn(entry) { !is_fence(entry.0) })
  case after, is_supervision_tree(inside) {
    [#(_, close), ..tail], True ->
      list.flatten([
        [open],
        list.map(inside, fn(entry) { entry.1 }),
        [close],
        diagram_lines(tail),
      ])
    [_, ..tail], False -> diagram_lines(tail)
    [], _ -> []
  }
}

fn is_fence(text: String) -> Bool {
  string.starts_with(doc_text(text), "```")
}

/// Whether the lines of a fence open with the root of the supervision tree.
fn is_supervision_tree(inside: List(#(String, Int))) -> Bool {
  case inside {
    [#(first, _), ..] ->
      string.starts_with(doc_text(first), "server supervisor")
    [] -> False
  }
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
