//// The player's sale to the open vendor (`genesis_prime/game/vendor_sale`): the client's
//// 0x0166 and 0x0167 taken against the held items and credits, and the store's answer to
//// the sale it asked for. Expected values come from these places.
//// - `opcode.0x166` and `0x1403d6a10` (CheckItemSellable): the body is the item's place
////   (location, bag index) and a quantity; the client's own checks give the codes
////   (`GameLib.CodeEnumGenericError`): 24 Vendor_NoQuantity, 19 a quantity over the count
////   (a held count of 0 reads as 1), 11 Vendor_StackSize for more than one of an item that
////   does not stack, 25 Vendor_BagIsNotEmpty for a bag at location 0, 23 for the bank
////   (locations 2 and 3) and for an item the vendor will not buy; the sender sends nothing
////   for a dead player (2 PlayerBusy), for no vendor interaction (16) or for a dead vendor
////   (23), and range checks the vendor with 6.0 between the two edges (17 Vendor_TooFar).
//// - `0x14040d160.sell_cleared`, `0x14040bfb0`: an item sells for max(1, trunc(buy price x
////   GameFormula 1026's 0.15)) in 32-bit floats, or for its own SellToVendor credit amount;
////   `0x14041bcc0.formula`: the vendor pays the base times its sell multiplier, cut to a
////   whole credit, for each item. The bases here are those of `item_price_test`: 14838 10,
////   20791 1, 13176 78, 4753 42, 175, 176 and 177 1 each, and 0 for 1154 and 74201.
//// - `0x1403d6a10`, `item.bags_sellable`: a bag in the bags sells whatever it holds.
//// - `lua.Item.CodeEnumItem2Category` (Junk is 94), `opcode.0x167`, Vendor.lua l.520 to 537:
////   sell junk sells every junk stack that sells, whole.
//// - `GetCurrencyCap.entitlement_14`: the credits cap is GameFormula 1115's dataint0, 500,000.
//// - `opcode.0x919`, `Item.CodeEnumItemUpdateReason` (7 Vendor makes the client show
////   "Sold <item>"), `opcode.0xba.price`: the answer is a 0x919 of kind 0 with the new
////   total, then for each stack a 0x148 (whole) or 0x17F (part) and a 0xBA that adds the
////   entry to the Buyback list, its amount the credits paid and its currency type 1.
//// - `opcode.0xba.random_stats`: the entry's five multipliers (fields 9 to 13) are the float
////   1.0, 0x3f800000, so a fixed-budget stat keeps its value (`entry`, `entry_in`).
//// - Where the server chooses: which 0x106 the server's own checks of a stale client give
////   (16, 2, 59, 62 and 18), and the logs.

import character_tables
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/client_connection
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/currency.{type Currencies}
import genesis_prime/game/interaction.{Player}
import genesis_prime/game/player_life.{type Life}
import genesis_prime/game/shown
import genesis_prime/game/vendor
import genesis_prime/game/vendor_sale.{
  type Taken, Asks, Refused, Sale, SellJunk, SellStack, SoldItem,
}
import genesis_prime/game/vendor_trade.{
  type Effect, Log, NotDecoded, Refuse, Send,
}
import genesis_prime/game/world_entry.{Buyback, BuybackEntry}
import genesis_prime/message/buyback_added
import genesis_prime/message/buyback_entry
import genesis_prime/message/currency_changed.{CurrencyChanged}
import genesis_prime/message/item_count_changed.{ItemCountChanged}
import genesis_prime/message/item_place.{ItemPlace}
import genesis_prime/message/item_removed.{ItemRemoved}
import genesis_prime/message/vendor_sale as vendor_sale_message
import genesis_prime/message/vendor_sell_junk
import genesis_prime/step.{LogDebug, LogError, LogWarning}
import genesis_prime/store.{type HeldItem, HeldItem}
import genesis_prime/table/game_formula
import genesis_prime/table/id.{Item2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/creature_life.{type Hostile, Hostile}
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set
import gleam/string
import owned_test
import planted_table.{Integer}
import player_life_support
import vendor_support

/// Dorian Walker's vendor window, open on his unit.
fn walkers_window() -> Option(vendor.Opened) {
  let assert Ok(walkers) =
    vendor.get(
      vendors: vendor_support.stocking(creature_ids: [74_812]),
      creature_id: id.Creature2Id(74_812),
    )
    as "the vendors of the test hold Dorian Walker"
  Some(vendor.Opened(unit_id: vendor_support.walker_unit, vendor: walkers))
}

/// The vendors of Dorian Walker with a sell multiplier of `multiplier`.
fn paying(multiplier multiplier: Float) -> vendor.Vendors {
  let assert Ok(vendors) =
    vendor.select(
      vendors: [vendor.VendorRow(74_812, 1.0, multiplier)],
      items: [vendor.ItemRow(74_812, 1, 12_078)],
      tables: character_tables.shared(),
    )
    as "Dorian Walker and Item2 12078 are rows of the client's committed tables"
  vendors
}

fn stack_body(
  location location: Int,
  bag_index bag_index: Int,
  quantity quantity: Int,
) -> BitArray {
  let assert Ok(body) =
    vendor_sale_message.encode(vendor_sale_message.VendorSale(
      place: ItemPlace(location:, bag_index:),
      quantity:,
    ))
    as "a place and a quantity of 32 bits fit the message"
  body
}

fn junk_body() -> BitArray {
  let assert Ok(body) = vendor_sell_junk.encode(vendor_sell_junk.VendorSellJunk)
    as "the message has no field to refuse"
  body
}

fn credits(total total: Int) -> Currencies {
  currency.with_amount(
    currencies: currency.from_held(held: []),
    currency_type_id: currency.credits_type,
    total:,
  )
}

/// A stack of Item2 `item2_id` at a place.
fn held(
  guid guid: Int,
  item2_id item2_id: Int,
  location location: Int,
  index index: Int,
  count count: Int,
) -> HeldItem {
  HeldItem(
    item_guid: guid,
    item2_id: Item2Id(item2_id),
    location:,
    bag_index: index,
    stack_count: count,
    random_stats: 0,
  )
}

/// A stack of Item2 `item2_id` in the inventory.
fn in_bag(
  guid guid: Int,
  item2_id item2_id: Int,
  index index: Int,
  count count: Int,
) -> HeldItem {
  held(guid:, item2_id:, location: 1, index:, count:)
}

/// Everything a sale reads, at the open window, the walker in reach and the player alive;
/// each test changes what it is about.
type Scene {
  Scene(
    request: vendor_sale.Request,
    items: List(HeldItem),
    credits: Currencies,
    opened: Option(vendor.Opened),
    life: Life,
    picture: shown.Picture,
    vendors: vendor.Vendors,
    logged: set.Set(String),
    tables: table_store.Tables,
  )
}

/// A sale of `quantity` of the stack at a place, with nothing held.
fn selling(
  location location: Int,
  index index: Int,
  quantity quantity: Int,
) -> Scene {
  Scene(
    request: SellStack(body: stack_body(location:, bag_index: index, quantity:)),
    items: [],
    credits: credits(total: 100),
    opened: walkers_window(),
    life: player_life_support.alive(),
    picture: vendor_support.picture_with_walker(gap: 1.0),
    vendors: vendor_support.stocking(creature_ids: [74_812]),
    logged: set.new(),
    tables: character_tables.shared(),
  )
}

/// A sale of `quantity` of the stack at inventory slot `index`, which `items` hold.
fn sell(
  items items: List(HeldItem),
  index index: Int,
  quantity quantity: Int,
) -> Scene {
  Scene(..selling(location: 1, index:, quantity:), items:)
}

/// A sale of all junk, which `items` hold.
fn selling_junk(items items: List(HeldItem)) -> Scene {
  Scene(
    ..selling(location: 1, index: 0, quantity: 1),
    request: SellJunk(body: junk_body()),
    items:,
  )
}

fn taken(scene scene: Scene) -> Result(Taken, vendor_trade.Refusal) {
  vendor_sale.take(
    request: scene.request,
    items: scene.items,
    currencies: scene.credits,
    opened: scene.opened,
    life: scene.life,
    player: Player(
      race_id: id.RaceId(1),
      faction: shown.Dominion,
      place: connection_support.entry_place(),
    ),
    picture: scene.picture,
    tables: scene.tables,
    vendors: scene.vendors,
    now_ms: 0,
    logged: scene.logged,
  )
}

/// The sale a message asks the store for, which the rule must have accepted.
fn asked(scene scene: Scene) -> vendor_sale.Sale {
  let assert Ok(Asks(sale:, ..)) = taken(scene:)
    as "the sale passes every check, so the store is asked"
  sale
}

/// The effects of a sale the rule refused.
fn refused(scene scene: Scene) -> List(Effect) {
  let assert Ok(Refused(effects:, ..)) = taken(scene:)
    as "the sale breaks a check, so it is answered and nothing is asked"
  effects
}

/// The codes of the 0x106s among the effects.
fn codes(effects effects: List(Effect)) -> List(Int) {
  list.filter_map(effects, fn(effect) {
    case effect {
      Refuse(code:) -> Ok(code)
      Send(..) | Log(..) -> Error(Nil)
    }
  })
}

/// The level and text of the one log line and the code of the one 0x106 among the effects
/// of a refusal that is logged.
fn logged_code(effects effects: List(Effect)) -> #(step.LogLevel, Int) {
  let #(level, code, _) = logged_text(effects:)
  #(level, code)
}

