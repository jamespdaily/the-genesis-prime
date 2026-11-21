//// Whether a unit is in a TargetGroup row (`0x1403b4a20`, which a quest objective's kill
//// test calls for its data and its reward pane).

import genesis_prime/game/objective_kind.{type PlacedTarget}
import genesis_prime/game/target_group_kind
import genesis_prime/gap
import genesis_prime/table/id.{
  type Creature2Id, type Faction2Id, type UnitRaceId, Creature2Id, TargetGroupId,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/target_group.{type TargetGroup}
import gleam/bool
import gleam/list
import gleam/result

/// What the client's tester reads of a unit (`0x140b66440`): the unit's Creature2 id,
/// its current Faction2 id (the one its 0x262 gave it, which its spawn row holds) and
/// the UnitRace id of its Creature2 row.
pub type Unit {
  Unit(
    creature_id: Creature2Id,
    faction_id: Faction2Id,
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
/// server does not hold, so they are never members here, though server rules reach type 9
/// groups.
pub fn contains(
  tables tables: table_store.Tables,
  group group: Int,
  unit unit: Unit,
) -> Bool {
  member(tables:, group:, unit:, path: [])
}

/// The Creature2 ids a group lists, each once, in the order of its words and
/// depth first through the groups a type 10 or 11 group names: the words of a
/// type 1 group. The other types hold a unit by a test of its faction or race, or
/// the opposite of a list, so they list no creature. A listed creature may still
/// be no member (a type 10 group needs every sub-group), so a caller that needs
/// members asks `contains` of each.
pub fn listed_creatures(
  tables tables: table_store.Tables,
  group group: Int,
) -> List(Int) {
  listed(tables:, group:, path: []) |> list.unique
}

/// The Creature2 ids a kill objective's placed target names: the one creature of a type 2
/// objective, or the creatures a type 8 or 16 objective's TargetGroup lists
/// (`listed_creatures`). A group that holds a unit by its faction or race lists none.
pub fn placed_creatures(
  tables tables: table_store.Tables,
  placed placed: PlacedTarget,
) -> List(Int) {
  case placed {
    objective_kind.OneCreature(creature2_id:) -> [creature2_id.value]
    objective_kind.GroupOf(target_group_id:) ->
      listed_creatures(tables:, group: target_group_id.value)
  }
}

fn listed(
  tables tables: table_store.Tables,
  group group: Int,
  path path: List(Int),
) -> List(Int) {
  use <- bool.guard(when: list.contains(path, group), return: [])
  case target_group.get(tables:, id: TargetGroupId(group)) {
    Error(Nil) -> []
    Ok(row) -> {
      case target_group_kind.names_sub_groups(target_group_kind.of_row(row)) {
        True ->
          list.flat_map(others(words: words_of(row:), row:), fn(sub) {
            listed(tables:, group: sub, path: [group, ..path])
          })
        False -> list.map(creatures_in(row:), fn(creature) { creature.value })
      }
    }
  }
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
  let words = words_of(row:)
  case target_group_kind.of_row(row) {
    target_group_kind.ByCreature -> names(words:, value: unit.creature_id.value)
    target_group_kind.NotCreature ->
      !names(words:, value: unit.creature_id.value)
    target_group_kind.ByFaction -> by_faction(words:, unit:, wanted: True)
    target_group_kind.NotFaction -> by_faction(words:, unit:, wanted: False)
    target_group_kind.ByUnitRace ->
      names(words:, value: unit.unit_race_id.value)
    target_group_kind.NotUnitRace ->
      !names(words:, value: unit.unit_race_id.value)
    target_group_kind.AllOf ->
      list.all(others(words:, row:), fn(sub) {
        member(tables:, group: sub, unit:, path:)
      })
    target_group_kind.AnyOf ->
      list.any(others(words:, row:), fn(sub) {
        member(tables:, group: sub, unit:, path:)
      })
    // The unit's race, class and 0x262 set value are not held: never members.
    target_group_kind.ByRace
    | target_group_kind.NotRace
    | target_group_kind.ByClass
    | target_group_kind.NotClass
    | target_group_kind.BySet
    | target_group_kind.Unread(_) -> False
  }
}

/// The data words of a row, the zero ones included.
fn words_of(row row: TargetGroup) -> List(Int) {
  [row.data0, row.data1, row.data2, row.data3, row.data4, row.data5, row.data6]
}

/// The Creature2 ids a group of type 1 names (the non-zero words `contains` tests a unit's
/// Creature2 id against), none for a group of another type or one the table lacks.
pub fn creatures_of(
  tables tables: table_store.Tables,
  group group: Int,
) -> List(Creature2Id) {
  case target_group.get(tables:, id: TargetGroupId(group)) {
    Ok(row) -> creatures_in(row:)
    Error(Nil) -> []
  }
}

/// The Creature2 ids a row names: its non-zero words when it is of type 1, none for
/// any other type.
fn creatures_in(row row: TargetGroup) -> List(Creature2Id) {
  case target_group_kind.names_creatures(target_group_kind.of_row(row)) {
    True ->
      words_of(row:)
      |> list.filter(fn(word) { word != 0 })
      |> list.map(Creature2Id)
    False -> []
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
  names(words:, value: unit.faction_id.value) == wanted
}

/// The non-zero words of a type 10 or 11 group that are not its own id.
fn others(words words: List(Int), row row: TargetGroup) -> List(Int) {
  list.filter(words, fn(word) { word != 0 && word != row.id })
}

/// The memberships the client's TargetGroup types give that the server does not.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Target groups",
      missing: "the membership of a TargetGroup of types 5 to 9, which read a unit's race, class and the third tagged value of its 0x262: the server holds none, so no unit is a member",
    ),
  ]
}
