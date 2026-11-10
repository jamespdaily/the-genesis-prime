//// What a vendor charges for an item, held in the stock when the vendor content loads
//// (`genesis_prime/game/vendor.select`, `genesis_prime/game/item_price`). Expected values
//// come from these places.
//// - `vendor.start_zone_prices`: with the vendor multiplier 1.0 the client shows 20, 67,
////   13 and 30 for Item2 12078, 14838, 20791 and 12044, and 525, 328, 281, 421 and 468
////   for the armor pieces (BuildItemPrices 0x14040d160 over the client's rows, in 32-bit
////   floats). Retail says 104 for 14838; the client shows what the multiplier makes.
//// - `0x14040bee0` (ItemVendorBuyPrice): the price is at least 1 credit. `0x14047aba0` and
////   `0x14041bf80`: the window's price is the buy price times the vendor's buy multiplier,
////   cut to a whole credit.
//// - `0x14040d160`: only an Item2 row whose currencyTypeId0 and currencyTypeId1 are both 0 is
////   priced in credits. `0x140243a00`, `0x1405e6230`: a row with a tradeskillAdditiveId is
////   priced with a bonus factor that is not built here.

import character_tables
import client_tables
import fixture_tables
import genesis_prime/content/refusal.{Refusal, RowName}
import genesis_prime/game/item_price
import genesis_prime/game/item_property
import genesis_prime/game/vendor.{ItemRow, VendorRow}
import genesis_prime/table/id.{Item2Id}
import genesis_prime/table/item2
import gleam/list
import owned_test
import planted_table.{Integer}
import unitest
import vendor_support

/// The stock of Supplier Ingavak, priced by the vendor's rows over the committed tables:
/// each item with the price the stock holds.
fn priced(
  items items: List(Int),
  buy_multiplier buy_multiplier: Float,
) -> List(#(Int, Int)) {
  let assert Ok(vendors) =
    vendor.select(
      vendors: [VendorRow(28_739, buy_multiplier, 1.0)],
      items: list.index_map(items, fn(item, index) {
        ItemRow(28_739, index + 1, item)
      }),
      tables: character_tables.shared(),
    )
    as "the committed rows hold these items"
  let assert Ok(ingavak) =
    vendor.get(vendors:, creature_id: id.Creature2Id(28_739))
    as "the vendor row is the one selected"
  list.map(ingavak.items, fn(stocked) {
    let Item2Id(item) = stocked.item_id
    #(item, stocked.price)
  })
}

pub fn the_buy_price_of_each_stocked_item_is_the_price_the_client_shows_test() -> Nil {
  use <- owned_test.run(60_000)
  assert priced(items: vendor_support.ingavaks_items, buy_multiplier: 1.0)
    == [
      #(12_078, 20),
      #(14_838, 67),
      #(20_791, 13),
      #(13_176, 525),
      #(13_185, 525),
      #(13_194, 525),
      #(13_188, 525),
      #(12_044, 30),
      #(13_191, 525),
      #(13_179, 525),
      #(13_151, 328),
      #(13_154, 281),
      #(13_166, 281),
      #(27_874, 421),
      #(27_873, 468),
      #(27_876, 281),
      #(13_157, 421),
      #(13_163, 328),
      #(27_875, 328),
      #(13_169, 421),
      #(13_148, 468),
      #(13_160, 468),
    ]
    as "vendor.start_zone_prices: the 22 stocked items at multiplier 1.0, in the order of the page"
}

/// What a vendor pays for each item at the sell multiplier 1.0, over the committed tables.
fn sell_bases(items items: List(Int)) -> List(#(Int, Int)) {
  list.map(items, fn(item) {
    let assert Ok(item_price.SellPrice(currency_type_id: 1, amount:)) =
      item_price.sell_price(
        tables: character_tables.shared(),
        item2_id: Item2Id(item),
      )
      as "the committed rows hold these items and price them in credits"
    #(item, amount)
  })
}

pub fn the_sell_base_of_each_start_zone_item_is_the_price_the_client_shows_test() -> Nil {
  use <- owned_test.run(60_000)
  assert sell_bases(items: vendor_support.ingavaks_items)
    == [
      #(12_078, 3),
      #(14_838, 10),
      #(20_791, 1),
      #(13_176, 78),
      #(13_185, 78),
      #(13_194, 78),
      #(13_188, 78),
      #(12_044, 4),
      #(13_191, 78),
      #(13_179, 78),
      #(13_151, 49),
      #(13_154, 42),
      #(13_166, 42),
      #(27_874, 63),
      #(27_873, 70),
      #(27_876, 42),
      #(13_157, 63),
      #(13_163, 49),
      #(27_875, 49),
      #(13_169, 63),
      #(13_148, 70),
      #(13_160, 70),
    ]
    as "vendor.start_zone_prices: the sell base BuildItemPrices computes for the 22 stocked items, in the order of the page (12078 3, 14838 10, 20791 1, 12044 4; armor 78, 49, 42, 63, 70); the client then clears the sell price of 12078 to 0 (0x14040d160.sell_cleared), so 3 is never shown for it"
}