fn logged_text(effects effects: List(Effect)) -> #(step.LogLevel, Int, String) {
  let assert [Log(level:, text:), Refuse(code:)] = effects
    as "a logged refusal is a log line, then the 0x106"
  #(level, code, text)
}

/// The frames among the effects.
fn frames(effects effects: List(Effect)) -> List(Frame) {
  list.filter_map(effects, fn(effect) {
    case effect {
      Send(frame:) -> Ok(frame)
      Log(..) | Refuse(..) -> Error(Nil)
    }
  })
}

/// The 0xBA entry the client reads for a sale of `quantity` of an item for `paid` credits:
/// the five multipliers are 1.0 (`opcode.0xba.random_stats`) and every other field the
/// client's code gives no use is 0.
fn entry(
  buyback_id buyback_id: Int,
  item_id item_id: Int,
  quantity quantity: Int,
  paid paid: Int,
) -> buyback_entry.BuybackEntry {
  entry_in(
    buyback_id:,
    item_id:,
    quantity:,
    paid:,
    currency_type: currency.credits_type,
  )
}

/// The 0xBA entry for a sale of `quantity` of an item for `paid` of the currency type
/// `currency_type`.
fn entry_in(
  buyback_id buyback_id: Int,
  item_id item_id: Int,
  quantity quantity: Int,
  paid paid: Int,
  currency_type currency_type: Int,
) -> buyback_entry.BuybackEntry {
  buyback_entry.BuybackEntry(
    buyback_id:,
    item_id:,
    quantity:,
    random_stats: 0,
    field_5: 0,
    field_6: 0,
    field_7: 0,
    field_8: 0,
    multiplier_1: 0x3f800000,
    multiplier_2: 0x3f800000,
    multiplier_3: 0x3f800000,
    multiplier_4: 0x3f800000,
    multiplier_5: 0x3f800000,
    field_14: 0,
    field_15: 0,
    field_16: 0,
    field_17: 0,
    field_18: 0,
    field_19: 0,
    field_20: 0,
    field_21: 0,
    amount_1: paid,
    amount_2: 0,
    currency_type_1: currency_type,
    currency_type_2: 0,
    field_26: 0,
  )
}

/// Dorian Walker's window, open on the unit `unit_id`.
fn window_on(unit_id unit_id: Int) -> Option(vendor.Opened) {
  let assert Some(vendor.Opened(vendor: walkers, ..)) = walkers_window()
    as "the window of the test is open"
  Some(vendor.Opened(unit_id:, vendor: walkers))
}

/// The picture of `vendor_support` with the walker's life and hostility changed.
fn walker_with(
  alive alive: Bool,
  hostile_to hostile_to: Hostile,
) -> shown.Picture {
  let picture = vendor_support.picture_with_walker(gap: 1.0)
  let assert Ok(shown.ShownCreature(..) as creature) =
    dict.get(picture, vendor_support.walker_unit)
    as "the picture holds the walker"
  dict.insert(
    picture,
    vendor_support.walker_unit,
    shown.ShownCreature(..creature, alive:, hostile_to:),
  )
}

