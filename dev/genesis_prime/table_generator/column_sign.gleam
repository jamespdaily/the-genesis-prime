//// The sign each 32-bit table column is read with. The client's loader copies
//// a type-3 field as its 4 bytes and gives it no sign (`0x1407c15c0`); each
//// reader of the client decides. The generator reads a type-3 column as a
//// signed number unless `all` lists it as `Unsigned`, and the generator's
//// check refuses a loaded table's type-3 column that holds a value with bit 31
//// set and is not listed, because only then does the sign change a value.

import genesis_prime/table/loader/tbl_file
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
      table: "Item2",
      column: "powerLevel",
      sign: Unread,
      evidence: "the server reads the power level of the 44 Novice items only (genesis_prime/game/item_property, genesis_prime/game/worn_visual), all 2 (Item2.novice_set); one Item2 row holds -1, which no rule reads",
    ),
    ColumnSign(
      table: "ItemDisplay",
      column: "componentRegionFlags",
      sign: Unread,
      evidence: "the server reads only the ID of ItemDisplay, to check that a worn item's display has a row (genesis_prime/game/worn_visual); no rule reads componentRegionFlags, which holds a value with bit 31 set in some rows",
    ),
    ColumnSign(
      table: "Item2",
      column: "maxCharges",
      sign: Unread,
      evidence: "no rule reads maxCharges, which holds -1 in one row",
    ),
    ColumnSign(
      table: "Item2",
      column: "questObjectiveActivationRequired",
      sign: Unread,
      evidence: "no rule reads questObjectiveActivationRequired, which holds -1 in 316 rows",
    ),
    ColumnSign(
      table: "Spell4",
      column: "spellDuration",
      sign: Unread,
      evidence: "no rule of the server reads spellDuration (genesis_prime/game/spell_plan reads castTime, spellCoolDown, the global cooldown and cost columns, genesis_prime/game/loadout spell4BaseIdBaseSpell); it holds -1 in 858 rows",
    ),
    ColumnSign(
      table: "Spell4",
      column: "channelMaxTime",
      sign: Unread,
      evidence: "no rule of the server reads channelMaxTime (genesis_prime/game/spell_plan reads castTime, spellCoolDown, the global cooldown and cost columns, genesis_prime/game/loadout spell4BaseIdBaseSpell); it holds -1 in 6 rows",
    ),
    ColumnSign(
      table: "Spell4",
      column: "propertyFlags",
      sign: Unread,
      evidence: "genesis_prime/game/spell_plan tests bits 0x1, 0x10 and 0x40 of propertyFlags with a bitwise and, which gives the same answer for the signed and the unsigned reading of the 32 bits; 6 rows hold a value with bit 31 set",
    ),
    ColumnSign(
      table: "Spell4Effects",
      column: "dataBits00",
      sign: Unread,
      evidence: "the server reads dataBits00 of the Proxy effects only (genesis_prime/game/spell_plan), a Spell4 id that the load looks up, so a Proxy row with bit 31 set would fail the load and none does; a row of another effect type holds a value with bit 31 set, which no rule reads",
    ),
    ColumnSign(
      table: "Spell4Effects",
      column: "dataBits01",
      sign: Unread,
      evidence: "no rule of the server reads dataBits01 of Spell4Effects (genesis_prime/game/spell_plan reads spellId, effectType, delayTime, phaseFlags, dataBits00 and the apply prerequisites); a row holds a value with bit 31 set",
    ),
    ColumnSign(
      table: "Spell4Effects",
      column: "dataBits02",
      sign: Unread,
      evidence: "no rule of the server reads dataBits02 of Spell4Effects (genesis_prime/game/spell_plan reads spellId, effectType, delayTime, phaseFlags, dataBits00 and the apply prerequisites); a row holds a value with bit 31 set",
    ),
    ColumnSign(
      table: "Spell4Effects",
      column: "dataBits03",
      sign: Unread,
      evidence: "no rule of the server reads dataBits03 of Spell4Effects (genesis_prime/game/spell_plan reads spellId, effectType, delayTime, phaseFlags, dataBits00 and the apply prerequisites); a row holds a value with bit 31 set",
    ),
    ColumnSign(
      table: "Spell4Effects",
      column: "dataBits04",
      sign: Unread,
      evidence: "no rule of the server reads dataBits04 of Spell4Effects (genesis_prime/game/spell_plan reads spellId, effectType, delayTime, phaseFlags, dataBits00 and the apply prerequisites); a row holds a value with bit 31 set",
    ),
    ColumnSign(
      table: "Spell4Effects",
      column: "dataBits05",
      sign: Unread,
      evidence: "no rule of the server reads dataBits05 of Spell4Effects (genesis_prime/game/spell_plan reads spellId, effectType, delayTime, phaseFlags, dataBits00 and the apply prerequisites); a row holds a value with bit 31 set",
    ),
    ColumnSign(
      table: "Spell4Effects",
      column: "dataBits06",
      sign: Unread,
      evidence: "no rule of the server reads dataBits06 of Spell4Effects (genesis_prime/game/spell_plan reads spellId, effectType, delayTime, phaseFlags, dataBits00 and the apply prerequisites); a row holds a value with bit 31 set",
    ),
    ColumnSign(
      table: "Spell4Effects",
      column: "dataBits07",
      sign: Unread,
      evidence: "no rule of the server reads dataBits07 of Spell4Effects (genesis_prime/game/spell_plan reads spellId, effectType, delayTime, phaseFlags, dataBits00 and the apply prerequisites); a row holds a value with bit 31 set",
    ),
    ColumnSign(
      table: "Spell4Effects",
      column: "dataBits08",
      sign: Unread,
      evidence: "no rule of the server reads dataBits08 of Spell4Effects (genesis_prime/game/spell_plan reads spellId, effectType, delayTime, phaseFlags, dataBits00 and the apply prerequisites); a row holds a value with bit 31 set",
    ),
    ColumnSign(
      table: "Spell4Effects",
      column: "phaseFlags",
      sign: Unread,
      evidence: "genesis_prime/game/spell_plan tests phaseFlags bit n of a phase with a bitwise and, which gives the same answer for the signed and the unsigned reading of the 32 bits (-1 and 0xffffffff both fire in every phase)",
    ),
    ColumnSign(
      table: "TelegraphDamage",
      column: "telegraphTimeEndMs",
      sign: Unread,
      evidence: "no rule of the server reads telegraphTimeEndMs of TelegraphDamage (genesis_prime/game/spell_area reads damageShapeEnum, param00 to param05, the position offsets, rotationDegrees, telegraphDamageFlags by bit and targetTypeFlags); a row holds a value with bit 31 set",
    ),
    ColumnSign(
      table: "TelegraphDamage",
      column: "phaseFlags",
      sign: Unread,
      evidence: "no rule of the server reads phaseFlags of TelegraphDamage (genesis_prime/game/spell_area reads damageShapeEnum, param00 to param05, the position offsets, rotationDegrees, telegraphDamageFlags by bit and targetTypeFlags); a row holds a value with bit 31 set",
    ),
    ColumnSign(
      table: "TelegraphDamage",
      column: "spellThresholdRestrictionFlags",
      sign: Unread,
      evidence: "no rule of the server reads spellThresholdRestrictionFlags of TelegraphDamage (genesis_prime/game/spell_area reads damageShapeEnum, param00 to param05, the position offsets, rotationDegrees, telegraphDamageFlags by bit and targetTypeFlags); a row holds a value with bit 31 set",
    ),
    ColumnSign(
      table: "TelegraphDamage",
      column: "opacityModifier",
      sign: Unread,
      evidence: "no rule of the server reads opacityModifier of TelegraphDamage (genesis_prime/game/spell_area reads damageShapeEnum, param00 to param05, the position offsets, rotationDegrees, telegraphDamageFlags by bit and targetTypeFlags); a row holds a value with bit 31 set",
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

/// The 32-bit columns of the table file that hold a value with bit 31 set and
/// are not listed, in the file's column order. A column whose every value has
/// bit 31 clear reads the same signed or unsigned, so it needs no entry. The
/// file's records are read in one pass, only the bytes that hold bit 31 of a
/// column not yet found to hold one, and the pass stops when every unlisted
/// column has. An error when the file is not a table file, has no 32-bit
/// integer `id` as its first column, or has a record size the placement rule
/// does not give.
pub fn unlisted(
  signs signs: List(ColumnSign),
  bytes bytes: BitArray,
) -> Result(List(Unlisted), Nil) {
  use tbl_file.Records(description:, bytes: records) <- result.try(
    tbl_file.records(bytes) |> result.replace_error(Nil),
  )
  use fields <- result.map(
    tbl_file.fields(description) |> result.replace_error(Nil),
  )
  let table = description.table
  let candidates =
    list.filter(fields, fn(field) {
      field.column.column_type == tbl_file.Integer32
      && result.is_error(find(signs:, table:, column: field.column.name))
    })
  let held =
    holding_top_bit(
      records:,
      record_size: description.record_size,
      pending: list.map(candidates, fn(field) { field.offset }),
      held: [],
    )
  list.filter(candidates, fn(field) { list.contains(held, field.offset) })
  |> list.map(fn(field) { Unlisted(table:, column: field.column.name) })
}

/// The offsets, among the pending ones, of the 32-bit fields that hold bit 31
/// in some record, walking the records one after another.
fn holding_top_bit(
  records records: BitArray,
  record_size record_size: Int,
  pending pending: List(Int),
  held held: List(Int),
) -> List(Int) {
  case pending, records {
    [], _ -> held
    _, <<record:bytes-size(record_size), rest:bits>> if record_size > 0 -> {
      let #(found, still_pending) =
        list.partition(pending, holds_top_bit(record, _))
      holding_top_bit(
        records: rest,
        record_size:,
        pending: still_pending,
        held: list.append(found, held),
      )
    }
    _, _ -> held
  }
}

/// Whether the 32-bit field at the offset has bit 31 set: the first bit of the
/// field's last byte, which is its highest as the bytes are little-endian.
fn holds_top_bit(record: BitArray, offset: Int) -> Bool {
  let last_byte = offset + 3
  case record {
    <<_:bytes-size(last_byte), top:size(1), _:bits>> -> top == 1
    _ ->
      panic as "a placed 32-bit field ends inside its record, because the record size is the placed fields' end rounded up (tbl_file.layout), and a record is read whole"
  }
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
