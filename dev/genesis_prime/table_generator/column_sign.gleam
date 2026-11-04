//// The sign each 32-bit table column is read with. The client's loader copies
//// a type-3 field as its 4 bytes and gives it no sign (`0x1407c15c0`); each
//// reader of the client decides. The generator reads a type-3 column as a
//// signed number unless `all` lists it as `Unsigned`, and the generator's
//// check refuses a loaded table's type-3 column that holds a value with bit 31
//// set and is not listed, because only then does the sign change a value.

import genesis_prime/table/loader/tbl_file
import genesis_prime/table_rows
import gleam/list
import gleam/result

/// How a listed column is read.
pub type Sign {
  /// The client's reader compares or uses the column as an unsigned number.
  Unsigned
  /// The client's reader uses the column as a signed number.
  Signed
  /// The client's readers are not read, so the column keeps the signed
  /// reading, and the entry's evidence says why that is safe for the rows the
  /// server's rules read.
  Unread
}

/// A 32-bit column with the sign its client reader uses: the client's table
/// and column names as the table file holds them, and the evidence, which
/// names the client's reader by address for `Signed` and `Unsigned`.
pub type ColumnSign {
  ColumnSign(table: String, column: String, sign: Sign, evidence: String)
}

/// A loaded table's 32-bit column that holds a value with bit 31 set and has
/// no entry in the list: the client's table and column names.
pub type Unlisted {
  Unlisted(table: String, column: String)
}

/// The columns whose client readers are known, and the loaded columns that
/// hold a value with bit 31 set (measured with `gleam run -m
/// genesis_prime/table_rows -- <Table>` on each loaded table).
pub fn all() -> List(ColumnSign) {
  [
    ColumnSign(
      table: "CharacterCustomizationSelection",
      column: "characterCustomizationLabelId",
      sign: Unsigned,
      evidence: "0x1400200e0 compares the label as unsigned",
    ),
    ColumnSign(
      table: "CharacterCustomizationSelection",
      column: "value",
      sign: Unsigned,
      evidence: "0x1400200e0 compares the value as unsigned",
    ),
    ColumnSign(
      table: "LevelUpUnlock",
      column: "level",
      sign: Unsigned,
      evidence: "0x1404b0e70 compares the level as unsigned, so -1 is above every level",
    ),
    ColumnSign(
      table: "XpPerLevel",
      column: "minXpForLevel",
      sign: Signed,
      evidence: "0x140029820 compares the experience with the column as signed: cmp ebp, dword ptr [rbx+0x4] then jl, jg",
    ),
    ColumnSign(
      table: "WorldZone",
      column: "worldLocation2IdExit",
      sign: Unread,
      evidence: "the server reads only ID and parentZoneId of WorldZone (genesis_prime/game/top_zone); two rows hold 0x86000000 here, which no rule of the server reads",
    ),
    ColumnSign(
      table: "GameFormula",
      column: "dataint0",
      sign: Unread,
      evidence: "each GameFormula row has its own reader; the one row a rule reads, 145, holds 50 (0x140029820); rows 780 and 857 hold -7 and -4",
    ),
    ColumnSign(
      table: "GameFormula",
      column: "dataint01",
      sign: Unread,
      evidence: "each GameFormula row has its own reader; no rule reads row 537, which holds -1800",
    ),
    ColumnSign(
      table: "GameFormula",
      column: "dataint02",
      sign: Unread,
      evidence: "each GameFormula row has its own reader; no rule reads row 1026, which holds -2",
    ),
    ColumnSign(
      table: "Creature2",
      column: "tradeSkillIdTrainer",
      sign: Unread,
      evidence: "the spawns read only a creature's level, faction, display group and the ids and multipliers of its Base Health (genesis_prime/world_map/spawn); no rule reads tradeSkillIdTrainer, which holds a value with bit 31 set in some rows",
    ),
    ColumnSign(
      table: "Creature2",
      column: "tradeSkillIdStation",
      sign: Unread,
      evidence: "the spawns read only a creature's level, faction, display group and the ids and multipliers of its Base Health (genesis_prime/world_map/spawn); no rule reads tradeSkillIdStation, which holds a value with bit 31 set in some rows",
    ),
    ColumnSign(
      table: "Creature2",
      column: "questAnimObjectiveIndex",
      sign: Unread,
      evidence: "the spawns read only a creature's level, faction, display group and the ids and multipliers of its Base Health (genesis_prime/world_map/spawn); no rule reads questAnimObjectiveIndex, which holds a value with bit 31 set in some rows",
    ),
    ColumnSign(
      table: "Creature2",
      column: "activationFlags",
      sign: Unread,
      evidence: "the spawns read only a creature's level, faction, display group and the ids and multipliers of its Base Health (genesis_prime/world_map/spawn); no rule reads activationFlags, which holds a value with bit 31 set in some rows",
    ),
    ColumnSign(
      table: "Creature2Difficulty",
      column: "rankValue",
      sign: Unread,
      evidence: "the spawns read only a creature's level, faction, display group and the ids and multipliers of its Base Health (genesis_prime/world_map/spawn); no rule reads rankValue, which holds a value with bit 31 set in some rows",
    ),
    ColumnSign(
      table: "WorldLocation2",
      column: "phases",
      sign: Unread,
      evidence: "no rule reads phases, which holds -1 in 27,763 rows; the loader copies the 4 bytes (0x1407c15c0)",
    ),
  ]
}