/// A 0x919, which must set credits to `total`.
fn assert_total(frame frame: Frame, total total: Int) -> Nil {
  assert_total_of(frame:, kind: 0, total:)
}

/// A 0x919 of this kind (the currency type - 1), which must set that currency to `total`.
fn assert_total_of(
  frame frame: Frame,
  kind kind: Int,
  total total: Int,
) -> Nil {
  assert frame.message_id == currency_changed.message_id
  assert currency_changed.decode(frame.body)
    == Ok(CurrencyChanged(kind:, total:, field_3: 0, field_4: 0))
    as "opcode.0x919: the kind is the currency type - 1, it sets that currency to the new total, and the two 32-bit values are 0"
}

/// A 0x148 that takes the stack away with the reason Vendor.
fn assert_removed(frame frame: Frame, guid guid: Int) -> Nil {
  assert frame.message_id == item_removed.message_id
  assert item_removed.decode(frame.body)
    == Ok(ItemRemoved(item_guid: guid, reason: 7))
    as "Item.CodeEnumItemUpdateReason: Vendor is 7, which shows 'Sold <item>'"
}

/// A 0xBA that adds the entry to the Buyback list.
fn assert_entry(
  frame frame: Frame,
  entry entry: buyback_entry.BuybackEntry,
) -> Nil {
  assert frame.message_id == buyback_added.message_id
  assert buyback_added.decode(frame.body)
    == Ok(buyback_added.BuybackAdded(entry:))
    as "opcode.0xba.price: the entry's amount is the credits paid and its currency type 1"
}

pub fn a_buyback_entry_sends_multipliers_of_one_test() -> Nil {
  use <- owned_test.run(10_000)
  let message =
    vendor_sale.buyback_entry_message(entry: BuybackEntry(
      buyback_id: 3,
      item2_id: Item2Id(14_838),
      quantity: 1,
      currency_type_id: currency.credits_type,
      amount: 10,
      random_stats: 0,
    ))
  // `opcode.0xba.random_stats`: the client builds the properties with 5 multipliers read
  // as 32-bit floats, and 0x3f800000 is the float 1.0 (IEEE 754 single precision).
  assert [
      message.multiplier_1,
      message.multiplier_2,
      message.multiplier_3,
      message.multiplier_4,
      message.multiplier_5,
    ]
    == [0x3f800000, 0x3f800000, 0x3f800000, 0x3f800000, 0x3f800000]
    as "fields 9 to 13 are the five multipliers, 1.0 so a fixed stat keeps its full value"
}

pub fn selling_a_whole_stack_removes_it_pays_the_shown_price_and_adds_a_buyback_entry_test() -> Nil {
  use <- owned_test.run(10_000)
  // Item2 14838 sells for 10 at the multiplier 1.0 (`item_price_test`); a vendor with the
  // sell multiplier 1.55 pays trunc(10 x 1.55) = 15 for each, so the stack of 7 pays 105.
  let items = [in_bag(guid: 11, item2_id: 14_838, index: 2, count: 7)]
  let scene =
    Scene(
      ..sell(items:, index: 2, quantity: 7),
      vendors: paying(multiplier: 1.55),
      credits: credits(total: 1000),
    )
  let sale = asked(scene:)
  assert sale
    == Sale(
      unit_id: vendor_support.walker_unit,
      first: SoldItem(
        item_guid: 11,
        item2_id: Item2Id(14_838),
        location: 1,
        held_count: 7,
        sold_count: 7,
        paid: 105,
      ),
      rest: [],
      currency_type_id: 1,
      held: 1000,
      after: 1105,
    )
    as "opcode.0x166: the whole stack for the 15 the vendor pays for each, against the 1000 held"
  let #(left, held_credits, buyback, effects) =
    vendor_sale.answered(
      sale:,
      items:,
      currencies: scene.credits,
      buyback: Buyback(next_id: 3, entries: []),
      answer: store.Sold(amount: 1105, words: [
        store.SoldWord(item_guid: 11, random_stats: 0),
      ]),
    )
  assert left == [] as "the stack is gone"
  assert currency.credits(currencies: held_credits) == 1105
  assert buyback
    == Buyback(next_id: 4, entries: [
      world_entry.BuybackEntry(
        buyback_id: 3,
        item2_id: Item2Id(14_838),
        quantity: 7,
        currency_type_id: 1,
        amount: 105,
        random_stats: 0,
      ),
    ])
    as "the sale is the buyback list's entry 3, the next id 4"
  let assert [total, removed, added] = frames(effects:)
    as "a 0x919, then a 0x148 and a 0xBA for the stack"
  assert_total(frame: total, total: 1105)
  assert_removed(frame: removed, guid: 11)
  assert_entry(
    frame: added,
    entry: entry(buyback_id: 3, item_id: 14_838, quantity: 7, paid: 105),
  )
}

pub fn selling_part_of_a_stack_lowers_its_count_and_pays_for_the_part_sold_test() -> Nil {
  use <- owned_test.run(10_000)
  // Item2 20791 sells for 1 (`item_price_test`): 2 of the 5 held pay 2.
  let items = [in_bag(guid: 12, item2_id: 20_791, index: 0, count: 5)]
  let scene = sell(items:, index: 0, quantity: 2)
  let sale = asked(scene:)
  assert sale
    == Sale(
      unit_id: vendor_support.walker_unit,
      first: SoldItem(
        item_guid: 12,
        item2_id: Item2Id(20_791),
        location: 1,
        held_count: 5,
        sold_count: 2,
        paid: 2,
      ),
      rest: [],
      currency_type_id: 1,
      held: 100,
      after: 102,
    )
    as "opcode.0x166: a quantity below the stack's count is allowed and pays for the part"
  let #(left, held_credits, buyback, effects) =
    vendor_sale.answered(
      sale:,
      items:,
      currencies: scene.credits,
      buyback: Buyback(next_id: 1, entries: []),
      answer: store.Sold(amount: 102, words: [
        store.SoldWord(item_guid: 12, random_stats: 0),
      ]),
    )
  assert left == [in_bag(guid: 12, item2_id: 20_791, index: 0, count: 3)]
    as "the stack keeps the 3 not sold"
  assert currency.credits(currencies: held_credits) == 102
  assert buyback.entries
    == [
      world_entry.BuybackEntry(
        buyback_id: 1,
        item2_id: Item2Id(20_791),
        quantity: 2,
        currency_type_id: 1,
        amount: 2,
        random_stats: 0,
      ),
    ]
    as "lua.Vendor.buyback_price: the entry holds the 2 items sold and the 2 credits"
  let assert [total, lowered, added] = frames(effects:)
    as "a 0x919, then a 0x17F and a 0xBA"
  assert_total(frame: total, total: 102)
  assert lowered.message_id == item_count_changed.message_id
  assert item_count_changed.decode(lowered.body)
    == Ok(ItemCountChanged(item_guid: 12, count: 3, reason: 7))
    as "Item.CodeEnumItemUpdateReason: Vendor is 7; the count is the 3 left"
  assert_entry(
    frame: added,
    entry: entry(buyback_id: 1, item_id: 20_791, quantity: 2, paid: 2),
  )
}

