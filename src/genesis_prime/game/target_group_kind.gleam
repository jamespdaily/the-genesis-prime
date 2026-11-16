//// The kind of a TargetGroup row, decoded once from its `type`: the one place the server
//// names the client's TargetGroup types. A rule that tests a unit against a group matches
//// on `Kind`, so a new variant names every place that must handle it; a type the client
//// has no case for is `Unread`.
////
//// ```text
//// TargetGroup row (type) -> kind_of / of_row -> Kind -> a rule's case
//// ```
////
//// - The client's tester picks the test by the type and skips data words that are 0
////   (`0x1403b4a20`, sure); the unit's values come from `0x140b66440`.
//// - Types 1 and 2 test the unit's Creature2 id, 3 and 4 its current Faction2 id, 5 and 6
////   its race, 7 and 8 its class, 12 and 13 its UnitRace id; each odd type of the pairs
////   is a member when a data word equals the value, each even one when none does.
//// - Type 9 tests the 18-bit value of the third tagged entry of the unit's 0x262
////   (`TargetGroup.type.9`, fairly sure).
//// - Types 10 and 11 hold when every, or any, sub-group its words name passes.
//// - This module imports only the generated tables, so any game module can name a kind.

import genesis_prime/table/target_group.{type TargetGroup}

/// What a rule reads a TargetGroup row as.
pub type Kind {
  /// Type 1: the unit's Creature2 id is a data word.
  ByCreature
  /// Type 2: the unit's Creature2 id is no data word.
  NotCreature
  /// Type 3: the unit's current Faction2 id is a data word.
  ByFaction
  /// Type 4: the unit's current Faction2 id is no data word.
  NotFaction
  /// Type 5: the unit's race is a data word.
  ByRace
  /// Type 6: the unit's race is no data word.
  NotRace
  /// Type 7: the unit's class is a data word.
  ByClass
  /// Type 8: the unit's class is no data word.
  NotClass
  /// Type 9: the 18-bit value of the unit's third tagged entry is a data word.
  BySet
  /// Type 10: every sub-group its words name (not its own id) passes.
  AllOf
  /// Type 11: any sub-group its words name (not its own id) passes.
  AnyOf
  /// Type 12: the UnitRace id of the unit's Creature2 row is a data word.
  ByUnitRace
  /// Type 13: the UnitRace id of the unit's Creature2 row is no data word.
  NotUnitRace
  /// Any other type: the client's tester has no case for it, so no unit is a member.
  Unread(type_number: Int)
}

/// The kind of a group of type `type_number` (`TargetGroup.type`).
pub fn kind_of(type_number type_number: Int) -> Kind {
  case type_number {
    1 -> ByCreature
    2 -> NotCreature
    3 -> ByFaction
    4 -> NotFaction
    5 -> ByRace
    6 -> NotRace
    7 -> ByClass
    8 -> NotClass
    9 -> BySet
    10 -> AllOf
    11 -> AnyOf
    12 -> ByUnitRace
    13 -> NotUnitRace
    other -> Unread(type_number: other)
  }
}

/// The kind of a TargetGroup row.
pub fn of_row(row: TargetGroup) -> Kind {
  kind_of(type_number: row.type_)
}

/// Whether the group lists Creature2 ids in its data words: type 1.
pub fn names_creatures(kind: Kind) -> Bool {
  case kind {
    ByCreature -> True
    NotCreature
    | ByFaction
    | NotFaction
    | ByRace
    | NotRace
    | ByClass
    | NotClass
    | BySet
    | AllOf
    | AnyOf
    | ByUnitRace
    | NotUnitRace
    | Unread(_) -> False
  }
}

/// Whether the group's data words name other groups: types 10 and 11.
pub fn names_sub_groups(kind: Kind) -> Bool {
  case kind {
    AllOf | AnyOf -> True
    ByCreature
    | NotCreature
    | ByFaction
    | NotFaction
    | ByRace
    | NotRace
    | ByClass
    | NotClass
    | BySet
    | ByUnitRace
    | NotUnitRace
    | Unread(_) -> False
  }
}
