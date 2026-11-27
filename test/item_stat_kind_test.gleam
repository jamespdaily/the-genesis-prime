//// The decode of an ItemStat entry's or an ItemRandomStat row's kind number and data into
//// one kind (genesis_prime/shared/item_stat_kind). Expected values and their sources:
//// - What each kind is: the client's builder `0x14040ca70` (kind 0 adds nothing, kind 4 is
////   a crafting entry, any other kind than 1 and 2 fails with 0x70) and `0x14040e6d0` (kind
////   1's data is a UnitProperty2 id, kind 2's an ItemRandomStatGroup id); `0x14040d5d0`
////   reads a random row's own kind.
//// - Kind 4 carries no data: its data is a guess (`ItemStat.itemStatData.kind4`) no rule
////   reads.
//// - The client's tables: every ItemStat cell is kind 0, 1, 2 or 4 (454 rows of 5 cells)
////   and every ItemRandomStat row (52) is kind 1 (`ItemRandomStat.itemRandomStatGroupId`).

import client_tables
import genesis_prime/shared/item_stat_kind.{
  CraftingSocket, NoStat, Property, RandomGroup, Unread,
}
import genesis_prime/table/id.{ItemRandomStatGroupId, UnitProperty2Id}
import genesis_prime/table/item_random_stat
import genesis_prime/table/item_stat
import gleam/list
import owned_test
import unitest

/// A data value no table row needs to hold: the kind must carry it through.
const data = 7777

pub fn item_stat_kind_decodes_each_kind_to_its_variant_test() -> Nil {
  use <- owned_test.run(10_000)
  assert item_stat_kind.kind_of(kind_number: 0, data:) == NoStat
    as "0x14040ca70: kind 0 adds nothing"
  assert item_stat_kind.kind_of(kind_number: 1, data:)
    == Property(UnitProperty2Id(data))
    as "0x14040e6d0: kind 1's data is a UnitProperty2 id"
  assert item_stat_kind.kind_of(kind_number: 2, data:)
    == RandomGroup(ItemRandomStatGroupId(data))
    as "0x14040e6d0: kind 2's data is an ItemRandomStatGroup id"
  assert item_stat_kind.kind_of(kind_number: 4, data:) == CraftingSocket
    as "0x14040ca70: kind 4 is a crafting entry; its data (a guess) is not carried"
  assert item_stat_kind.kind_of(kind_number: 4, data: 0)
    == item_stat_kind.kind_of(kind_number: 4, data:)
    as "kind 4 is the same whatever its data"
}

pub fn item_stat_kind_gives_unread_the_number_of_any_other_kind_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([3, 5, 6, 255, -1], fn(kind_number) {
    assert item_stat_kind.kind_of(kind_number:, data:) == Unread(kind_number)
      as "0x14040ca70: any kind other than 0, 1, 2 and 4 fails with 0x70, so no rule reads it"
  })
}

pub fn item_stat_kind_number_of_gives_back_the_kind_it_was_decoded_from_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([0, 1, 2, 3, 4, 9], fn(kind_number) {
    assert item_stat_kind.number_of(item_stat_kind.kind_of(kind_number:, data:))
      == kind_number
      as "the kind number of the table cell is the decode's number"
  })
}

pub fn item_stat_kind_accessors_answer_for_their_own_kind_only_test() -> Nil {
  use <- owned_test.run(10_000)
  let kinds =
    list.map([0, 1, 2, 3, 4], fn(kind_number) {
      item_stat_kind.kind_of(kind_number:, data:)
    })
  assert list.map(kinds, item_stat_kind.property_of)
    == [
      Error(Nil),
      Ok(UnitProperty2Id(data)),
      Error(Nil),
      Error(Nil),
      Error(Nil),
    ]
    as "only kind 1 names a UnitProperty2 row"
  assert list.map(kinds, item_stat_kind.random_group_of)
    == [
      Error(Nil),
      Error(Nil),
      Ok(ItemRandomStatGroupId(data)),
      Error(Nil),
      Error(Nil),
    ]
    as "only kind 2 names an ItemRandomStatGroup"
  assert list.map(kinds, item_stat_kind.is_crafting_socket)
    == [False, False, False, False, True]
    as "only kind 4 is a crafting entry"
}

pub fn item_stat_kind_reads_every_cell_and_row_of_the_real_tables_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let stats = item_stat.all(tables)
  assert list.length(stats) == 454 as "ItemStat.tbl holds 454 rows"
  let cells = list.flat_map(stats, item_stat_kind.of_stat)
  assert list.length(cells) == 454 * 5 as "each row has five entries"
  assert list.filter(cells, fn(kind) {
      case kind {
        Unread(_) -> True
        NoStat | Property(_) | RandomGroup(_) | CraftingSocket -> False
      }
    })
    == []
    as "every ItemStat cell is a kind the builder reads: 0, 1, 2 or 4"
  let random_rows = item_random_stat.all(tables)
  assert list.length(random_rows) == 52 as "ItemRandomStat.tbl holds 52 rows"
  list.each(random_rows, fn(row) {
    assert item_stat_kind.of_random_row(row)
      == Property(UnitProperty2Id(row.item_stat_data))
      as "every ItemRandomStat row is a property"
  })
}
