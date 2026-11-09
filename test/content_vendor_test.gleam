//// The vendor content tables (`vendor` and `vendor_item`, migration 0023) through the
//// content load, run on databases of the test's own. Expected values come from these
//// places.
//// - The seven vendors and their 150 stock rows are Jabbithole's npc pages (version
////   "launch", Sells tab), the one record of vendor stock: the client's tables hold none
////   (`vendor.stock_gap`). The counts are the committed rows'; Supplier Ingavak
////   (Creature2 28739) sells the 22 items of list A in the order its page gives them.
//// - A row the client's tables lack stops the load, naming the table, the row and the
////   rule: AddVendorItem drops an item whose Item2 row is missing (`0x14047aba0`), and
////   CLAUDE.md fails the load on a missing row.

import content_support
import database_support
import genesis_prime/content
import genesis_prime/content/refusal.{Refusal}
import genesis_prime/content/vendor as content_vendor
import genesis_prime/game/vendor
import genesis_prime/table/id.{Item2Id}
import gleam/list
import owned_test
import vendor_support

pub fn the_load_puts_each_vendors_stock_in_its_term_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil) as "a migrated database loads"
  let vendors = content_vendor.vendors(key:)
  let creatures = vendor.creatures(vendors:)
  assert list.length(creatures) == 7 as "seven creatures sell"
  let assert Ok(ingavak) =
    vendor.get(vendors:, creature_id: id.Creature2Id(28_739))
    as "Supplier Ingavak sells"
  assert list.length(ingavak.items) == 22
  assert list.map(ingavak.items, fn(stocked) {
      let Item2Id(item) = stocked.item_id
      #(stocked.position, item)
    })
    == list.index_map(vendor_support.ingavaks_items, fn(item, index) {
      #(index + 1, item)
    })
    as "list A, each item at its place on the page"
  let stocked =
    list.fold(creatures, 0, fn(total, creature_id) {
      let assert Ok(each) = vendor.get(vendors:, creature_id:)
      total + list.length(each.items)
    })
  assert stocked == 150 as "the seven pages' rows: 21, 21, 22, 21, 22, 22, 21"
}

pub fn a_vendor_row_the_tables_refuse_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "insert into vendor (creature_id, source, reason) values (200001, 'server_choice', 'a creature the client does not hold')",
  )
  content_support.change(
    database:,
    sql: "insert into vendor_item (creature_id, position, item_id, source, reason) values (28739, 23, 4000000, 'server_choice', 'an item the client does not hold')",
  )
  let #(loaded, _key) = content_support.load(database:)
  let assert Error(content.Refused(refusals:)) = loaded
    as "a row the tables refuse stops the start"
  assert refusals
    == [
      Refusal(
        table: "vendor",
        row: refusal.RowId(200_001),
        rule: "Creature2 200001 has no row in the client's table",
      ),
      Refusal(
        table: "vendor_item",
        row: refusal.RowName("28739/23"),
        rule: "Item2 4000000 has no row in the client's table",
      ),
    ]
    as "each refused row is named by its table and row, with the rule"
}