pub fn a_sell_quantity_of_0_is_refused_with_no_quantity_test() -> Nil {
  use <- owned_test.run(10_000)
  let items = [in_bag(guid: 12, item2_id: 20_791, index: 0, count: 5)]
  assert codes(effects: refused(scene: sell(items:, index: 0, quantity: 0)))
    == [24]
    as "enum 24, Vendor_NoQuantity"
}

pub fn a_sell_quantity_over_the_stack_count_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let items = [in_bag(guid: 12, item2_id: 20_791, index: 0, count: 5)]
  assert asked(scene: sell(items:, index: 0, quantity: 5)).first.sold_count == 5
    as "the whole count may be sold"
  assert codes(effects: refused(scene: sell(items:, index: 0, quantity: 6)))
    == [19]
    as "0x1403d6a10: a quantity over the stack's count is enum 19"
  // A held count of 0 reads as 1 (0x1403d6a10).
  let uncounted = [in_bag(guid: 12, item2_id: 20_791, index: 0, count: 0)]
  assert asked(scene: sell(items: uncounted, index: 0, quantity: 1)).first.sold_count
    == 1
    as "a count of 0 reads as 1, so one may be sold"
  assert codes(
      effects: refused(scene: sell(items: uncounted, index: 0, quantity: 2)),
    )
    == [19]
    as "and two may not"
}

pub fn a_sell_of_more_than_one_of_an_item_that_does_not_stack_is_refused_with_stack_size_test() -> Nil {
  use <- owned_test.run(10_000)
  // Item2 13176's joined flags lack 4 (it does not stack: maxStackCount 1); a held count
  // of 3 stands for a row the client would hold only by a changed count.
  let items = [in_bag(guid: 13, item2_id: 13_176, index: 0, count: 3)]
  assert codes(effects: refused(scene: sell(items:, index: 0, quantity: 2)))
    == [11]
    as "0x1403d6a10: more than one of an item that does not stack is enum 11, Vendor_StackSize"
  assert asked(scene: sell(items:, index: 0, quantity: 1)).first.paid == 78
    as "one is sold for the 78 of `item_price_test`"
}

pub fn an_item_with_no_sell_price_is_refused_with_i_wont_buy_that_test() -> Nil {
  use <- owned_test.run(10_000)
  // Item2 9939's joined flags lack 0x20 (`item_property_test`) and 1154's SellToVendor
  // credit amount is 0 (`item_price_test`).
  list.each([9939, 1154], fn(item2_id) {
    let items = [in_bag(guid: 14, item2_id:, index: 0, count: 1)]
    assert codes(effects: refused(scene: sell(items:, index: 0, quantity: 1)))
      == [23]
      as "0x14040d160.sell_cleared and 0x1403d6a10: an item with no sell price is enum 23"
  })
}

pub fn a_worn_bag_is_refused_with_bag_is_not_empty_test() -> Nil {
  use <- owned_test.run(10_000)
  // Item2 4753 is a bag of 4 (`item_property_test`): at location 0 it is worn.
  let worn = [held(guid: 15, item2_id: 4753, location: 0, index: 17, count: 1)]
  let scene = Scene(..selling(location: 0, index: 17, quantity: 1), items: worn)
  assert logged_code(effects: refused(scene:)) == #(LogWarning, 25)
    as "0x1403d6a10: a bag whose location word is 0 is enum 25, Vendor_BagIsNotEmpty, whatever it holds"
  // The same bag in the bags passes to the price: its row sells for 42.
  let carried = [in_bag(guid: 15, item2_id: 4753, index: 3, count: 1)]
  assert asked(scene: sell(items: carried, index: 3, quantity: 1)).first.paid
    == 42
    as "item.bags_sellable: a bag in the bags sells; its sell price is 42"
}

pub fn an_item_in_the_bank_is_refused_and_an_empty_place_is_refused_with_bad_item_rec_test() -> Nil {
  use <- owned_test.run(10_000)
  // 0x1403d6a10: the bank's locations 2 and 3 are enum 23.
  list.each([2, 3], fn(location) {
    let banked = [
      held(guid: 18, item2_id: 14_838, location:, index: 0, count: 4),
    ]
    let scene =
      Scene(..selling(location:, index: 0, quantity: 1), items: banked)
    assert codes(effects: refused(scene:)) == [23]
      as "0x1403d6a10: a bank location is enum 23"
  })
  // The client sends nothing for a place that holds no item, so 18 is the server's choice.
  let items = [in_bag(guid: 19, item2_id: 14_838, index: 0, count: 4)]
  assert logged_code(
      effects: refused(scene: sell(items:, index: 4, quantity: 1)),
    )
    == #(LogWarning, 18)
    as "enum 18, Vendor_BadItemRec: no stack is held at the place"
}