pub fn the_sell_multiplier_scales_the_shown_price_and_cuts_it_to_a_whole_credit_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert [#(13_176, base)] = sell_bases(items: [13_176])
  assert base == 78 as "vendor.start_zone_prices: 13176 sells for 78"
  assert item_price.shown(base:, multiplier: 1.0) == 78
    as "0x14041bcc0.formula: a multiplier of 1.0 shows the base"
  assert item_price.shown(base:, multiplier: 1.55) == 120
    as "0x14041bcc0.formula: trunc(f32(78) x f32(1.55)) = 120.9 cut to 120"
}

pub fn a_sell_to_vendor_credit_amount_replaces_the_computed_price_test() -> Nil {
  use <- owned_test.run(10_000)
  let item = fixture_tables.root("Item2", 11_538)
  assert sell_bases(items: [item]) == [#(11_538, 1)]
    as "0x14040d160: Item2 11538 has sell currency type 1 (credits) and amount 1, which is its price, though its buy columns name another currency"
  let planted = {
    use tables <- fixture_tables.changed(table: "Item2", id: item, with: [
      #("currencyAmount0SellToVendor", Integer(7)),
    ])
    item_price.sell_price(tables:, item2_id: Item2Id(item))
  }
  assert planted == Ok(item_price.SellPrice(currency_type_id: 1, amount: 7))
    as "0x14040d160: with a sell currency type set the amount column is the price, not the computed 0.15 of the buy price"
  assert item_price.shown(base: 1, multiplier: 2.5) == 2
    as "0x14041bcc0.formula: trunc(f32(1) x f32(2.5)) = 2"
}

pub fn a_sell_currency_set_with_an_amount_of_0_sells_for_nothing_whatever_the_computed_price_is_test() -> Nil {
  use <- owned_test.run(10_000)
  let item = fixture_tables.root("Item2", 1154)
  assert sell_bases(items: [item]) == [#(1154, 0)]
    as "0x14040d160 (sell branch tests currencyTypeId0SellToVendor and currencyTypeId1SellToVendor, offsets 0x98 and 0x9c): Item2 1154 has sell currency type 1 and amount 0, so its price is the amount, 0, and not the 3 that 0.15 of its computed buy price 21 would give; its buy columns are 0 and 0"
}

pub fn a_row_with_a_buy_currency_and_no_sell_currency_sells_for_the_computed_price_test() -> Nil {
  use <- owned_test.run(10_000)
  let item = fixture_tables.root("Item2", 85_531)
  assert sell_bases(items: [item]) == [#(85_531, 5625)]
    as "0x14040d160 (both sell currency types 0, so 0x14040bfb0): Item2 85531 sells for max(1, trunc(f32(37 500) x f32(0.15))) = 5625, 37 500 being its computed buy price (level 50: 7.5 x 50^2 = 18 750, times quality 4, times 0.5); its own buy price of 250 000 credits in currencyAmount0 is not read"
}

pub fn a_tradeskill_additive_changes_the_buy_price_only_not_the_computed_sell_price_test() -> Nil {
  use <- owned_test.run(10_000)
  let item = fixture_tables.root("Item2", 23_318)
  assert sell_bases(items: [item]) == [#(23_318, 37)]
    as "0x14040d160 (both sell currency types 0): Item2 23318 has tradeskillAdditiveId 95 and sells for max(1, trunc(f32(248) x f32(0.15))) = 37, 248 being its computed buy price (level 47: 7.5 x 47^2 = 16 567.5, times quality 3, times 0.005); the additive reaches only Item GetBuyPrice (0x14041bf80)"
}

pub fn a_proxy_item_takes_its_quality_from_the_proxy_row_test() -> Nil {
  use <- owned_test.run(60_000)
  assert priced(items: [12_078], buy_multiplier: 1.0) == [#(12_078, 20)]
    as "0x1404445d0.proxy: Item2 12078 holds flag 0x4000, so its quality is Item2 74201's (2) and its power level its own; vendor.start_zone_prices shows 20"
}

pub fn the_vendor_multiplier_scales_the_price_and_cuts_it_to_a_whole_credit_test() -> Nil {
  use <- owned_test.run(60_000)
  assert priced(items: [14_838], buy_multiplier: 1.55) == [#(14_838, 103)]
    as "0x14047aba0: 67 x 1.55 in 32-bit floats is 103.85, shown as 103"
}

pub fn every_credit_priced_item2_row_costs_at_least_one_credit_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let credit_priced =
    list.filter(item2.all(tables), fn(row) {
      row.currency_type_id0 == 0
      && row.currency_type_id1 == 0
      && row.tradeskill_additive_id == 0
    })
  assert credit_priced != [] as "the client's Item2 holds credit-priced rows"
  let cheaper =
    list.filter_map(credit_priced, fn(row) {
      case item_price.base(tables:, item2_id: Item2Id(row.id)) {
        Ok(price) if price >= 1 -> Error(Nil)
        other -> Ok(#(row.id, other))
      }
    })
  assert cheaper == []
    as "0x14040bee0: the buy price is max(1, ...), so no credit-priced row is free or has no price"
}

pub fn a_stock_row_priced_in_another_currency_stops_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  // Synthetic: the client's Item2 14838 has currencyTypeId0 0 (a credit price).
  let selected = {
    use tables <- fixture_tables.changed(table: "Item2", id: 14_838, with: [
      #("currencyTypeId0", Integer(1)),
    ])
    vendor.select(
      vendors: [VendorRow(28_739, 1.0, 1.0)],
      items: [ItemRow(28_739, 2, 14_838)],
      tables:,
    )
  }
  assert selected
    == Error([
      Refusal(
        table: "vendor_item",
        row: RowName("28739/2"),
        rule: "Item2 14838 is priced in a currency other than credits, which #333 builds",
      ),
    ])
    as "0x14040d160: only both currency ids 0 give the computed credit price; paying another currency is a later step"
}

pub fn a_stock_row_with_a_tradeskill_additive_stops_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  // Synthetic: the client's Item2 14838 has tradeskillAdditiveId 0.
  let selected = {
    use tables <- fixture_tables.changed(table: "Item2", id: 14_838, with: [
      #("tradeskillAdditiveId", Integer(1)),
    ])
    vendor.select(
      vendors: [VendorRow(28_739, 1.0, 1.0)],
      items: [ItemRow(28_739, 2, 14_838)],
      tables:,
    )
  }
  assert selected
    == Error([
      Refusal(
        table: "vendor_item",
        row: RowName("28739/2"),
        rule: "Item2 14838 has tradeskill additive 1, whose price bonus #333 builds",
      ),
    ])
    as "0x140243a00, 0x1405e6230: a row with a tradeskillAdditiveId is priced with a bonus factor in place of the vendor multiplier, which is not built here"
}

pub fn a_stock_row_whose_item_holds_a_buy_lot_of_0_stops_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  // Synthetic: the client's Item2 14838 has buyFromVendorStackCount 1, and none of the 22
  // stocked items holds 0 (the Item2 column; 0x14047aba0 copies it as it stands).
  let selected = {
    use tables <- fixture_tables.changed(table: "Item2", id: 14_838, with: [
      #("buyFromVendorStackCount", Integer(0)),
    ])
    vendor.select(
      vendors: [VendorRow(28_739, 1.0, 1.0)],
      items: [ItemRow(28_739, 2, 14_838)],
      tables:,
    )
  }
  assert selected
    == Error([
      Refusal(
        table: "vendor_item",
        row: RowName("28739/2"),
        rule: "Item2 14838 holds a buy lot of 0, which would sell no items (opcode.0xbe, 0x14047aba0 copies the lot as it stands)",
      ),
    ])
    as "a lot of 0 would charge nothing and give nothing, so a stocked row of 0 is a missing-data failure at start"
}

pub fn an_item_priced_in_another_currency_sells_for_its_row_amount_in_that_currency_unscaled_test() -> Nil {
  use <- owned_test.run(10_000)
  let item = fixture_tables.root("Item2", 16_053)
  let assert Ok(price) =
    item_price.sell_price(
      tables: character_tables.shared(),
      item2_id: Item2Id(item),
    )
    as "the committed rows hold Item2 16053"
  assert price == item_price.SellPrice(currency_type_id: 7, amount: 60)
    as "0x14040d160: Item2 16053's currencyTypeId0SellToVendor is 7 (Glory) and currencyAmount0SellToVendor 60, which is its price in that currency"
  assert item_price.paid(price:, multiplier: 1.55) == price
    as "0x14041bcc0.formula: only a credit slot is scaled by the vendor's sell multiplier; another currency's amount is paid as the row gives it"
  assert item_price.paid(
      price: item_price.SellPrice(currency_type_id: 1, amount: 10),
      multiplier: 1.55,
    )
    == item_price.SellPrice(currency_type_id: 1, amount: 15)
    as "0x14041bcc0.formula: a credit slot pays trunc(f32(10) x f32(1.55)) = 15"
}

pub fn a_row_with_amounts_in_both_sell_slots_is_refused_by_name_test() -> Nil {
  use <- owned_test.run(10_000)
  // Synthetic: no row of the client has an amount in both slots
  // (`every_sellable_item2_row_names_its_sell_price_in_at_most_one_currency_test`).
  let item = fixture_tables.root("Item2", 16_053)
  let priced = {
    use tables <- fixture_tables.changed(table: "Item2", id: item, with: [
      #("currencyTypeId1SellToVendor", Integer(1)),
      #("currencyAmount1SellToVendor", Integer(5)),
    ])
    item_price.sell_price(tables:, item2_id: Item2Id(item))
  }
  assert priced == Error(item_price.TwoSellCurrencies(item2_id: Item2Id(item)))
    as "0x14040d160 reads one currency slot's price; a row with an amount in both has no one price, so the error names the item"
  let assert Error(error) = priced
  assert item_price.describe(error:)
    == "Item2 16053 has an amount in both sell currency slots"
    as "the sentence names the Item2 row"
}

/// The client's Item2 rows, each with its two SellToVendor slots as (currency type, amount).
fn sell_slots() -> List(#(item2.Item2, #(Int, Int), #(Int, Int))) {
  list.map(item2.all(client_tables.shared()), fn(row) {
    #(
      row,
      #(
        row.currency_type_id0_sell_to_vendor,
        row.currency_amount0_sell_to_vendor,
      ),
      #(
        row.currency_type_id1_sell_to_vendor,
        row.currency_amount1_sell_to_vendor,
      ),
    )
  })
}