fn find(
  signs signs: List(ColumnSign),
  table table: String,
  column column: String,
) -> Result(ColumnSign, Nil) {
  list.find(signs, fn(listed) {
    listed.table == table && listed.column == column
  })
}

/// Whether the column is listed `Unsigned`. A column listed any other way, or
/// not listed, is read as a signed number.
pub fn is_unsigned(
  signs signs: List(ColumnSign),
  table table: String,
  column column: String,
) -> Bool {
  case find(signs:, table:, column:) {
    Ok(ColumnSign(sign: Unsigned, ..)) -> True
    Ok(ColumnSign(sign: Signed, ..)) | Ok(ColumnSign(sign: Unread, ..)) -> False
    Error(Nil) -> False
  }
}

/// The table's 32-bit columns that hold a value with bit 31 set and are not
/// listed, in the file's column order. A column whose every value has bit 31
/// clear reads the same signed or unsigned, so it needs no entry.
pub fn unlisted(
  signs signs: List(ColumnSign),
  read read: table_rows.TableRows,
) -> List(Unlisted) {
  let table = read.description.table
  list.filter(read.description.columns, fn(column) {
    column.column_type == tbl_file.Integer32
    && result.is_error(find(signs:, table:, column: column.name))
    && list.any(read.rows, holds_top_bit(_, column.name))
  })
  |> list.map(fn(column) { Unlisted(table:, column: column.name) })
}

/// Whether the row's value in the column is a 32-bit integer with bit 31 set,
/// which the table reader gives as a negative number.
fn holds_top_bit(row: table_rows.Row, column: String) -> Bool {
  list.any(table_rows.cells(row), fn(cell) {
    case cell.column == column, cell.value {
      True, table_rows.Integer32(value) -> value < 0
      True, table_rows.Integer64(_)
      | True, table_rows.Float32(..)
      | True, table_rows.Boolean(_)
      | True, table_rows.Text(_)
      | False, _
      -> False
    }
  })
}

/// The sentence the check prints for a column it refuses.
pub fn describe(unlisted: Unlisted) -> String {
  unlisted.table
  <> "."
  <> unlisted.column
  <> " holds a value with bit 31 set and has no entry in the sign list: add one"
  <> " with the client reader that reads it, or Unread with why a signed"
  <> " reading is safe"
}
