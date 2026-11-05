//// A Prerequisite row as the client reads it, and its check against a unit: the
//// gate of an effect such as a resource gain (genesis_prime/game/spell_plan `Gain`).
//// The rule is pure: the cast rule (genesis_prime/game/cast) supplies what the unit
//// is under.
////
//// ```
//// Prerequisite row ─▶ of_row: the conditions kept up to the first type 0, AND or OR
//// the Spell4 ids of the live casts the unit is a target of ─▶ check ─▶ Passes | Fails | NotRead(type)
//// ```
////
//// - **The conditions** are read in order and cut at the first whose type is 0:
////   that one and every later one are dropped (`0x1404a5190`, `Prerequisite.flags`).
//// - **AND or OR:** the row passes when every kept condition passes, or with flags
////   bit 0 when any does; a row with no kept condition passes under AND and fails
////   under OR (`0x1404a1ca0`).
//// - **Type 15** passes, by comparison 1, when a live cast of the Spell4 in its value
////   has the unit as a target, and by comparison 2 when none has; any other
////   comparison fails, and its objectId is not read
////   (`Prerequisite.prerequisiteTypeId.15`, `0x1404a4ec0`).
//// - **A type with no case** in the client, 0 or one above 295, fails
////   (`0x1404a2100`). Every other type has a case the server does not read:
////   `NotRead`, which decides the row only when no read condition does.

import genesis_prime/table/id.{
  type PrerequisiteId, type Spell4Id, PrerequisiteId,
}
import genesis_prime/table/prerequisite as prerequisite_table
import gleam/list

/// A Prerequisite row as the client keeps it: its id, whether any condition is
/// enough (flags bit 0), and its conditions up to the first of type 0.
pub opaque type Prerequisite {
  Prerequisite(id: PrerequisiteId, any: Bool, conditions: List(Condition))
}

/// One condition: its PrerequisiteType, comparison and value. The objectId is not
/// kept: no type the server reads reads it.
type Condition {
  Condition(type_id: Int, comparison: Int, value: Int)
}

/// What a check of a prerequisite gives.
pub type Verdict {
  Passes
  Fails
  /// A condition of this PrerequisiteType decides the row, and the server does not
  /// read that type: the client would decide it, the server cannot.
  NotRead(prerequisite_type: Int)
}

/// The types from 1 to 295 that have no case in the client's condition check
/// (`0x1404a2100`): a condition of one fails.
const types_without_a_case = [
  17, 21, 32, 45, 57, 58, 72, 75, 132, 144, 156, 157, 158, 161, 165, 181, 202,
  247, 249, 257, 258, 274, 282, 284,
]

/// The highest type the client's condition check has a case for (`0x1404a2100`).
const highest_type = 295

/// The type that tests a live cast of a spell targeting the unit
/// (`Prerequisite.prerequisiteTypeId.15`).
const under_spell_type = 15

/// The row as the client keeps it (`0x1404a5190`).
pub fn of_row(row row: prerequisite_table.Prerequisite) -> Prerequisite {
  let conditions =
    [
      Condition(
        type_id: row.prerequisite_type_id0,
        comparison: row.prerequisite_comparison_id0,
        value: row.value0,
      ),
      Condition(
        type_id: row.prerequisite_type_id1,
        comparison: row.prerequisite_comparison_id1,
        value: row.value1,
      ),
      Condition(
        type_id: row.prerequisite_type_id2,
        comparison: row.prerequisite_comparison_id2,
        value: row.value2,
      ),
    ]
    |> list.take_while(fn(condition) { condition.type_id != 0 })
  Prerequisite(id: PrerequisiteId(row.id), any: row.flags % 2 != 0, conditions:)
}

/// The prerequisite's Prerequisite id.
pub fn id(prerequisite prerequisite: Prerequisite) -> PrerequisiteId {
  prerequisite.id
}

/// The prerequisite checked against a unit that is a target of live casts of the
/// spells `under` (`0x1404a1ca0`).
pub fn check(
  prerequisite prerequisite: Prerequisite,
  under under: List(Spell4Id),
) -> Verdict {
  let verdicts =
    list.map(prerequisite.conditions, fn(condition) {
      condition_check(condition:, under:)
    })
  let #(decides, otherwise) = case prerequisite.any {
    True -> #(Passes, Fails)
    False -> #(Fails, Passes)
  }
  case list.contains(verdicts, decides) {
    True -> decides
    False ->
      case list.find(verdicts, fn(verdict) { verdict != otherwise }) {
        Ok(not_read) -> not_read
        Error(Nil) -> otherwise
      }
  }
}

fn condition_check(
  condition condition: Condition,
  under under: List(Spell4Id),
) -> Verdict {
  let type_id = condition.type_id
  case type_id == under_spell_type {
    True -> {
      let found = list.any(under, fn(spell) { spell.value == condition.value })
      case condition.comparison, found {
        1, True | 2, False -> Passes
        _, _ -> Fails
      }
    }
    False ->
      case
        type_id < 1
        || type_id > highest_type
        || list.contains(types_without_a_case, type_id)
      {
        True -> Fails
        False -> NotRead(prerequisite_type: type_id)
      }
  }
}
