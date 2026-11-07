//// Copies the client's rows the tests read into text files under
//// `test/fixture/client_tables/`, so a test of the server's logic runs on the
//// client's own rows in CI, where no client is installed.
////
//// `gleam run -m genesis_prime/fixture_rows` reads the client's tables
//// (`table_folder`) with the server's own reader (`table_rows`) and writes one
//// `<Table>.tsv` for each of the server's tables (`server_table.entries`), the
//// `roots.tsv` ids and every row they reach, and the `NOTICE`.
////
//// - **A root** is a line of `roots.tsv`: `table`, `id`, `name` and the test
////   that needs it (`used_by`). A test names an id through `fixture_tables.root`.
//// - **The closure** adds every row a selected row reaches, in a table the
////   server loads:
////   - an id column, by `table_generator/reference` (`spell4IdAttackPrimary00`
////     holds Spell4 ids), in the client's own spelling;
////   - the child rows of a parent (`child_rules`), which the server reads by
////     scanning the child table for the parent's id or group;
////   - the ids the server reads by the kind of the row (`untyped_references`),
////     each with the function that reads it.
//// - **A small table goes in whole**, so a scan or a derivation sees it as the
////   client holds it: every table whose text is under `whole_limit` bytes, and
////   the tables of `whole_tables`.
//// - **The text:** the header is the file's own column names in file order;
////   rows are sorted by id and a line is a row; an integer is decimal; a boolean
////   is `true` or `false`; a 32-bit float is its bits in hex (`0x3dcccccd`), so
////   it reads back exactly; a string is its text with `\`, tab, newline and
////   carriage return escaped (`\\`, `\t`, `\n`, `\r`).

import genesis_prime/dev_exit
import genesis_prime/table
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store
import genesis_prime/table/loader/tbl_file
import genesis_prime/table_folder
import genesis_prime/table_generator/naming
import genesis_prime/table_generator/reference
import genesis_prime/table_rows.{type Cell, type TableRows}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/order
import gleam/result
import gleam/set.{type Set}
import gleam/string
import simplifile

/// Where the fixture is committed.
pub const fixture_folder = "test/fixture/client_tables"

/// The tables smaller than this many bytes of text go in whole.
const whole_limit = 65_536

/// Tables that go in whole whatever their size.
///
/// - GameFormula: the load's requirement and the rating derivation read its rows
///   by number (`level.requirements`, `rating.build`).
/// - CreatureLevel: the loadout derivation checks a row for each level
///   (`loadout.health_rows`).
const whole_tables: List(String) = ["GameFormula", "CreatureLevel"]

/// A line of `roots.tsv`: a row a test names.
pub type Root {
  Root(table: String, id: Int, name: String, used_by: String)
}

/// The text of the fixture's files.
pub type Fixture {
  Fixture(
    /// Each table's file, by the table's name, for every table the server
    /// loads.
    tables: Dict(String, String),
    /// `stale.tsv`: the references of the rows chosen to an id the client's
    /// table has no row for.
    stale: String,
  )
}

/// The file of the references to ids the client has no row for, in the fixture's
/// folder.
pub const stale_file = "stale"

/// A reference of a row chosen to an id the client's table has no row for, so no
/// closure can reach it: a row of the client that names a row the client lacks.
pub type Stale {
  Stale(table: String, id: Int, target_table: String, target_id: Int)
}

/// Why the rows could not be made.
pub type Refusal {
  /// `roots.tsv` has a line that is not four tab-separated fields with an id.
  BadRootLine(line: String)
  /// A root names a table the server does not load.
  RootTableNotLoaded(table: String)
  /// A root names an id the client's table has no row for.
  RootRowMissing(table: String, id: Int)
  /// A client file could not be read.
  ClientFile(table: String, reason: String)
  /// A rule names a column a table does not have.
  RuleColumnMissing(table: String, column: String)
  /// A file could not be read or written.
  FileFailed(path: String, reason: String)
}

/// How to say why a refusal happened.
pub fn describe(refusal: Refusal) -> String {
  case refusal {
    BadRootLine(line:) ->
      "roots.tsv has a line that is not `table`, `id`, `name`, `used_by` separated by tabs: "
      <> line
    RootTableNotLoaded(table:) ->
      "the root's table " <> table <> " is not one the server loads"
    RootRowMissing(table:, id:) ->
      "the root "
      <> table
      <> " "
      <> int.to_string(id)
      <> " has no row in the client"
    ClientFile(table:, reason:) ->
      "the client's table " <> table <> " could not be read: " <> reason
    FileFailed(path:, reason:) ->
      "the file " <> path <> " could not be used: " <> reason
    RuleColumnMissing(table:, column:) ->
      "a closure rule names the column "
      <> column
      <> " of "
      <> table
      <> ", which has no such column"
  }
}

/// The roots of `roots.tsv`: the header line, then a line for each root.
pub fn parse_roots(text: String) -> Result(List(Root), Refusal) {
  case string.split(text, "\n") {
    [] -> Ok([])
    [_header, ..lines] ->
      lines
      |> list.filter(fn(line) { line != "" })
      |> list.try_map(fn(line) {
        case string.split(line, "\t") {
          [table, id, name, used_by] ->
            case int.parse(id) {
              Ok(id) -> Ok(Root(table:, id:, name:, used_by:))
              Error(Nil) -> Error(BadRootLine(line))
            }
          _ -> Error(BadRootLine(line))
        }
      })
  }
}