pub fn an_item_failing_two_checks_gets_the_code_of_the_check_the_client_runs_first_test() -> Nil {
  use <- owned_test.run(10_000)
  let far = vendor_support.picture_with_walker(gap: 9.5)
  // 0x1403d3a60 checks the quantity (24) before 0x1403d6a10, whose checks run in the order
  // count 19, stack size 11, bank 23, bag 25, price 23, and the range (17) last.
  let worn_bag = [
    held(guid: 15, item2_id: 4753, location: 0, index: 17, count: 1),
  ]
  let bag_scene = fn(quantity) {
    Scene(
      ..selling(location: 0, index: 17, quantity:),
      items: worn_bag,
      picture: far,
    )
  }
  assert codes(effects: refused(scene: bag_scene(0))) == [24]
    as "a worn bag sold in a quantity of 0 is refused with 24, the quantity check, not 25"
  assert logged_code(effects: refused(scene: bag_scene(1))) == #(LogWarning, 25)
    as "a worn bag with a vendor beyond the window's 9.0 is refused with 25 first: the range comes last"
  assert codes(effects: refused(scene: bag_scene(2))) == [19]
    as "and a quantity over its count of 1 is refused with 19, before the bag check"
  // 13176 does not stack: two of three is 11, and 6 of 3 is 19 first.
  let unstacking = [in_bag(guid: 13, item2_id: 13_176, index: 0, count: 3)]
  let far_sale = fn(items, quantity) {
    Scene(..sell(items:, index: 0, quantity:), picture: far)
  }
  assert codes(effects: refused(scene: far_sale(unstacking, 6))) == [19]
    as "0x1403d6a10: the count check is before the stack-size check"
  assert codes(effects: refused(scene: far_sale(unstacking, 2))) == [11]
    as "and the stack-size check is before the range"
  // An item with no price is 23 from the client's price check, before the range's 17.
  let unpriced = [in_bag(guid: 14, item2_id: 9939, index: 0, count: 1)]
  assert codes(effects: refused(scene: far_sale(unpriced, 1))) == [23]
    as "0x1403d6a10 ends with the price check, which is before the range"
  // The server's own refusals come after all of the client's checks, the range included.
  let worn_item = [
    held(guid: 16, item2_id: 13_176, location: 0, index: 5, count: 1),
  ]
  let worn_scene =
    Scene(
      ..selling(location: 0, index: 5, quantity: 1),
      items: worn_item,
      picture: far,
    )
  assert logged_code(effects: refused(scene: worn_scene)) == #(LogWarning, 17)
    as "a worn item too far from the vendor is refused with the client's 17, not the server's 23"
  let other_currency = [in_bag(guid: 17, item2_id: 16_053, index: 0, count: 1)]
  assert logged_code(effects: refused(scene: far_sale(other_currency, 1)))
    == #(LogWarning, 17)
    as "an item priced in another currency too far from the vendor is refused with 17, not 23"
}

pub fn a_place_at_a_location_the_client_has_no_check_for_is_refused_and_logged_test() -> Nil {
  use <- owned_test.run(10_000)
  // 0x1403d6a10 knows the locations 0 to 3; the server holds items at 0 to 2 only.
  let held_at_5 = [
    held(guid: 20, item2_id: 14_838, location: 5, index: 0, count: 1),
  ]
  let scene =
    Scene(..selling(location: 5, index: 0, quantity: 1), items: held_at_5)
  let assert Ok(Refused(effects:, logged:)) = taken(scene:)
    as "the sale breaks a check"
  let #(level, code, _) = logged_text(effects:)
  assert #(level, code) == #(LogWarning, 23)
    as "a location other than 0 to 3 is enum 23, logged as a gap the first time"
  assert logged_code(effects: refused(scene: Scene(..scene, logged:)))
    == #(LogDebug, 23)
    as "and as a debug line after"
}

pub fn a_sell_with_no_vendor_open_is_refused_with_not_a_vendor_test() -> Nil {
  use <- owned_test.run(10_000)
  let items = [in_bag(guid: 12, item2_id: 20_791, index: 0, count: 5)]
  let none = Scene(..sell(items:, index: 0, quantity: 1), opened: None)
  let assert Ok(Refused(effects:, logged:)) = taken(scene: none)
    as "no window is open"
  assert logged_code(effects:) == #(LogWarning, 16)
    as "opcode.0x166: the sender needs a vendor interaction, so this is enum 16, with a warning the first time"
  assert logged_code(effects: refused(scene: Scene(..none, logged:)))
    == #(LogDebug, 16)
    as "a debug line the second time"
}

pub fn a_sell_by_a_dead_player_is_refused_with_player_busy_test() -> Nil {
  use <- owned_test.run(10_000)
  let items = [in_bag(guid: 12, item2_id: 20_791, index: 0, count: 5)]
  let dead =
    Scene(
      ..sell(items:, index: 0, quantity: 1),
      life: player_life_support.dead(),
    )
  assert logged_code(effects: refused(scene: dead)) == #(LogWarning, 2)
    as "opcode.0x166: the sender refuses a dead player with enum 2, PlayerBusy"
}

pub fn a_sell_to_a_vendor_gone_dead_far_or_hostile_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let items = [in_bag(guid: 12, item2_id: 20_791, index: 0, count: 5)]
  let base = sell(items:, index: 0, quantity: 1)
  let level_and_code = fn(scene) { logged_code(effects: refused(scene:)) }
  assert level_and_code(Scene(..base, opened: window_on(unit_id: 41)))
    == #(LogWarning, 59)
    as "opcode.0x7ea: a unit not in the picture is enum 59, Vendor_NoVendor"
  assert level_and_code(
      Scene(..base, vendors: vendor_support.stocking(creature_ids: [])),
    )
    == #(LogWarning, 16)
    as "a creature with no stock is enum 16, Vendor_NotAVendor"
  assert level_and_code(
      Scene(
        ..base,
        picture: walker_with(
          alive: False,
          hostile_to: Hostile(exile: False, dominion: False),
        ),
      ),
    )
    == #(LogWarning, 23)
    as "opcode.0x166: a dead vendor is enum 23 for a sale"
  assert level_and_code(
      Scene(
        ..base,
        picture: walker_with(
          alive: True,
          hostile_to: Hostile(exile: True, dominion: True),
        ),
      ),
    )
    == #(LogWarning, 62)
    as "opcode.0x7ea: a vendor Hostile to the player is enum 62"
  // The sale's range is 6.0 between the two edges (opcode.0x166), though the window opens at
  // 9.0.
  let at = fn(gap) {
    Scene(..base, picture: vendor_support.picture_with_walker(gap:))
  }
  assert asked(scene: at(5.5)).unit_id == vendor_support.walker_unit
    as "a vendor 5.5 away is sold to"
  assert level_and_code(at(6.5)) == #(LogWarning, 17)
    as "opcode.0x166: 6.5 is beyond the sale's 6.0, enum 17, Vendor_TooFar"
  assert level_and_code(at(9.5)) == #(LogWarning, 17)
    as "opcode.0x7ea: 9.5 is beyond the window's reach too"
  let assert Ok(Refused(logged:, ..)) = taken(scene: at(6.5))
  assert logged_code(effects: refused(scene: Scene(..at(6.5), logged:)))
    == #(LogDebug, 17)
    as "each reason is logged once as a warning, then as a debug line"
}