pub fn every_sellable_item2_row_names_its_sell_price_in_at_most_one_currency_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let both =
    list.filter_map(sell_slots(), fn(slots) {
      let #(row, #(first_type, first), #(second_type, second)) = slots
      case first_type != 0 && first > 0 && second_type != 0 && second > 0 {
        True -> Ok(row.id)
        False -> Error(Nil)
      }
    })
  assert both == []
    as "0x14040d160 reads one SellToVendor slot: no row of the client holds an amount in both, so sell_price names one currency"
  let refused =
    list.filter_map(item2.all(tables), fn(row) {
      case item_price.sell_price(tables:, item2_id: Item2Id(row.id)) {
        Ok(_) -> Error(Nil)
        Error(error) -> Ok(#(row.id, error))
      }
    })
  assert refused == []
    as "every row of the client has a sell price: the sell price reads no column that can be missing"
}

pub fn every_junk_item2_row_sells_for_credits_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let junk =
    list.filter(item2.all(tables), fn(row) {
      row.item2_category_id == junk_category
      && item_property.sellable(tables:, item2_id: row.id) == Ok(True)
    })
  assert junk != [] as "the client's Item2 holds junk that sells"
  let elsewhere =
    list.filter_map(junk, fn(row) {
      case item_price.sell_price(tables:, item2_id: Item2Id(row.id)) {
        Ok(item_price.SellPrice(currency_type_id: 1, ..)) -> Error(Nil)
        other -> Ok(#(row.id, other))
      }
    })
  assert elsewhere == []
    as "lua.Item.CodeEnumItem2Category (Junk is 94), Vendor.lua l.520 to 537: sell junk is paid in credits, so every junk row that sells must have a credit price"
}

/// Item2Category 94, Junk (`lua.Item.CodeEnumItem2Category`).
const junk_category = 94

pub fn every_currency_an_item2_row_sells_for_is_one_the_client_keeps_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let outside =
    list.filter_map(sell_slots(), fn(slots) {
      let #(row, #(first_type, _), #(second_type, _)) = slots
      let kept = fn(currency_type_id) {
        currency_type_id == 0
        || { currency_type_id >= 1 && currency_type_id <= 14 }
      }
      case kept(first_type) && kept(second_type) {
        True -> Error(Nil)
        False -> Ok(#(row.id, first_type, second_type))
      }
    })
  assert outside == []
    as "opcode.0x25e holds the amounts of types 1 to 15 and opcode.0x919 drops kinds 14 and over (types 15 and over), so a row sold for another type could not be shown or kept"
}