// ---------------------------------------------------------------- the text

/// What a cell's text says, by the type of its column.
type Field {
  /// An integer column's number.
  Number(Int)
  /// A float column's 32 bits.
  Bits(Int)
  /// A boolean column's value.
  Flag(Bool)
  /// A string column's text.
  Words(String)
}

/// The text of one cell.
fn cell_text(value: table_rows.Value) -> String {
  case value {
    table_rows.Integer32(number) | table_rows.Integer64(number) ->
      int.to_string(number)
    table_rows.Float32(bits:, ..) ->
      "0x" <> string.pad_start(string.lowercase(int.to_base16(bits)), 8, "0")
    table_rows.Boolean(True) -> "true"
    table_rows.Boolean(False) -> "false"
    table_rows.Text(text) ->
      text
      |> string.replace("\\", "\\\\")
      |> string.replace("\t", "\\t")
      |> string.replace("\n", "\\n")
      |> string.replace("\r", "\\r")
  }
}

/// Why the text of a cell is not a value of its column's type.
pub type CellRefusal {
  NotADecimalInteger
  NotEightHexCharacters
  NotHexWithItsPrefix
  NotTrueOrFalse
  BadEscape
  NotAFiniteFloat
}

/// What a cell refusal says.
fn describe_cell(refusal: CellRefusal) -> String {
  case refusal {
    NotADecimalInteger -> "not a decimal integer"
    NotEightHexCharacters -> "not 8 hex characters"
    NotHexWithItsPrefix -> "not `0x` and 8 hex characters"
    NotTrueOrFalse -> "not true or false"
    BadEscape -> "an escape that is not \\\\, \\t, \\n or \\r"
    NotAFiniteFloat -> "the bits are not a finite 32-bit float"
  }
}

/// What the text of a cell in a column of this type says, or why it is not a
/// value of the type.
fn parse_field(
  column_type column_type: tbl_file.ColumnType,
  text text: String,
) -> Result(Field, CellRefusal) {
  case column_type {
    tbl_file.Integer32 | tbl_file.Integer64 ->
      int.parse(text)
      |> result.map(Number)
      |> result.replace_error(NotADecimalInteger)
    tbl_file.Float32 ->
      case text {
        "0x" <> hex ->
          case string.length(hex) {
            8 ->
              int.base_parse(hex, 16)
              |> result.map(Bits)
              |> result.replace_error(NotEightHexCharacters)
            _ -> Error(NotEightHexCharacters)
          }
        _ -> Error(NotHexWithItsPrefix)
      }
    tbl_file.Boolean32 ->
      case text {
        "true" -> Ok(Flag(True))
        "false" -> Ok(Flag(False))
        _ -> Error(NotTrueOrFalse)
      }
    tbl_file.Utf16Text ->
      unescape(string.to_graphemes(text), "")
      |> result.map(Words)
  }
}

fn unescape(
  letters: List(String),
  done: String,
) -> Result(String, CellRefusal) {
  case letters {
    [] -> Ok(done)
    ["\\", "\\", ..rest] -> unescape(rest, done <> "\\")
    ["\\", "t", ..rest] -> unescape(rest, done <> "\t")
    ["\\", "n", ..rest] -> unescape(rest, done <> "\n")
    ["\\", "r", ..rest] -> unescape(rest, done <> "\r")
    ["\\", ..] -> Error(BadEscape)
    [letter, ..rest] -> unescape(rest, done <> letter)
  }
}

/// Why a table's file text is not rows of its table.
pub type TextRefusal {
  /// The header is not the table's columns, in order: the first column that
  /// differs (counting from 1), and what the file has there (nothing when it
  /// ends early).
  HeaderDiffers(table: String, position: Int, expected: String, found: String)
  /// A row has not as many cells as the table has columns.
  WrongCellCount(table: String, line: Int, expected: Int, found: Int)
  /// A cell is not a value of its column's type.
  BadCell(table: String, line: Int, column: String, reason: CellRefusal)
}

/// What a refusal of a file's text says, with the fix.
pub fn describe_text(refusal: TextRefusal) -> String {
  case refusal {
    HeaderDiffers(table:, position:, expected:, found:) ->
      "the header of "
      <> table
      <> " differs from the table's columns at column "
      <> int.to_string(position)
      <> ": the schema has `"
      <> expected
      <> "` and the file has `"
      <> found
      <> "`; run `gleam run -m genesis_prime/fixture_rows`"
    WrongCellCount(table:, line:, expected:, found:) ->
      "line "
      <> int.to_string(line)
      <> " of "
      <> table
      <> " has "
      <> int.to_string(found)
      <> " cells and the table has "
      <> int.to_string(expected)
      <> " columns"
    BadCell(table:, line:, column:, reason:) ->
      "line "
      <> int.to_string(line)
      <> " of "
      <> table
      <> ", column "
      <> column
      <> ": "
      <> describe_cell(reason)
  }
}

