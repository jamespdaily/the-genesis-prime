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
  type PrerequisiteId, type Spell4Id, PrerequisiteId, Spell4Id,
}
import genesis_prime/table/prerequisite as prerequisite_table
import gleam/bool
import gleam/list

/// A Prerequisite row as the client keeps it: its id, whether any condition is
/// enough (flags bit 0), and its conditions up to the first of type 0.
pub opaque type Prerequisite {
  Prerequisite(id: PrerequisiteId, any: Bool, conditions: List(Condition))
}

/// One condition as the client's check reads it, decoded once from its
/// PrerequisiteType, comparison and value. The objectId is not kept: no type the
/// server reads reads it.
type Condition {
  /// Type 15: whether a live cast of the Spell4 has the unit as a target
  /// (`Prerequisite.prerequisiteTypeId.15`).
  TargetOfLiveCast(comparison: Comparison, spell4_id: Spell4Id)
  /// A type the client's check has no case for (`0x1404a2100`): it fails.
  NoCase
  /// A type the client decides and the server does not read.
  Unread(prerequisite_type: Int)
}

/// A comparison of a type 15 condition: 1 passes when a live cast is found, 2 when
/// none is, any other fails (`0x1404a4ec0`).
type Comparison {
  Found
  NotFound
  OtherComparison(comparison: Int)
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
/// (`0x1404a2100`).
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
      #(row.prerequisite_type_id0, row.prerequisite_comparison_id0, row.value0),
      #(row.prerequisite_type_id1, row.prerequisite_comparison_id1, row.value1),
      #(row.prerequisite_type_id2, row.prerequisite_comparison_id2, row.value2),
    ]
    |> list.take_while(fn(condition) { condition.0 != 0 })
    |> list.map(fn(condition) {
      condition_of(
        type_id: condition.0,
        comparison: condition.1,
        value: condition.2,
      )
    })
  Prerequisite(id: PrerequisiteId(row.id), any: row.flags % 2 != 0, conditions:)
}

fn condition_of(
  type_id type_id: Int,
  comparison comparison: Int,
  value value: Int,
) -> Condition {
  use <- bool.lazy_guard(when: type_id == under_spell_type, return: fn() {
    TargetOfLiveCast(
      comparison: case comparison {
        1 -> Found
        2 -> NotFound
        other -> OtherComparison(comparison: other)
      },
      spell4_id: Spell4Id(value),
    )
  })
  case
    type_id < 1
    || type_id > highest_type
    || list.contains(types_without_a_case, type_id)
  {
    True -> NoCase
    False -> Unread(prerequisite_type: type_id)
  }
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
  case condition {
    TargetOfLiveCast(comparison:, spell4_id:) ->
      case comparison, list.contains(under, spell4_id) {
        Found, True | NotFound, False -> Passes
        Found, False | NotFound, True -> Fails
        OtherComparison(..), True | OtherComparison(..), False -> Fails
      }
    NoCase -> Fails
    Unread(prerequisite_type:) -> NotRead(prerequisite_type:)
  }
}
