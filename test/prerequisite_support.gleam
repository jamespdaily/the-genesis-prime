//// Prerequisite rows for tests that check a prerequisite
//// (`genesis_prime/game/prerequisite`), built as the client's table holds them.

import genesis_prime/game/lasting
import genesis_prime/game/prerequisite.{type Prerequisite, type Subject, Subject}
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/positional_requirement
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
  prerequisite_of(row: row(id:, flags: 0, conditions: [condition]))
}

/// The prerequisite of a row that holds no type 108 condition, which would need a
/// PositionalRequirement row (`prerequisite_of_arcs`); a row that does is a mistake of the
/// test.
pub fn prerequisite_of(
  row row: prerequisite_table.Prerequisite,
) -> Prerequisite {
  prerequisite_of_arcs(row:, arcs: [])
}

/// The prerequisite of a row, whose type 108 conditions find their PositionalRequirement
/// rows among `arcs`, as the client's table holds them (`table_rows -- PositionalRequirement
/// 53`); a row that names none is a mistake of the test.
pub fn prerequisite_of_arcs(
  row row: prerequisite_table.Prerequisite,
  arcs arcs: List(positional_requirement.PositionalRequirement),
) -> Prerequisite {
  let assert Ok(prerequisite) =
    prerequisite.of_row_with(row:, find_arc: fn(id) {
      list.find(arcs, fn(arc) { arc.id == id })
    })
    as "the row's type 108 conditions name the arcs given"
  prerequisite
}

/// A PositionalRequirement row: its id, angleCenter, angleRange and flags.
pub fn arc_row(
  id id: Int,
  center center: Int,
  range range: Int,
  flags flags: Int,
) -> positional_requirement.PositionalRequirement {
  positional_requirement.PositionalRequirement(
    id:,
    angle_center: center,
    angle_range: range,
    flags:,
  )
}

/// Row 53 of the client's PositionalRequirement table: the 140 degrees behind the first
/// unit (`table_rows -- PositionalRequirement 53`: angleCenter 180, angleRange 140,
/// flags 0).
pub fn behind_arc() -> positional_requirement.PositionalRequirement {
  arc_row(id: 53, center: 180, range: 140, flags: 0)
}

/// A subject holding these nodes (spell, caster, stack count), whose second unit is
/// `second_unit`, out of combat, with no vital, difficulty, stealth or roll.
pub fn holding(
  held held: List(#(Int, Int, Int)),
  second_unit second_unit: Option(Int),
) -> Subject {
  Subject(
    under: list.map(held, fn(node) {
      lasting.Held(spell4_id: Spell4Id(node.0), caster: node.1, count: node.2)
    }),
    second_unit:,
    in_combat: False,
    vitals: dict.new(),
    rolls: [],
    difficulty: None,
    stealthed: None,
    positions: prerequisite.NotPlaced,
    seen: prerequisite.WholeUnit,
  )
}

/// The row checked against the subject.
pub fn check(
  row row: prerequisite_table.Prerequisite,
  subject subject: Subject,
) -> prerequisite.Verdict {
  prerequisite.check(prerequisite: prerequisite_of(row:), subject:)
}
