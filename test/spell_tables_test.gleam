//// The planted spell rows (`spell_tables`) are the client's own rows: each row
//// holds the value the client's row of the same id holds in every column the
//// plan reads, and in every other column it sets. A column the planted row leaves
//// at 0 that the plan does not read is not compared. The comparison is of the
//// records' bytes, field by field, as the file lays them out.

import client_tables
import genesis_prime/table/class
import genesis_prime/table/loader/tbl_file.{type Field, type Records, Field}
import genesis_prime/table/prerequisite
import genesis_prime/table/spell4
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_conditions
import genesis_prime/table/spell4_effects
import genesis_prime/table/spell4_stack_group
import genesis_prime/table/spell4_thresholds
import genesis_prime/table/spell_cool_down
import genesis_prime/table/spell_level
import genesis_prime/table/spell_phase
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import owned_test
import planted_table.{type Cell}
import spell_tables
import unitest

/// The records of a table's bytes, by the id each begins with, as the bytes of
/// each record.
fn by_id(records records: Records) -> Dict(Int, BitArray) {
  let size = records.description.record_size
  list.repeat(Nil, records.description.record_count)
  |> list.index_map(fn(_, index) {
    let assert Ok(record) = bit_array.slice(records.bytes, index * size, size)
      as "the records are whole"
    let assert <<id:size(32)-little, _:bits>> = record
      as "a record begins with its 32-bit id"
    #(id, record)
  })
  |> dict.from_list
}

/// The 4 or 8 bytes of a field of a record.
fn field_of(record record: BitArray, field field: Field) -> BitArray {
  let width = case field.column.column_type {
    tbl_file.Integer64 | tbl_file.Utf16Text -> 8
    tbl_file.Integer32 | tbl_file.Float32 | tbl_file.Boolean32 -> 4
  }
  let assert Ok(bytes) = bit_array.slice(record, field.offset, width)
    as "the field lies in the record"
  bytes
}

fn is_zero(bytes: BitArray) -> Bool {
  case bytes {
    <<0:size(32)>> | <<0:size(64)>> -> True
    _ -> False
  }
}

/// The columns of the planted rows whose value is not the client's, each as the
/// table, the row and the column.
fn differences(
  schema schema: tbl_file.Schema,
  rows rows: List(List(Cell)),
  read read: List(String),
) -> List(String) {
  let assert Ok(real) = tbl_file.records(client_tables.read(schema.file))
    as "the client's table reads"
  let assert Ok(planted) =
    tbl_file.records(planted_table.bytes(planted_table.table(schema:, rows:)))
    as "the planted table reads"
  let real_by_id = by_id(records: real)
  let #(fields, _) = tbl_file.layout(schema.columns)
  list.flat_map(dict.to_list(by_id(records: planted)), fn(entry) {
    let #(id, record) = entry
    let name = schema.table <> " " <> int.to_string(id)
    case dict.get(real_by_id, id) {
      Error(Nil) -> [name <> " has no row in the client's table"]
      Ok(real_record) ->
        list.filter_map(fields, fn(field) {
          let Field(column:, ..) = field
          let planted_value = field_of(record:, field:)
          let compared = case column.column_type {
            tbl_file.Utf16Text -> False
            tbl_file.Integer32
            | tbl_file.Float32
            | tbl_file.Boolean32
            | tbl_file.Integer64 ->
              !is_zero(planted_value) || list.contains(read, column.name)
          }
          case
            compared && planted_value != field_of(record: real_record, field:)
          {
            True -> Ok(name <> ", column " <> column.name)
            False -> Error(Nil)
          }
        })
    }
  })
}

pub fn every_planted_spell_row_holds_the_clients_values_in_each_column_it_sets_or_the_plan_reads_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let rows = spell_tables.rows_with_stealth()
  let found =
    list.flatten([
      differences(schema: spell4.schema, rows: rows.spell4, read: [
        "spell4BaseIdBaseSpell", "castTime", "spellCoolDown", "innateCostType0",
        "innateCost0", "innateCostType1", "innateCost1", "channelInitialDelay",
        "channelMaxTime", "channelPulseTime", "thresholdTime",
        "spellCoolDownIdGlobal", "globalCooldownEnum", "propertyFlags",
        "spell4ConditionsIdCaster", "spellCastStealthChange",
      ]),
      differences(
        schema: spell4_conditions.schema,
        rows: rows.spell4_conditions,
        read: ["conditionMask", "conditionValue"],
      ),
      differences(schema: spell4_base.schema, rows: rows.spell4_base, read: [
        "castMethod", "weaponSlot", "castBarType", "classIdPlayer",
      ]),
      differences(
        schema: spell4_effects.schema,
        rows: rows.spell4_effects,
        read: [
          "spellId", "effectType", "delayTime", "phaseFlags", "dataBits00",
          "prerequisiteIdCasterApply", "prerequisiteIdTargetApply", "orderIndex",
        ],
      ),
      differences(
        schema: spell4_thresholds.schema,
        rows: rows.spell4_thresholds,
        read: [
          "spell4IdParent", "spell4IdToCast", "orderIndex", "thresholdDuration",
          "vitalEnumCostType00", "vitalEnumCostType01", "vitalCostValue00",
          "vitalCostValue01",
        ],
      ),
      differences(schema: spell_phase.schema, rows: rows.spell_phases, read: [
        "phaseDelay", "phaseFlags", "orderIndex", "spell4IdOwner",
      ]),
      differences(
        schema: spell_cool_down.schema,
        rows: rows.spell_cool_downs,
        read: ["cooldownTime"],
      ),
      differences(
        schema: spell4_stack_group.schema,
        rows: rows.spell4_stack_groups,
        read: ["stackCap"],
      ),
      differences(schema: prerequisite.schema, rows: rows.prerequisites, read: [
        "flags",
      ]),
      // The SpellLevel row 99421 is test data (`spell_tables.rows_with_stealth`): the
      // client holds none for 46073.
      differences(
        schema: spell_level.schema,
        rows: list.filter(rows.spell_levels, fn(row) {
          case row {
            [planted_table.Integer(99_421), ..] -> False
            _ -> True
          }
        }),
        read: ["classId", "characterLevel", "prerequisiteId", "spell4Id"],
      ),
      differences(schema: class.schema, rows: rows.classes, read: [
        "vitalEnumResource00", "vitalEnumResource01", "vitalEnumResource02",
        "vitalEnumResource03", "vitalEnumResource04", "vitalEnumResource05",
        "vitalEnumResource06", "vitalEnumResource07",
      ]),
    ])
  assert found == []
    as "each planted row is the client's row in every column it sets and every column the plan reads"
}