pub fn a_sale_past_the_credit_cap_stops_credits_at_the_cap_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert Ok(cap_row) =
    game_formula.get(
      tables: character_tables.shared(),
      id: id.GameFormulaId(1115),
    )
    as "the client's table holds GameFormula 1115"
  assert cap_row.dataint0 == 500_000
    as "GetCurrencyCap.entitlement_14: the credits cap is GameFormula 1115's dataint0"
  // 3 of 14838 pay 3 x 10 = 30 on 499,990: 10 over the cap.
  let items = [in_bag(guid: 11, item2_id: 14_838, index: 0, count: 3)]
  let scene =
    Scene(
      ..sell(items:, index: 0, quantity: 3),
      credits: credits(total: 499_990),
    )
  let sale = asked(scene:)
  assert sale.first.paid == 30 as "the sale pays 30"
  assert sale.held == 499_990
  assert sale.after == 500_000 as "the total stops at the cap"
}

pub fn a_sale_at_the_credit_cap_still_sells_and_its_entry_keeps_the_full_price_test() -> Nil {
  use <- owned_test.run(10_000)
  let items = [in_bag(guid: 11, item2_id: 14_838, index: 0, count: 3)]
  let scene =
    Scene(
      ..sell(items:, index: 0, quantity: 3),
      credits: credits(total: 500_000),
    )
  let sale = asked(scene:)
  assert sale.after == 500_000 as "the credits stay at the cap"
  let #(left, held_credits, buyback, effects) =
    vendor_sale.answered(
      sale:,
      items:,
      currencies: scene.credits,
      buyback: Buyback(next_id: 1, entries: []),
      answer: store.Sold(amount: 500_000, words: [
        store.SoldWord(item_guid: 11, random_stats: 0),
      ]),
    )
  assert left == [] as "the item still leaves"
  assert currency.credits(currencies: held_credits) == 500_000
  let assert [total, removed, added] = frames(effects:)
  assert_total(frame: total, total: 500_000)
  assert_removed(frame: removed, guid: 11)
  assert_entry(
    frame: added,
    entry: entry(buyback_id: 1, item_id: 14_838, quantity: 3, paid: 30),
  )
  assert buyback.entries
    == [
      world_entry.BuybackEntry(
        buyback_id: 1,
        item2_id: Item2Id(14_838),
        quantity: 3,
        currency_type_id: 1,
        amount: 30,
        random_stats: 0,
      ),
    ]
    as "lua.Vendor.buyback_price: the entry holds the price the sale paid for the stack, before the cap"
}

/// The bags of the junk tests: the junk that sells is 175 at index 0, 176 at 3 and 177 at 5;
/// 14838 is no junk, 6141 is a junk proxy item that does not sell (`item_property_test`)
/// and 74201 is junk with a sell price of 0; a junk stack in the bank stays.
fn junk_bags() -> List(HeldItem) {
  [
    in_bag(guid: 7, item2_id: 177, index: 5, count: 1),
    in_bag(guid: 1, item2_id: 175, index: 0, count: 1),
    in_bag(guid: 2, item2_id: 6141, index: 2, count: 5),
    in_bag(guid: 3, item2_id: 14_838, index: 1, count: 4),
    in_bag(guid: 4, item2_id: 74_201, index: 4, count: 1),
    in_bag(guid: 5, item2_id: 176, index: 3, count: 1),
    held(guid: 6, item2_id: 175, location: 3, index: 0, count: 1),
  ]
}

pub fn sell_junk_sells_every_sellable_category_94_stack_in_the_bags_test() -> Nil {
  use <- owned_test.run(10_000)
  // 175, 176 and 177 sell for 1 each (`item_price_test`); a vendor with the sell multiplier
  // 2.5 pays trunc(1 x 2.5) = 2 for each.
  let items = junk_bags()
  let scene = Scene(..selling_junk(items:), vendors: paying(multiplier: 2.5))
  let sale = asked(scene:)
  let junk = fn(guid, item2_id) {
    SoldItem(
      item_guid: guid,
      item2_id: Item2Id(item2_id),
      location: 1,
      held_count: 1,
      sold_count: 1,
      paid: 2,
    )
  }
  assert sale
    == Sale(
      unit_id: vendor_support.walker_unit,
      first: junk(1, 175),
      rest: [junk(5, 176), junk(7, 177)],
      currency_type_id: 1,
      held: 100,
      after: 106,
    )
    as "lua.Item.CodeEnumItem2Category.Junk: the three junk stacks that sell, whole, in bag-index order; the proxy, the item of no price, the bank's stack and 14838 stay"
  let #(left, held_credits, buyback, effects) =
    vendor_sale.answered(
      sale:,
      items:,
      currencies: scene.credits,
      buyback: Buyback(next_id: 1, entries: []),
      answer: store.Sold(amount: 106, words: [
        store.SoldWord(item_guid: 1, random_stats: 0),
        store.SoldWord(item_guid: 5, random_stats: 0),
        store.SoldWord(item_guid: 7, random_stats: 0),
      ]),
    )
  assert list.map(left, fn(item) { item.item_guid }) == [2, 3, 4, 6]
    as "the stacks not sold stay held"
  assert currency.credits(currencies: held_credits) == 106
  assert list.map(buyback.entries, fn(entry) { entry.buyback_id }) == [1, 2, 3]
    as "each stack is an entry, from the next id"
  assert buyback.next_id == 4
  let assert [total, r1, b1, r2, b2, r3, b3] = frames(effects:)
    as "one 0x919, then a 0x148 and a 0xBA for each stack"
  assert_total(frame: total, total: 106)
  assert_removed(frame: r1, guid: 1)
  assert_entry(
    frame: b1,
    entry: entry(buyback_id: 1, item_id: 175, quantity: 1, paid: 2),
  )
  assert_removed(frame: r2, guid: 5)
  assert_entry(
    frame: b2,
    entry: entry(buyback_id: 2, item_id: 176, quantity: 1, paid: 2),
  )
  assert_removed(frame: r3, guid: 7)
  assert_entry(
    frame: b3,
    entry: entry(buyback_id: 3, item_id: 177, quantity: 1, paid: 2),
  )
}

