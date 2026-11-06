//// Prerequisite rows for tests that check a prerequisite
//// (`genesis_prime/game/prerequisite`), built as the client's table holds them.

import genesis_prime/game/lasting
import genesis_prime/game/prerequisite.{type Prerequisite, type Subject, Subject}
import genesis_prime/table/id.{PrerequisiteId, Spell4Id}
import genesis_prime/table/prerequisite as prerequisite_table
import gleam/dict
import gleam/list
import gleam/option.{type Option, None}

/// A Prerequisite row with these conditions, as (type, comparison, objectId,
/// value), and these flags.
pub fn row(
  id id: Int,
  flags flags: Int,
  conditions conditions: List(#(Int, Int, Int, Int)),
) -> prerequisite_table.Prerequisite {
  let at = fn(index) {
    case list.drop(conditions, index) {
      [condition, ..] -> condition
      [] -> #(0, 0, 0, 0)
    }
  }
  let #(type0, comparison0, object0, value0) = at(0)
  let #(type1, comparison1, object1, value1) = at(1)
  let #(type2, comparison2, object2, value2) = at(2)
  prerequisite_table.Prerequisite(
    id:,
    flags:,
    prerequisite_type_id0: type0,
    prerequisite_type_id1: type1,
    prerequisite_type_id2: type2,
    prerequisite_comparison_id0: comparison0,
    prerequisite_comparison_id1: comparison1,
    prerequisite_comparison_id2: comparison2,
    object_id0: object0,
    object_id1: object1,
    object_id2: object2,
    value0:,
    value1:,
    value2:,
    localized_text_id_failure: 0,
  )
}

/// The prerequisite of a row with one condition, as (type, comparison, objectId,
/// value), under AND.
pub fn single(
  id id: Int,
  condition condition: #(Int, Int, Int, Int),
) -> Prerequisite {
  loaded(id:, rows: [row(id:, flags: 0, conditions: [condition])])
}

/// The prerequisite with this id as `load` makes it from rows held in memory: the
/// planted table is these rows.
pub fn load_from(
  id id: Int,
  rows rows: List(prerequisite_table.Prerequisite),
) -> Result(Prerequisite, prerequisite.LoadError) {
  prerequisite.load(id: PrerequisiteId(id), rows: fn(wanted) {
    list.find(rows, fn(row) { row.id == wanted.value })
  })
}

/// The same, which must load.
pub fn loaded(
  id id: Int,
  rows rows: List(prerequisite_table.Prerequisite),
) -> Prerequisite {
  let assert Ok(loaded) = load_from(id:, rows:)
    as "the rows held in memory load: every id they name has a row"
  loaded
}

/// A subject holding these nodes (spell, caster, stack count), whose second unit is
/// `second_unit`, out of combat, with no vital, difficulty, stealth or roll.
pub fn holding(
  held held: List(#(Int, Int, Int)),
  second_unit second_unit: Option(Int),
) -> Subject {
  Subject(
    under: list.map(held, fn(node) {
      lasting.Held(
        spell4_id: Spell4Id(node.0),
        caster: node.1,
        count: node.2,
        groups: [],
      )
    }),
    second_unit:,
    in_combat: False,
    vitals: dict.new(),
    rolls: [],
    difficulty: None,
    stealthed: None,
    resource_slots: None,
  )
}

/// The row checked against the subject.
pub fn check(
  row row: prerequisite_table.Prerequisite,
  subject subject: Subject,
) -> prerequisite.Verdict {
  prerequisite.check(prerequisite: loaded(id: row.id, rows: [row]), subject:)
}
