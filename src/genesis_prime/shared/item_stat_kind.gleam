//// The kind of an ItemStat entry or an ItemRandomStat row, decoded once from its kind
//// number and data: the one place the server names the client's item stat kinds. A rule
//// that reads an item's stats matches on `Kind`, so a new variant names every place that
//// must handle it; a kind no rule reads is `Unread`.
////
//// ```text
//// ItemStat entry (kind, data) / ItemRandomStat row -> kind_of / of_stat / of_random_row
////   -> Kind -> a rule's case or accessor
//// ```
////
//// - The client's builder reads kind 0 as no stat, kind 1 as a property (the data is a
////   UnitProperty2 id), kind 2 as an ItemRandomStatGroup id whose row the item's
////   random-stat byte picks, and kind 4 as a crafting-socket entry; any other kind fails
////   with 0x70 (`0x14040e6d0`, `0x14040ca70`, `0x14040d5d0`).
//// - The data of kind 4 is a crafting-group mask (a guess, `ItemStat.itemStatData.kind4`);
////   no rule reads it, so the variant carries none.
//// - Every ItemRandomStat row is kind 1 (`ItemRandomStat.itemRandomStatGroupId`).
//// - This module imports only the generated tables and typed ids, so any game module can
////   name a kind.

import genesis_prime/table/id.{
  type ItemRandomStatGroupId, type UnitProperty2Id, ItemRandomStatGroupId,
  UnitProperty2Id,
}
import genesis_prime/table/item_random_stat.{type ItemRandomStat}
import genesis_prime/table/item_stat.{type ItemStat}

/// What a rule reads an item stat entry as.
pub type Kind {
  /// Kind 0: the entry adds nothing (`0x14040ca70`).
  NoStat
  /// Kind 1: a property; the data is a UnitProperty2 id (`0x14040e6d0`).
  Property(unit_property2_id: UnitProperty2Id)
  /// Kind 2: a random stat group; the data is an ItemRandomStatGroup id, and a byte of
  /// the item's random-stat word picks the row (`0x14040e6d0`).
  RandomGroup(item_random_stat_group_id: ItemRandomStatGroupId)
  /// Kind 4: a property that crafting picks (`0x14040ca70`); its data is not read.
  CraftingSocket
  /// Any other kind: the client's builder refuses it with 0x70, and no client row holds
  /// one.
  Unread(kind_number: Int)
}

/// The kind of an entry of kind `kind_number` with `data` (`ItemStat.itemStatTypeEnum00`,
/// `ItemStat.itemStatData00`).
pub fn kind_of(kind_number kind_number: Int, data data: Int) -> Kind {
  case kind_number {
    0 -> NoStat
    1 -> Property(UnitProperty2Id(data))
    2 -> RandomGroup(ItemRandomStatGroupId(data))
    4 -> CraftingSocket
    other -> Unread(kind_number: other)
  }
}

/// The kind of each of an ItemStat's five entries, in order.
pub fn of_stat(stat: ItemStat) -> List(Kind) {
  [
    kind_of(
      kind_number: stat.item_stat_type_enum00,
      data: stat.item_stat_data00,
    ),
    kind_of(
      kind_number: stat.item_stat_type_enum01,
      data: stat.item_stat_data01,
    ),
    kind_of(
      kind_number: stat.item_stat_type_enum02,
      data: stat.item_stat_data02,
    ),
    kind_of(
      kind_number: stat.item_stat_type_enum03,
      data: stat.item_stat_data03,
    ),
    kind_of(
      kind_number: stat.item_stat_type_enum04,
      data: stat.item_stat_data04,
    ),
  ]
}

/// The kind of an ItemRandomStat row.
pub fn of_random_row(row: ItemRandomStat) -> Kind {
  kind_of(kind_number: row.item_stat_type_enum, data: row.item_stat_data)
}

/// The kind number the client's table holds for the kind.
pub fn number_of(kind: Kind) -> Int {
  case kind {
    NoStat -> 0
    Property(_) -> 1
    RandomGroup(_) -> 2
    CraftingSocket -> 4
    Unread(kind_number:) -> kind_number
  }
}

/// The property a kind 1 entry names.
pub fn property_of(kind: Kind) -> Result(UnitProperty2Id, Nil) {
  case kind {
    Property(unit_property2_id:) -> Ok(unit_property2_id)
    NoStat | RandomGroup(_) | CraftingSocket | Unread(_) -> Error(Nil)
  }
}

/// The random stat group a kind 2 entry names.
pub fn random_group_of(kind: Kind) -> Result(ItemRandomStatGroupId, Nil) {
  case kind {
    RandomGroup(item_random_stat_group_id:) -> Ok(item_random_stat_group_id)
    NoStat | Property(_) | CraftingSocket | Unread(_) -> Error(Nil)
  }
}

/// Whether the entry is a crafting socket, which the item's random-stat word cannot fill.
pub fn is_crafting_socket(kind: Kind) -> Bool {
  case kind {
    CraftingSocket -> True
    NoStat | Property(_) | RandomGroup(_) | Unread(_) -> False
  }
}