pub fn sell_junk_with_nothing_to_sell_sends_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  // Vendor.lua l.168 sends 0x167 on every vendor open with auto-sell on: nothing to sell is
  // no sale and no answer.
  let items = [
    in_bag(guid: 3, item2_id: 14_838, index: 1, count: 4),
    in_bag(guid: 2, item2_id: 6141, index: 2, count: 5),
  ]
  assert refused(scene: selling_junk(items:)) == []
    as "no junk stack sells: nothing is sent, logged or asked"
}

pub fn sell_junk_with_no_vendor_open_is_refused_with_not_a_vendor_test() -> Nil {
  use <- owned_test.run(10_000)
  let none = Scene(..selling_junk(items: junk_bags()), opened: None)
  assert logged_code(effects: refused(scene: none)) == #(LogWarning, 16)
    as "opcode.0x167: the sender needs a vendor interaction, so this is enum 16, logged"
}

pub fn a_sell_or_sell_junk_body_the_client_reader_refuses_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  let items = [in_bag(guid: 12, item2_id: 20_791, index: 0, count: 5)]
  let short =
    Scene(
      ..sell(items:, index: 0, quantity: 1),
      request: SellStack(body: <<1, 2, 3>>),
    )
  let assert Error(NotDecoded(undecoded:)) = taken(scene: short)
    as "opcode.0x166: the body is a place and a 32-bit quantity; three bytes are no message"
  assert undecoded.message_id == vendor_sale.sale_message_id
  assert client_connection.describe_undecoded(undecoded:) != ""
  let extra = Scene(..selling_junk(items:), request: SellJunk(body: <<1>>))
  let assert Error(NotDecoded(undecoded:)) = taken(scene: extra)
    as "opcode.0x167: the body is empty; a byte is no message"
  assert undecoded.message_id == vendor_sale.junk_message_id
}

pub fn a_sale_the_store_did_not_save_answers_db_failure_and_keeps_items_and_credits_test() -> Nil {
  use <- owned_test.run(10_000)
  let items = [in_bag(guid: 12, item2_id: 20_791, index: 0, count: 5)]
  let scene = sell(items:, index: 0, quantity: 2)
  let sale = asked(scene:)
  let before = Buyback(next_id: 3, entries: [])
  let answers = [
    #(store.ItemsNotSaved, LogWarning, "20791"),
    #(
      store.SaveRefused(constraint: "currency_amount_check"),
      LogError,
      "currency_amount_check",
    ),
  ]
  list.each(answers, fn(case_) {
    let #(answer, level, mentions) = case_
    let #(left, held_credits, buyback, effects) =
      vendor_sale.answered(
        sale:,
        items:,
        currencies: scene.credits,
        buyback: before,
        answer:,
      )
    assert left == items
      as "the store changed nothing, so the connection's items are as they were"
    assert currency.credits(currencies: held_credits) == 100
      as "the credits are as they were"
    assert buyback == before as "no buyback entry was made"
    let assert [Log(level: logged, text:), Refuse(code: 5)] = effects
      as "opcode.0x106: DbFailure 5, after a log line, and no 0x919, 0x148 or 0xBA"
    assert logged == level
    assert string.contains(text, mentions)
      as "the line names the item the sale sold, or the constraint the store refused"
  })
}

pub fn a_table_set_without_the_credit_cap_or_the_sell_fraction_row_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  assert list.append(vendor_sale.requirements(), currency.requirements())
    |> list.flat_map(fn(requirement) {
      requirement.missing(fixture_tables.shared())
    })
    == []
    as "the client's GameFormula holds rows 1115, 1116 and 1026"
  list.each(
    [
      #(1115, "the server's credit cap"),
      #(1116, "the server's Renown cap"),
      #(1026, "the server's sell price fraction"),
    ],
    fn(row_and_name) {
      let #(row, from_table) = row_and_name
      let assert Ok(rows) =
        fixture_tables.remove(
          rows: fixture_tables.rows(),
          table: "GameFormula",
          id: row,
        )
        as "the client's table holds the row"
      assert fixture_tables.edited(
          rows:,
          entries: [game_formula.entry()],
          requirements: list.append(
            vendor_sale.requirements(),
            currency.requirements(),
          ),
          derivations: [],
        )
        == Error(table_store.RowMissing(
          from_table:,
          column: "GameFormula id",
          to_table: "GameFormula",
          id: row,
        ))
        as "GetCurrencyCap.entitlement_14 and 0x14040bfb0: the cap and the sell fraction are read from GameFormula rows 1115, 1116 and 1026, so a load without one fails"
    },
  )
}

pub fn selling_a_worn_item_removes_it_with_0x148_reason_vendor_and_adds_a_buyback_entry_test() -> Nil {
  use <- owned_test.run(10_000)
  // Item2 13176 sells for 78 (`item_price_test`); it is worn at location 0, slot 5, beside a
  // stack in the bags. `0x1403d6a10` refuses only a worn bag at location 0, so this sells.
  let worn = held(guid: 16, item2_id: 13_176, location: 0, index: 5, count: 1)
  let bagged = in_bag(guid: 12, item2_id: 20_791, index: 0, count: 5)
  let items = [worn, bagged]
  let scene = sell_at(items:, location: 0, index: 5, quantity: 1)
  let sale = asked(scene:)
  assert sale
    == Sale(
      unit_id: vendor_support.walker_unit,
      first: SoldItem(
        item_guid: 16,
        item2_id: Item2Id(13_176),
        location: 0,
        held_count: 1,
        sold_count: 1,
        paid: 78,
      ),
      rest: [],
      currency_type_id: 1,
      held: 100,
      after: 178,
    )
    as "0x1403d6a10: the worn item is let through, and the store is asked to delete the stack at location 0"
  let #(left, held_credits, buyback, effects) =
    vendor_sale.answered(
      sale:,
      items:,
      currencies: scene.credits,
      buyback: Buyback(next_id: 1, entries: []),
      answer: store.Sold(amount: 178, words: [
        store.SoldWord(item_guid: 16, random_stats: 0),
      ]),
    )
  assert left == [bagged]
    as "the worn item leaves the held items; the stack in the bags stays"
  assert currency.credits(currencies: held_credits) == 178
  let assert [total, removed, added] = frames(effects:)
    as "a 0x919, then a 0x148 and a 0xBA, as for a stack in the bags"
  assert_total(frame: total, total: 178)
  assert_removed(frame: removed, guid: 16)
  assert_entry(
    frame: added,
    entry: entry(buyback_id: 1, item_id: 13_176, quantity: 1, paid: 78),
  )
  assert buyback.entries
    == [
      world_entry.BuybackEntry(
        buyback_id: 1,
        item2_id: Item2Id(13_176),
        quantity: 1,
        currency_type_id: 1,
        amount: 78,
        random_stats: 0,
      ),
    ]
    as "opcode.0xba.price: the sale is the buyback list's entry 1"
}

