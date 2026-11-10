//// Whether a unit is in a TargetGroup row (`0x1403b4a20`, which a quest objective's kill
//// test calls for its data and its reward pane).

import genesis_prime/table/id.{
  type Creature2Id, type Faction2Id, type UnitRaceId, TargetGroupId,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/target_group.{type TargetGroup}
import gleam/bool
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// What the client's tester reads of a unit (`0x140b66440`): the unit's Creature2 id,
/// its current Faction2 id (the one its 0x262 gave it, which a unit the connection no
/// longer shows does not have) and the UnitRace id of its Creature2 row.
pub type Unit {
  Unit(
    creature_id: Creature2Id,
    faction_id: Option(Faction2Id),
    unit_race_id: UnitRaceId,
  )
}

/// Whether the unit is in the TargetGroup row `group`.
///
/// The client's cases: types 1, 3 and 12 are members when a non-zero data word equals
/// the unit's Creature2, Faction2 or UnitRace id, and types 2, 4 and 13 are their
/// negations. Type 10 needs every sub-group its words name (not its own id) and type 11
/// any. A missing row, or a type the client has no case for, is not a member. Types 5 to
/// 9 read the unit's race, class and the third tagged value of its 0x262, which the
/// server does not hold, so they are never members here; a type 3 or 4 group of a unit
/// whose faction the server does not know is none either, whichever way it would go.
pub fn contains(
  tables tables: table_store.Tables,
  group group: Int,
  unit unit: Unit,
) -> Bool {
  member(tables:, group:, unit:, path: [])
}

/// The membership of a group reached through the groups of `path`, which a group naming
/// itself again through the others ends as no member (the client would not return).
fn member(
  tables tables: table_store.Tables,
  group group: Int,
  unit unit: Unit,
  path path: List(Int),
) -> Bool {
  use <- bool.guard(when: list.contains(path, group), return: False)
  target_group.get(tables:, id: TargetGroupId(group))
  |> result.map(fn(row) { row_has(tables:, row:, unit:, path: [group, ..path]) })
  |> result.unwrap(or: False)
}

fn row_has(
  tables tables: table_store.Tables,
  row row: TargetGroup,
  unit unit: Unit,
  path path: List(Int),
) -> Bool {
  let words = [
    row.data0,
    row.data1,
    row.data2,
    row.data3,
    row.data4,
    row.data5,
    row.data6,
  ]
  case row.type_ {
    1 -> names(words:, value: unit.creature_id.value)
    2 -> !names(words:, value: unit.creature_id.value)
    3 -> by_faction(words:, unit:, wanted: True)
    4 -> by_faction(words:, unit:, wanted: False)
    12 -> names(words:, value: unit.unit_race_id.value)
    13 -> !names(words:, value: unit.unit_race_id.value)
    10 ->
      list.all(others(words:, row:), fn(sub) {
        member(tables:, group: sub, unit:, path:)
      })
    11 ->
      list.any(others(words:, row:), fn(sub) {
        member(tables:, group: sub, unit:, path:)
      })
    _ -> False
  }
}

/// Whether a non-zero word equals the value: the client skips the zero words.
fn names(words words: List(Int), value value: Int) -> Bool {
  list.any(words, fn(word) { word != 0 && word == value })
}

fn by_faction(
  words words: List(Int),
  unit unit: Unit,
  wanted wanted: Bool,
) -> Bool {
  case unit.faction_id {
    Some(faction) -> names(words:, value: faction.value) == wanted
    None -> False
  }
}

/// The non-zero words of a type 10 or 11 group that are not its own id.
fn others(words words: List(Int), row row: TargetGroup) -> List(Int) {
  list.filter(words, fn(word) { word != 0 && word != row.id })
}