fn value_of(
  column_type: tbl_file.ColumnType,
  text: String,
) -> Result(table_rows.Value, CellRefusal) {
  use field <- result.try(parse_field(column_type:, text:))
  case column_type, field {
    tbl_file.Integer64, Number(number) -> Ok(table_rows.Integer64(number))
    _, Number(number) -> Ok(table_rows.Integer32(number))
    _, Flag(value) -> Ok(table_rows.Boolean(value))
    _, Words(words) -> Ok(table_rows.Text(words))
    _, Bits(bits) ->
      case <<bits:size(32)>> {
        <<value:float-size(32)>> -> Ok(table_rows.Float32(value:, bits:))
        _ -> Error(NotAFiniteFloat)
      }
  }
}

/// The rows of a table's file text, read against the schema's columns.
pub fn parse_table(
  schema schema: tbl_file.Schema,
  text text: String,
) -> Result(List(List(Cell)), TextRefusal) {
  case string.split(text, "\n") {
    [] -> Ok([])
    [header, ..lines] -> {
      use _ <- result.try(check_columns(
        table: schema.table,
        position: 1,
        expected: list.map(schema.columns, fn(column) { column.name }),
        found: string.split(header, "\t"),
      ))
      lines
      |> list.filter(fn(line) { line != "" })
      |> list.index_map(fn(line, index) { #(line, index + 2) })
      |> list.try_map(fn(numbered) {
        parse_line(schema:, line: numbered.0, number: numbered.1)
      })
    }
  }
}

/// The cells of a line of a table's file, which is line `number` of it.
fn parse_line(
  schema schema: tbl_file.Schema,
  line line: String,
  number number: Int,
) -> Result(List(Cell), TextRefusal) {
  let texts = string.split(line, "\t")
  let expected = list.length(schema.columns)
  use <- bool.guard(
    when: list.length(texts) != expected,
    return: Error(WrongCellCount(
      table: schema.table,
      line: number,
      expected:,
      found: list.length(texts),
    )),
  )
  list.zip(schema.columns, texts)
  |> list.try_map(fn(pair) {
    let #(column, text) = pair
    value_of(column.column_type, text)
    |> result.map(table_rows.Cell(column.name, _))
    |> result.map_error(fn(reason) {
      BadCell(table: schema.table, line: number, column: column.name, reason:)
    })
  })
}

fn check_columns(
  table table: String,
  position position: Int,
  expected expected: List(String),
  found found: List(String),
) -> Result(Nil, TextRefusal) {
  case expected, found {
    [], [] -> Ok(Nil)
    [name, ..more_expected], [same, ..more_found] if name == same ->
      check_columns(
        table:,
        position: position + 1,
        expected: more_expected,
        found: more_found,
      )
    [name, ..], [other, ..] ->
      Error(HeaderDiffers(table:, position:, expected: name, found: other))
    [name, ..], [] ->
      Error(HeaderDiffers(table:, position:, expected: name, found: ""))
    [], [other, ..] ->
      Error(HeaderDiffers(table:, position:, expected: "", found: other))
  }
}

// ------------------------------------------------------------ the closure

/// A column that holds the id of another table the server loads.
type Link {
  Link(position: Int, table: String)
}

/// Rows of `child` whose `column` holds the value of `parent_column` in a
/// selected row of `parent`, which the server finds by scanning the child
/// table. An `ID` column is the table's first.
type ChildRule {
  ChildRule(
    child: String,
    column: String,
    parent: String,
    parent_column: String,
    reader: String,
  )
}

/// The child rows the server reads, each with the function that reads it.
const child_rules = [
  ChildRule(
    "Spell4Effects",
    "spellId",
    "Spell4",
    "ID",
    "spell_plan.effects_of (Spell4Effects.spellId)",
  ),
  ChildRule(
    "SpellPhase",
    "spell4IdOwner",
    "Spell4",
    "ID",
    "spell_plan.phases_of (SpellPhase.spell4IdOwner)",
  ),
  ChildRule(
    "Spell4Telegraph",
    "spell4Id",
    "Spell4",
    "ID",
    "spell_area (Spell4Telegraph.spell4Id)",
  ),
  ChildRule(
    "Spell4Thresholds",
    "spell4IdParent",
    "Spell4",
    "ID",
    "spell_plan.thresholds_of (Spell4Thresholds.spell4IdParent)",
  ),
  ChildRule(
    "Creature2DisplayGroupEntry",
    "creature2DisplayGroupId",
    "Creature2",
    "creature2DisplayGroupId",
    "appearance (Creature2.creature2DisplayGroupId)",
  ),
  ChildRule(
    "Creature2OutfitGroupEntry",
    "creature2OutfitGroupId",
    "Creature2",
    "creature2OutfitGroupId",
    "appearance (Creature2.creature2OutfitGroupId)",
  ),
  ChildRule(
    "Creature2OverrideProperties",
    "creature2Id",
    "Creature2",
    "ID",
    "unit_properties (Creature2OverrideProperties.creature2Id)",
  ),
  // The server picks one row of the item's source by type and power level
  // (`worn_visual.of_item`); every row of the source comes in, so the pick is
  // the server's.
  ChildRule(
    "ItemDisplaySourceEntry",
    "itemSourceId",
    "Item2",
    "itemSourceId",
    "worn_visual.of_item (ItemDisplaySourceEntry.itemSourceId)",
  ),
]

/// The rows the server reads by the kind of a row, where no column's name says
/// which table the number is an id of: for a row of `table` whose `kinds`
/// columns all hold their value, the `column` holds an id of `target`.
type UntypedReference {
  UntypedReference(
    table: String,
    kinds: List(#(String, Int)),
    column: String,
    target: String,
    reader: String,
  )
}

const untyped_references = [
  UntypedReference(
    "Prerequisite",
    [#("prerequisiteTypeId0", 11)],
    "objectId0",
    "Prerequisite",
    "prerequisite.nested_loaded (a type 11 condition names a row; a missing row fails it)",
  ),
  UntypedReference(
    "Prerequisite",
    [#("prerequisiteTypeId1", 11)],
    "objectId1",
    "Prerequisite",
    "prerequisite.nested_loaded (a type 11 condition names a row; a missing row fails it)",
  ),
  UntypedReference(
    "Prerequisite",
    [#("prerequisiteTypeId2", 11)],
    "objectId2",
    "Prerequisite",
    "prerequisite.nested_loaded (a type 11 condition names a row; a missing row fails it)",
  ),
  UntypedReference(
    "Spell4Effects",
    [#("effectType", 26)],
    "dataBits00",
    "Spell4",
    "spell_plan.proxy_of (Proxy effect type 26)",
  ),
  UntypedReference(
    "Spell4Effects",
    [#("effectType", 26)],
    "dataBits06",
    "Prerequisite",
    "spell_plan (Proxy effect type 26 dataBits06 names a gate)",
  ),
  UntypedReference(
    "Spell4Effects",
    [#("effectType", 14)],
    "dataBits01",
    "Spell4",
    "spell_plan.procs_of (Proc effect type 14)",
  ),
  UntypedReference(
    "Spell4Effects",
    [#("effectType", 80), #("dataBits00", 2)],
    "dataBits01",
    "Spell4",
    "spell_plan.selector_of (SpellForceRemove effect type 80, selector 2: a spell)",
  ),
  UntypedReference(
    "Spell4Effects",
    [#("effectType", 80), #("dataBits00", 3)],
    "dataBits01",
    "Spell4Base",
    "spell_plan.selector_of (SpellForceRemove effect type 80, selector 3: a base)",
  ),
  UntypedReference(
    "Spell4Effects",
    [#("effectType", 112)],
    "dataBits01",
    "ItemDisplay",
    "spell_plan.disguise_of (DisguiseOutfit effect type 112)",
  ),
  UntypedReference(
    "Spell4Effects",
    [#("effectType", 112)],
    "dataBits02",
    "ItemDisplay",
    "spell_plan.disguise_of (DisguiseOutfit effect type 112)",
  ),
]

/// A column the server reads as an id of a table whose name the column's own
/// does not say.
type ColumnReference {
  ColumnReference(
    table: String,
    columns: List(String),
    target: String,
    reader: String,
  )
}

const column_references = [
  ColumnReference(
    "CharacterCreation",
    [
      "itemId0", "itemId01", "itemId02", "itemId03", "itemId04", "itemId05",
      "itemId06", "itemId07", "itemId08", "itemId09", "itemId010", "itemId011",
      "itemId012", "itemId013", "itemId014", "itemId015",
    ],
    "Item2",
    "loadout.items_of (CharacterCreation.itemId0 to itemId015)",
  ),
]

/// The rows of a table the server's load reads by what their columns hold, kept
/// instead of the whole table, which would bring in every row they reach.
type LoadRule {
  LoadRule(table: String, columns: List(#(String, Int)), reader: String)
}

const load_rules = [
  LoadRule(
    "SpellLevel",
    [#("characterLevel", 1), #("prerequisiteId", 0)],
    "loadout.is_level_one_ability: a class's abilities at level 1 with no prerequisite, read by loadout and spell_plan",
  ),
]

/// What the closure keeps of one table once its rows are let go, so only one
/// table's rows are in memory at a time.
type Digest {
  Digest(
    /// Every row's id.
    ids: Set(Int),
    /// The ids of the rows the load reads (`load_rules`).
    wanted: List(Int),
    /// Whether the table goes in whole.
    whole: Bool,
    /// The rows a row reaches by an id column or by its kind, by the row's id.
    reaches: Dict(Int, List(#(String, Int))),
    /// For each child rule whose parent is this table, the key of each row.
    keys: Dict(Int, List(#(Int, Int))),
    /// For each child rule whose child is this table, the ids of its rows by
    /// the value of the rule's column.
    children: Dict(Int, Dict(Int, List(Int))),
  )
}

/// Where each rule reads a table's cells, found once from the file's columns.
type Plan {
  Plan(
    links: List(Link),
    load: List(List(#(Int, Int))),
    untyped: List(#(UntypedReference, List(#(Int, Int)), Int)),
    parent_rules: List(#(Int, Int)),
    child_rules: List(#(Int, Int)),
  )
}

type Selection =
  Dict(String, Set(Int))

fn column_position(header: List(String), column: String) -> Result(Int, Nil) {
  case column {
    "ID" -> Ok(0)
    _ ->
      list.index_map(header, fn(name, index) { #(name, index) })
      |> list.key_find(column)
  }
}

/// The reading plan of one table, or the column a rule needs that the table
/// does not have.
fn plan_of(
  table table: String,
  schema schema: tbl_file.Schema,
  known known: Dict(String, reference.Table),
  loaded loaded: List(String),
) -> Result(Plan, Refusal) {
  let header = list.map(schema.columns, fn(column) { column.name })
  let position = fn(column) {
    column_position(header, column)
    |> result.replace_error(RuleColumnMissing(table:, column:))
  }
  let links =
    schema.columns
    |> list.index_map(fn(column, position) { #(column, position) })
    |> list.filter_map(fn(pair) {
      let #(column, position) = pair
      use <- bool.guard(when: position == 0, return: Error(Nil))
      use <- bool.guard(
        when: column.column_type != tbl_file.Integer32,
        return: Error(Nil),
      )
      use snake <- result.try(
        naming.field_name(column.name) |> result.replace_error(Nil),
      )
      use target <- result.try(reference.referenced_table(
        column: snake,
        tables: known,
      ))
      case list.contains(loaded, target.type_name) {
        True -> Ok(Link(position:, table: target.type_name))
        False -> Error(Nil)
      }
    })
  use named <- result.try(
    column_references
    |> list.filter(fn(rule) { rule.table == table })
    |> list.try_map(fn(rule) {
      list.try_map(rule.columns, fn(column) {
        position(column) |> result.map(Link(position: _, table: rule.target))
      })
    })
    |> result.map(list.flatten),
  )
  use untyped <- result.try(
    untyped_references
    |> list.filter(fn(rule) { rule.table == table })
    |> list.try_map(fn(rule) {
      use kinds <- result.try(
        list.try_map(rule.kinds, fn(kind) {
          position(kind.0) |> result.map(fn(cell) { #(cell, kind.1) })
        }),
      )
      use cell <- result.map(position(rule.column))
      #(rule, kinds, cell)
    }),
  )
  use parents <- result.try(
    list.index_map(child_rules, fn(rule, index) { #(index, rule) })
    |> list.filter(fn(pair) { { pair.1 }.parent == table })
    |> list.try_map(fn(pair) {
      use cell <- result.map(position({ pair.1 }.parent_column))
      #(pair.0, cell)
    }),
  )
  use children <- result.try(
    list.index_map(child_rules, fn(rule, index) { #(index, rule) })
    |> list.filter(fn(pair) { { pair.1 }.child == table })
    |> list.try_map(fn(pair) {
      use cell <- result.map(position({ pair.1 }.column))
      #(pair.0, cell)
    }),
  )
  use load <- result.map(
    load_rules
    |> list.filter(fn(rule) { rule.table == table })
    |> list.try_map(fn(rule) {
      list.try_map(rule.columns, fn(entry) {
        position(entry.0) |> result.map(fn(cell) { #(cell, entry.1) })
      })
    }),
  )
  Plan(
    links: list.append(links, named),
    load:,
    untyped:,
    parent_rules: parents,
    child_rules: children,
  )
}

fn id_of(row: List(Cell)) -> Int {
  case row {
    [table_rows.Cell(value: table_rows.Integer32(id), ..), ..] -> id
    _ -> panic as "a table's first column is a 32-bit id"
  }
}

fn number_at(row: List(Cell), position: Int) -> Int {
  case list.drop(row, position) {
    [table_rows.Cell(value: table_rows.Integer32(number), ..), ..]
    | [table_rows.Cell(value: table_rows.Integer64(number), ..), ..] -> number
    _ -> panic as "a rule's column holds an integer"
  }
}

/// The size of the table's text, counted only up to `whole_limit`.
fn text_size(rows: List(List(Cell))) -> Int {
  list.fold_until(rows, 0, fn(size, row) {
    let size = size + string.length(row_line(row)) + 1
    case size < whole_limit {
      True -> list.Continue(size)
      False -> list.Stop(size)
    }
  })
}

/// What the closure keeps of a table whose rows are read.
fn digest_of(
  table table: String,
  rows rows: List(List(Cell)),
  plan plan: Plan,
) -> Digest {
  let whole =
    plan.load == []
    && { list.contains(whole_tables, table) || text_size(rows) < whole_limit }
  let wanted =
    list.filter_map(rows, fn(row) {
      case
        list.any(plan.load, fn(rule) {
          list.all(rule, fn(entry) { number_at(row, entry.0) == entry.1 })
        })
      {
        True -> Ok(id_of(row))
        False -> Error(Nil)
      }
    })
  let #(reaches, keys, children) =
    list.fold(rows, #(dict.new(), dict.new(), dict.new()), fn(state, row) {
      let #(reaches, keys, children) = state
      let id = id_of(row)
      let typed =
        list.filter_map(plan.links, fn(link) {
          case number_at(row, link.position) {
            0 -> Error(Nil)
            value -> Ok(#(link.table, value))
          }
        })
      let untyped =
        list.filter_map(plan.untyped, fn(entry) {
          let #(rule, kinds, cell) = entry
          case list.all(kinds, fn(kind) { number_at(row, kind.0) == kind.1 }) {
            True -> Ok(#(rule.target, number_at(row, cell)))
            False -> Error(Nil)
          }
        })
      let reaches = case list.append(typed, untyped) {
        [] -> reaches
        reached -> dict.insert(reaches, id, reached)
      }
      let keys = case
        list.filter_map(plan.parent_rules, fn(entry) {
          case number_at(row, entry.1) {
            0 -> Error(Nil)
            key -> Ok(#(entry.0, key))
          }
        })
      {
        [] -> keys
        held -> dict.insert(keys, id, held)
      }
      let children =
        list.fold(plan.child_rules, children, fn(children, entry) {
          let value = number_at(row, entry.1)
          dict.upsert(children, entry.0, fn(by_value) {
            dict.upsert(option.unwrap(by_value, dict.new()), value, fn(ids) {
              [id, ..option.unwrap(ids, [])]
            })
          })
        })
      #(reaches, keys, children)
    })
  Digest(
    ids: set.from_list(list.map(rows, id_of)),
    wanted:,
    whole:,
    reaches:,
    keys:,
    children:,
  )
}

/// The rows the roots reach, and the rows of the tables that go in whole, by
/// table.
fn closure(
  digests digests: Dict(String, Digest),
  roots roots: List(#(String, Int)),
) -> Result(Selection, Refusal) {
  let whole =
    dict.fold(digests, [], fn(found, name, digest) {
      let kept = case digest.whole {
        True -> set.to_list(digest.ids)
        False -> digest.wanted
      }
      list.append(list.map(kept, fn(id) { #(name, id) }), found)
    })
  walk(queue: list.append(roots, whole), selected: dict.new(), digests:)
}

fn walk(
  queue queue: List(#(String, Int)),
  selected selected: Selection,
  digests digests: Dict(String, Digest),
) -> Result(Selection, Refusal) {
  case queue {
    [] -> Ok(selected)
    [#(table, id), ..rest] -> {
      let already =
        dict.get(selected, table)
        |> result.map(set.contains(_, id))
        |> result.unwrap(False)
      // `bool.guard` computes its `return` before it tests, so a guard whose
      // return is the recursive call would walk the rest of the queue twice.
      case already {
        True -> walk(queue: rest, selected:, digests:)
        False -> visit(table:, id:, rest:, selected:, digests:)
      }
    }
  }
}

/// Selects a row not yet selected, then walks what it reaches before the rest
/// of the queue.
fn visit(
  table table: String,
  id id: Int,
  rest rest: List(#(String, Int)),
  selected selected: Selection,
  digests digests: Dict(String, Digest),
) -> Result(Selection, Refusal) {
  let assert Ok(digest) = dict.get(digests, table)
  use <- bool.guard(
    when: !set.contains(digest.ids, id),
    return: Error(RootRowMissing(table:, id:)),
  )
  let selected =
    dict.upsert(selected, table, fn(ids) {
      set.insert(option.unwrap(ids, set.new()), id)
    })
  let reached =
    dict.get(digest.reaches, id)
    |> result.unwrap([])
    |> list.filter(fn(target) { exists(digests, target) })
  walk(
    queue: list.append(
      list.append(reached, children_of(digest:, id:, digests:)),
      rest,
    ),
    selected:,
    digests:,
  )
}

/// The child rows of a row, by each child rule whose parent is the row's table.
fn children_of(
  digest digest: Digest,
  id id: Int,
  digests digests: Dict(String, Digest),
) -> List(#(String, Int)) {
  dict.get(digest.keys, id)
  |> result.unwrap([])
  |> list.flat_map(fn(entry) {
    let #(index, key) = entry
    let assert Ok(rule) = list.drop(child_rules, index) |> list.first
    let assert Ok(child) = dict.get(digests, rule.child)
    dict.get(child.children, index)
    |> result.try(dict.get(_, key))
    |> result.unwrap([])
    |> list.map(fn(child_id) { #(rule.child, child_id) })
  })
}

/// Whether the reached row is one the client holds: an id no row holds, such as
/// a stale reference, reaches nothing.
fn exists(digests: Dict(String, Digest), target: #(String, Int)) -> Bool {
  case dict.get(digests, target.0) {
    Ok(digest) -> set.contains(digest.ids, target.1)
    Error(Nil) -> False
  }
}

// --------------------------------------------------------------- the rows

fn row_line(cells: List(Cell)) -> String {
  cells
  |> list.map(fn(cell) { cell_text(cell.value) })
  |> string.join("\t")
}

/// A table's file read from the client's folder.
fn read_table(
  entry: store.Entry,
  folder: String,
) -> Result(#(tbl_file.Schema, TableRows), Refusal) {
  let schema = store.schema(entry)
  let path = folder <> "/" <> schema.file <> ".tbl"
  use bytes <- result.try(
    simplifile.read_bits(path)
    |> result.map_error(fn(error) {
      ClientFile(table: schema.table, reason: simplifile.describe_error(error))
    }),
  )
  table_rows.read(bytes:, table: schema.file)
  |> result.map(fn(read) { #(schema, read) })
  |> result.map_error(fn(error) {
    ClientFile(table: schema.table, reason: table_rows.describe(error))
  })
}

/// The text of one table's file: the header, and the selected rows by id.
fn table_text(read: TableRows, ids: Set(Int)) -> String {
  let header = list.map(read.description.columns, fn(column) { column.name })
  let lines =
    list.filter_map(read.rows, fn(row) {
      let cells = table_rows.cells(row)
      case set.contains(ids, id_of(cells)) {
        True -> Ok(row_line(cells))
        False -> Error(Nil)
      }
    })
  string.join([string.join(header, "\t"), ..lines], "\n") <> "\n"
}

/// What the closure reads in every table: the entries, the names of the tables
/// the server loads, and the tables of the client by name.
fn context() -> #(
  List(store.Entry),
  List(String),
  Dict(String, reference.Table),
) {
  let entries = server_table.entries()
  let loaded = list.map(entries, fn(entry) { store.schema(entry).table })
  let known =
    list.filter_map(table.entries(), fn(entry) {
      let name = store.schema(entry).table
      use snake <- result.map(naming.module_name(name))
      reference.Table(snake:, type_name: name)
    })
    |> reference.index
  #(entries, loaded, known)
}

/// The references of the selected rows to ids the digests hold no row for,
/// sorted.
fn stale_of(digests: Dict(String, Digest), selected: Selection) -> List(Stale) {
  dict.fold(selected, [], fn(found, table, ids) {
    let assert Ok(digest) = dict.get(digests, table)
    set.fold(ids, found, fn(found, id) {
      dict.get(digest.reaches, id)
      |> result.unwrap([])
      |> list.filter(fn(target) { target.1 != 0 && !exists(digests, target) })
      |> list.fold(found, fn(found, target) {
        [
          Stale(table:, id:, target_table: target.0, target_id: target.1),
          ..found
        ]
      })
    })
  })
  |> list.sort(fn(a, b) {
    order.break_tie(
      string.compare(a.table, b.table),
      order.break_tie(
        int.compare(a.id, b.id),
        order.break_tie(
          string.compare(a.target_table, b.target_table),
          int.compare(a.target_id, b.target_id),
        ),
      ),
    )
  })
}

/// The text of `stale.tsv` for these references.
pub fn stale_text(stale: List(Stale)) -> String {
  let lines =
    list.map(stale, fn(entry) {
      string.join(
        [
          entry.table,
          int.to_string(entry.id),
          entry.target_table,
          int.to_string(entry.target_id),
        ],
        "\t",
      )
    })
  string.join(["table\tid\ttarget_table\ttarget_id", ..lines], "\n") <> "\n"
}

/// The references of the rows held to an id no row of the table holds, for rows
/// read from the committed files. A reference the closure follows from a row the
/// fixture holds reaches a row it holds, so these are the references the
/// client's own rows make to rows the client lacks.
pub fn stale_in(
  rows: Dict(String, List(List(Cell))),
) -> Result(List(Stale), Refusal) {
  let #(entries, loaded, known) = context()
  use digests <- result.map(
    list.try_map(entries, fn(entry) {
      let schema = store.schema(entry)
      use plan <- result.map(plan_of(
        table: schema.table,
        schema:,
        known:,
        loaded:,
      ))
      #(
        schema.table,
        digest_of(
          table: schema.table,
          rows: result.unwrap(dict.get(rows, schema.table), []),
          plan:,
        ),
      )
    })
    |> result.map(dict.from_list),
  )
  stale_of(digests, dict.map_values(digests, fn(_, digest) { digest.ids }))
}

/// The text of every file for these roots, from the client's tables in
/// `folder`. Each table is read twice, once for what it reaches and once for
/// the text of the rows chosen, so only one is in memory at a time.
pub fn generate(
  roots roots: List(Root),
  folder folder: String,
) -> Result(Fixture, Refusal) {
  let #(entries, loaded, known) = context()
  use _ <- result.try(
    list.try_each(roots, fn(root) {
      case list.contains(loaded, root.table) {
        True -> Ok(Nil)
        False -> Error(RootTableNotLoaded(root.table))
      }
    }),
  )
  use digests <- result.try(
    list.try_map(entries, fn(entry) {
      use #(schema, read) <- result.try(read_table(entry, folder))
      use plan <- result.map(plan_of(
        table: schema.table,
        schema:,
        known:,
        loaded:,
      ))
      #(
        schema.table,
        digest_of(
          table: schema.table,
          rows: list.map(read.rows, table_rows.cells),
          plan:,
        ),
      )
    })
    |> result.map(dict.from_list),
  )
  use selected <- result.try(closure(
    digests:,
    roots: list.map(roots, fn(root) { #(root.table, root.id) }),
  ))
  use tables <- result.map(
    list.try_map(entries, fn(entry) {
      use #(schema, read) <- result.map(read_table(entry, folder))
      #(
        schema.table,
        table_text(
          read,
          result.unwrap(dict.get(selected, schema.table), set.new()),
        ),
      )
    })
    |> result.map(dict.from_list),
  )
  Fixture(tables:, stale: stale_text(stale_of(digests, selected)))
}

// ------------------------------------------------------------ differences

/// How the regenerated text differs from the committed one in a row.
pub type Change {
  /// The regenerated file holds a row the committed one lacks.
  Added
  /// The committed file holds a row the regenerated one lacks.
  Removed
  /// Both hold the row, with different cells.
  Changed
}

/// A row that differs between the committed and the regenerated text of a file.
/// The header is named `header`.
pub type Difference {
  Difference(file: String, row: String, change: Change)
}

/// What a difference says.
pub fn describe_difference(difference: Difference) -> String {
  let change = case difference.change {
    Added -> "added"
    Removed -> "removed"
    Changed -> "changed"
  }
  difference.file
  <> " "
  <> difference.row
  <> " would be "
  <> change
  <> " by the generator; run `gleam run -m genesis_prime/fixture_rows` and commit"
}

/// The rows that differ between the committed text of a file and the text the
/// generator makes now, by the first `key_columns` cells of a row.
pub fn differences(
  file file: String,
  committed committed: String,
  regenerated regenerated: String,
  key_columns key_columns: Int,
) -> List(Difference) {
  let split = fn(text) {
    case string.split(text, "\n") |> list.filter(fn(line) { line != "" }) {
      [header, ..lines] -> #(
        header,
        list.map(lines, fn(line) {
          #(
            string.split(line, "\t")
              |> list.take(key_columns)
              |> string.join(" "),
            line,
          )
        })
          |> dict.from_list,
      )
      [] -> #("", dict.new())
    }
  }
  let #(old_header, old) = split(committed)
  let #(new_header, new) = split(regenerated)
  let header = case old_header == new_header {
    True -> []
    False -> [Difference(file:, row: "header", change: Changed)]
  }
  let rows =
    list.unique(list.append(dict.keys(old), dict.keys(new)))
    |> list.sort(string.compare)
    |> list.filter_map(fn(row) {
      case dict.get(old, row), dict.get(new, row) {
        Ok(a), Ok(b) if a == b -> Error(Nil)
        Ok(_), Ok(_) -> Ok(Difference(file:, row:, change: Changed))
        Ok(_), Error(Nil) -> Ok(Difference(file:, row:, change: Removed))
        Error(Nil), _ -> Ok(Difference(file:, row:, change: Added))
      }
    })
  list.append(header, rows)
}

/// The names of the tables the server loads, in the order of its entries, with
/// the file name each is committed under, without its extension.
pub fn files() -> List(#(String, String)) {
  list.map(server_table.entries(), fn(entry) {
    let schema = store.schema(entry)
    #(schema.table, schema.file)
  })
}

/// What `NOTICE` says.
fn notice() -> String {
  "The .tsv files in this folder hold rows of the tables of the WildStar client, extracted
by setup_check/extract_tables.py from the client's own game table files and read with
the server's table reader (genesis_prime/table/loader/tbl_file). Each row is copied as the
client holds it. roots.tsv names the rows the tests ask for; the generator
(dev/genesis_prime/fixture_rows.gleam) adds the rows they reach and the small tables
whole. Run `gleam run -m genesis_prime/fixture_rows` to make them again. The tests read
them as the client's rows (test/fixture_tables.gleam).
"
}

/// Writes one file of the fixture.
fn write_file(path: String, text: String) -> Result(Nil, Refusal) {
  simplifile.write(path, text)
  |> result.map_error(fn(error) {
    FileFailed(path:, reason: simplifile.describe_error(error))
  })
}

/// Writes the fixture's files into the folder.
fn write(fixture: Fixture, folder: String) -> Result(Nil, Refusal) {
  use _ <- result.try(
    simplifile.create_directory_all(folder)
    |> result.map_error(fn(error) {
      FileFailed(path: folder, reason: simplifile.describe_error(error))
    }),
  )
  use _ <- result.try(
    list.try_each(files(), fn(pair) {
      let #(table, file) = pair
      let assert Ok(text) = dict.get(fixture.tables, table)
      write_file(folder <> "/" <> file <> ".tsv", text)
    }),
  )
  use _ <- result.try(write_file(
    folder <> "/" <> stale_file <> ".tsv",
    fixture.stale,
  ))
  write_file(folder <> "/NOTICE", notice())
}

/// Makes the files again from `roots.tsv` and the client's tables.
pub fn main() -> Nil {
  let outcome = {
    use text <- result.try(
      simplifile.read(fixture_folder <> "/roots.tsv")
      |> result.map_error(fn(error) {
        FileFailed(
          path: fixture_folder <> "/roots.tsv",
          reason: simplifile.describe_error(error),
        )
      }),
    )
    use roots <- result.try(parse_roots(text))
    use fixture <- result.try(generate(roots:, folder: table_folder.path()))
    use _ <- result.map(write(fixture, fixture_folder))
    list.each(files(), fn(pair) {
      let assert Ok(text) = dict.get(fixture.tables, pair.0)
      io.println(
        pair.1
        <> ".tsv "
        <> int.to_string(list.length(string.split(text, "\n")) - 2)
        <> " rows, "
        <> int.to_string(string.length(text))
        <> " bytes",
      )
    })
  }
  case outcome {
    Ok(Nil) -> Nil
    Error(refusal) -> {
      io.println_error(describe(refusal))
      dev_exit.halt(1)
    }
  }
}