/// A sale of `quantity` of the stack at a place `location`, `index`, which `items` hold.
fn sell_at(
  items items: List(HeldItem),
  location location: Int,
  index index: Int,
  quantity quantity: Int,
) -> Scene {
  Scene(..selling(location:, index:, quantity:), items:)
}

pub fn selling_an_item_priced_in_glory_pays_its_row_amount_in_glory_and_its_entry_names_glory_test() -> Nil {
  use <- owned_test.run(10_000)
  // Item2 16053 sells for 60 Glory, CurrencyType 7 (`item_price_test`); the player holds 100
  // credits and no Glory, so the one of 16053 asks for a held of 0 and an after of 60.
  let items = [in_bag(guid: 21, item2_id: 16_053, index: 0, count: 1)]
  let scene =
    Scene(
      ..sell(items:, index: 0, quantity: 1),
      vendors: paying(multiplier: 1.55),
    )
  let sale = asked(scene:)
  assert sale
    == Sale(
      unit_id: vendor_support.walker_unit,
      first: SoldItem(
        item_guid: 21,
        item2_id: Item2Id(16_053),
        location: 1,
        held_count: 1,
        sold_count: 1,
        paid: 60,
      ),
      rest: [],
      currency_type_id: 7,
      held: 0,
      after: 60,
    )
    as "0x14041bcc0.formula: a price in Glory is the row's 60 whatever the vendor's sell multiplier 1.55 says, against the 0 Glory held"
  let #(left, held_currencies, buyback, effects) =
    vendor_sale.answered(
      sale:,
      items:,
      currencies: scene.credits,
      buyback: Buyback(next_id: 1, entries: []),
      answer: store.Sold(amount: 60, words: [
        store.SoldWord(item_guid: 21, random_stats: 0),
      ]),
    )
  assert left == [] as "the item leaves"
  assert currency.held(currencies: held_currencies, currency_type_id: 7) == 60
    as "the Glory held is the total the store left"
  assert currency.credits(currencies: held_currencies) == 100
    as "the credits are as they were"
  let assert [total, removed, added] = frames(effects:)
    as "a 0x919, then a 0x148 and a 0xBA"
  assert_total_of(frame: total, kind: 6, total: 60)
  assert_removed(frame: removed, guid: 21)
  assert_entry(
    frame: added,
    entry: entry_in(
      buyback_id: 1,
      item_id: 16_053,
      quantity: 1,
      paid: 60,
      currency_type: 7,
    ),
  )
  assert buyback.entries
    == [
      world_entry.BuybackEntry(
        buyback_id: 1,
        item2_id: Item2Id(16_053),
        quantity: 1,
        currency_type_id: 7,
        amount: 60,
        random_stats: 0,
      ),
    ]
    as "opcode.0xba.price: the entry names Glory (type 7) and the 60 paid"
}

pub fn a_sale_past_a_currency_cap_stops_that_currency_at_its_cap_and_its_entry_keeps_the_full_price_test() -> Nil {
  use <- owned_test.run(10_000)
  // The fixture holds no Item2 row priced in Renown (CurrencyType 2, capped by GameFormula
  // 1116 at 5,000), so Item2 16053 is edited to the 2,500 Renown that Item2 16069 sells for
  // in the client's own table.
  use tables <- fixture_tables.changed(table: "Item2", id: 16_053, with: [
    #("currencyTypeId0SellToVendor", Integer(2)),
    #("currencyAmount0SellToVendor", Integer(2500)),
  ])
  let items = [in_bag(guid: 21, item2_id: 16_053, index: 0, count: 1)]
  let renown =
    currency.with_amount(
      currencies: credits(total: 100),
      currency_type_id: 2,
      total: 4000,
    )
  let scene =
    Scene(..sell(items:, index: 0, quantity: 1), credits: renown, tables:)
  let sale = asked(scene:)
  assert sale.currency_type_id == 2 as "the item sells for Renown"
  assert sale.first.paid == 2500
  assert sale.held == 4000
  assert sale.after == 5000
    as "GetCurrencyCap.entitlement_14: Renown stops at GameFormula 1116's 5,000, not 6,500"
  let #(_, held_currencies, buyback, effects) =
    vendor_sale.answered(
      sale:,
      items:,
      currencies: scene.credits,
      buyback: Buyback(next_id: 1, entries: []),
      answer: store.Sold(amount: 5000, words: [
        store.SoldWord(item_guid: 21, random_stats: 0),
      ]),
    )
  assert currency.held(currencies: held_currencies, currency_type_id: 2) == 5000
  assert currency.credits(currencies: held_currencies) == 100
  let assert [total, _, added] = frames(effects:)
  assert_total_of(frame: total, kind: 1, total: 5000)
  assert_entry(
    frame: added,
    entry: entry_in(
      buyback_id: 1,
      item_id: 16_053,
      quantity: 1,
      paid: 2500,
      currency_type: 2,
    ),
  )
  assert list.map(buyback.entries, fn(entry) { entry.amount }) == [2500]
    as "lua.Vendor.buyback_price: the entry keeps the 2,500 the sale paid, before the cap"
}
