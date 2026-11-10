//// The player's buy from the open vendor (`genesis_prime/game/vendor_purchase`): the
//// client's 0x00BE taken against the held items and credits, and the store's answer to
//// the buy it asked for. Expected values come from these places.
//// - `opcode.0xbe`: the body is the unique id the window's 0x90B gave the item (its
////   position) and a quantity of lots; the client checks neither the stock nor the cash,
////   so the refusals are the server's, each with the code the vendor addon shows
////   (`GameLib.CodeEnumGenericError`): 5 DbFailure, 14 Vendor_UnknownItem, 16
////   Vendor_NotAVendor, 17 Vendor_TooFar, 20 Vendor_NotEnoughCash, 24 Vendor_NoQuantity,
////   27 Item_InventoryFull, 57 Player_CantDoWhileDead.
//// - `vendor.start_zone_prices`: the window shows 67 credits for Item2 14838, 13 for
////   20791 and 20 for 12078 (`item_price_test`).
//// - The Item2 rows (`fixture_tables`, the client's own): 14838 stacks to 50 and a lot
////   is 1 item (buyFromVendorStackCount 1); 20791 stacks to 99 and a lot is 5 items
////   (Vendor.lua l.437 to 452: price times the stack size times the spinner).
//// - The stock is Dorian Walker's, from `vendor_support`: position 1 is Item2 12078, 2 is
////   14838 and 3 is 20791, and unit 40 is his unit in the player's picture.
//// - `opcode.0x7ea`: the vendor-open checks the buy repeats are the 0x7EA's, with the
////   reach of 9.0 between the two edges.
//// - Where the items go is the server's choice (no client code decides it): a stack of the
////   same Item2 in the usable inventory (location 1, bag index below 16 with no bags) below
////   its stack limit is filled first, lowest index first, then the empty slots lowest
////   first, at most the stack limit each.
//// - `opcode.0x919` and `Item.CodeEnumItemUpdateReason`: the answer is a 0x919 of kind 0
////   with the new total, then a 0x111 for each new stack and a 0x17F for each grown stack,
////   each with the reason 7 (Vendor), which makes the client show "Bought <item>"
////   (Vendor.lua OnItemAdded l.733).
//// - `opcode.0xba.price` and `lua.Vendor.buyback_price`: a buy back costs what its entry
////   holds, in the entry's currency, so the 0x919 it ends in has that currency's kind (the
////   type - 1); the entry names no place, so a worn item's entry returns a stack to the bags.

import character_support
import character_tables
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/client_connection
import genesis_prime/connection/frame
import genesis_prime/game/currency.{type Currencies}
import genesis_prime/game/interaction.{Player}
import genesis_prime/game/player_life.{type Life}
import genesis_prime/game/shown
import genesis_prime/game/vendor
import genesis_prime/game/vendor_purchase.{type Taken, Asks, Purchase, Refused}
import genesis_prime/game/vendor_trade.{
  type Effect, Log, NotDecoded, Refuse, Send,
}
import genesis_prime/game/world_entry.{type Buyback, Buyback, BuybackEntry}
import genesis_prime/message/buyback_removed
import genesis_prime/message/currency_changed.{CurrencyChanged}
import genesis_prime/message/item_added
import genesis_prime/message/item_count_changed.{ItemCountChanged}
import genesis_prime/message/vendor_buyback
import genesis_prime/message/vendor_purchase as vendor_purchase_message
import genesis_prime/step.{LogDebug, LogError, LogWarning}
import genesis_prime/store.{
  type HeldItem, AccountId, Bought, CharacterId, HeldItem, ItemsNotSaved,
  NewStack, SaveRefused, StackGrowth,
}
import genesis_prime/table/id.{Item2Id}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set
import gleam/string
import owned_test
import player_life_support
import vendor_support

/// The positions of the stock in `vendor_support.items`.
const position_12078 = 1

const position_14838 = 2

const position_20791 = 3

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

fn body(unique_id unique_id: Int, quantity quantity: Int) -> BitArray {
  let assert Ok(body) =
    vendor_purchase_message.encode(vendor_purchase_message.VendorPurchase(
      unique_id:,
      quantity:,
    ))
    as "two 32-bit values fit the message"
  body
}

fn credits(total total: Int) -> Currencies {
  currency.with_amount(
    currencies: currency.from_held(held: []),
    currency_type_id: currency.credits_type,
    total:,
  )
}

/// A stack of Item2 `item2_id` in the inventory.
fn in_bag(
  guid guid: Int,
  item2_id item2_id: Int,
  index index: Int,
  count count: Int,
) -> HeldItem {
  HeldItem(
    item_guid: guid,
    item2_id: Item2Id(item2_id),
    location: 1,
    bag_index: index,
    stack_count: count,
    random_stats: 0,
  )
}

/// Everything a buy reads, at the open window, the walker in reach and the player alive;
/// each test changes what it is about.
type Scene {
  Scene(
    body: BitArray,
    items: List(HeldItem),
    credits: Currencies,
    opened: Option(vendor.Opened),
    life: Life,
    gap: Float,
    vendors: vendor.Vendors,
    logged: set.Set(String),
    buyback: Buyback,
  )
}

fn scene(unique_id unique_id: Int, quantity quantity: Int) -> Scene {
  Scene(
    body: body(unique_id:, quantity:),
    items: [],
    credits: credits(total: 100_000),
    opened: walkers_window(),
    life: player_life_support.alive(),
    gap: 1.0,
    vendors: vendor_support.stocking(creature_ids: [74_812]),
    logged: set.new(),
    buyback: held_back(),
  )
}

fn taken(scene scene: Scene) -> Result(Taken, vendor_trade.Refusal) {
  vendor_purchase.take(
    body: scene.body,
    items: scene.items,
    currencies: scene.credits,
    opened: scene.opened,
    life: scene.life,
    player: Player(
      race_id: id.RaceId(1),
      faction: shown.Dominion,
      place: connection_support.entry_place(),
    ),
    picture: vendor_support.picture_with_walker(gap: scene.gap),
    tables: character_tables.shared(),
    vendors: scene.vendors,
    now_ms: 0,
    logged: scene.logged,
  )
}

/// The purchase a buy asks the store for, which it must have accepted.
fn asked(scene scene: Scene) -> vendor_purchase.Purchase {
  let assert Ok(Asks(purchase:, ..)) = taken(scene:)
    as "the buy passes every check, so the store is asked"
  purchase
}

/// The effects of a buy the rule refused.
fn refused(scene scene: Scene) -> List(Effect) {
  let assert Ok(Refused(effects:, ..)) = taken(scene:)
    as "the buy breaks a check, so it is answered and nothing is asked"
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

/// The level of the one log line and the code of the one 0x106 among the effects of a
/// refusal that is logged.
fn logged_code(effects effects: List(Effect)) -> #(step.LogLevel, Int) {
  let assert [Log(level:, ..), Refuse(code:)] = effects
    as "a logged refusal is a log line, then the 0x106"
  #(level, code)
}

/// The buyback list the buy back tests read, as sales left it: entry 2 is 3 of Item2 14838
/// sold for 40 credits in all (the stock price of 14838 is 67 each, so the entry's credits
/// are not a stock price) and entry 3 is 7 of 20791 sold for 91; entry 1 was bought back
/// and is gone, so the next id is 4.
fn held_back() -> Buyback {
  Buyback(next_id: 4, entries: [
    BuybackEntry(
      buyback_id: 2,
      item2_id: Item2Id(14_838),
      quantity: 3,
      currency_type_id: 1,
      amount: 40,
      random_stats: 0,
    ),
    BuybackEntry(
      buyback_id: 3,
      item2_id: Item2Id(20_791),
      quantity: 7,
      currency_type_id: 1,
      amount: 91,
      random_stats: 0,
    ),
  ])
}

fn back_body(buyback_id buyback_id: Int) -> BitArray {
  let assert Ok(body) =
    vendor_buyback.encode(vendor_buyback.VendorBuyback(buyback_id:))
    as "a 32-bit id fits the message"
  body
}

/// The scene's body is a buy's; a buy back is the scene with the 0xBB of this id.
fn buying_back(buyback_id buyback_id: Int) -> Scene {
  Scene(..scene(unique_id: 0, quantity: 0), body: back_body(buyback_id:))
}

fn taken_back(scene scene: Scene) -> Result(Taken, vendor_trade.Refusal) {
  vendor_purchase.take_back(
    body: scene.body,
    items: scene.items,
    currencies: scene.credits,
    opened: scene.opened,
    buyback: scene.buyback,
    life: scene.life,
    player: Player(
      race_id: id.RaceId(1),
      faction: shown.Dominion,
      place: connection_support.entry_place(),
    ),
    picture: vendor_support.picture_with_walker(gap: scene.gap),
    tables: character_tables.shared(),
    vendors: scene.vendors,
    now_ms: 0,
    logged: scene.logged,
  )
}

/// The purchase a buy back asks the store for, which it must have accepted.
fn asked_back(scene scene: Scene) -> vendor_purchase.Purchase {
  let assert Ok(Asks(purchase:, ..)) = taken_back(scene:)
    as "the buy back passes every check, so the store is asked"
  purchase
}

/// The effects and log keys of a buy back the rule refused.
fn refused_back(scene scene: Scene) -> #(List(Effect), set.Set(String)) {
  let assert Ok(Refused(effects:, logged:)) = taken_back(scene:)
    as "the buy back breaks a check, so it is answered and nothing is asked"
  #(effects, logged)
}

/// The frames among the effects.
fn frames(effects effects: List(Effect)) -> List(frame.Frame) {
  list.filter_map(effects, fn(effect) {
    case effect {
      Send(frame:) -> Ok(frame)
      Log(..) | Refuse(..) -> Error(Nil)
    }
  })
}

pub fn a_buy_at_the_shown_price_asks_the_store_to_take_the_price_and_add_the_items_test() -> Nil {
  use <- owned_test.run(10_000)
  // Item2 14838 at the 67 the window shows (`item_price_test`), one lot of 1 item, with
  // 100 credits held and an empty inventory.
  let scene =
    Scene(
      ..scene(unique_id: position_14838, quantity: 1),
      credits: credits(total: 100),
    )
  assert asked(scene:)
    == Purchase(
      kind: vendor_purchase.Bought,
      unit_id: vendor_support.walker_unit,
      item2_id: Item2Id(14_838),
      items_bought: 1,
      cost: 67,
      currency_type_id: 1,
      held: 100,
      grow: [],
      make: [
        NewStack(location: 1, bag_index: 0, stack_count: 1, random_stats: 0),
      ],
    )
    as "opcode.0xbe: one item for the 67 the window shows, against the 100 held, in the first empty slot"
  assert vendor_purchase.request(
      purchase: asked(scene:),
      account_id: AccountId(7),
      character_id: CharacterId(42),
      session_epoch: character_support.epoch(1),
    )
    == store.Items(store.BuyFromVendor(
      account_id: AccountId(7),
      character_id: CharacterId(42),
      session_epoch: character_support.epoch(1),
      currency_type_id: 1,
      held: 100,
      cost: 67,
      grow: [],
      make: [
        NewStack(location: 1, bag_index: 0, stack_count: 1, random_stats: 0),
      ],
      item2_id: Item2Id(14_838),
    ))
    as "the store is asked to take the price off the total held and add the item, fenced by the login's epoch"
}

pub fn a_buy_of_several_lots_gives_stack_count_times_quantity_items_test() -> Nil {
  use <- owned_test.run(10_000)
  // Item2 20791: a lot is 5 items (buyFromVendorStackCount), 13 credits each; 3 lots is
  // 15 items for 13 x 5 x 3 = 195.
  let purchase = asked(scene: scene(unique_id: position_20791, quantity: 3))
  assert purchase.items_bought == 15
    as "Vendor.lua l.437 to 452: 3 lots of 5 items"
  assert purchase.cost == 195 as "13 credits an item, 15 items"
  assert purchase.make
    == [NewStack(location: 1, bag_index: 0, stack_count: 15, random_stats: 0)]
    as "20791 stacks to 99, so the 15 items are one stack"
}

pub fn a_buy_fills_a_held_stack_with_room_before_an_empty_slot_test() -> Nil {
  use <- owned_test.run(10_000)
  // The server's choice, stated in the module's doc: 14838 stacks to 50. Slot 1 holds a
  // full stack, slot 3 holds 48 and slot 0 is empty; 5 are bought.
  let items = [
    in_bag(guid: 11, item2_id: 14_838, index: 1, count: 50),
    in_bag(guid: 12, item2_id: 14_838, index: 3, count: 48),
  ]
  let purchase =
    asked(scene: Scene(..scene(unique_id: position_14838, quantity: 5), items:))
  assert purchase.grow
    == [StackGrowth(item_guid: 12, held_count: 48, new_count: 50)]
    as "the stack with room is filled up to its limit"
  assert purchase.make
    == [NewStack(location: 1, bag_index: 0, stack_count: 3, random_stats: 0)]
    as "the rest goes to the lowest empty slot"
  // A buy larger than a stack limit makes stacks of the limit, lowest slot first, the
  // last holding the rest: 120 items into an empty inventory is 50, 50 and 20.
  let large = asked(scene: scene(unique_id: position_14838, quantity: 120))
  assert large.make
    == [
      NewStack(location: 1, bag_index: 0, stack_count: 50, random_stats: 0),
      NewStack(location: 1, bag_index: 1, stack_count: 50, random_stats: 0),
      NewStack(location: 1, bag_index: 2, stack_count: 20, random_stats: 0),
    ]
    as "a stack holds at most the Item2's maxStackCount"
}

pub fn a_buy_over_the_credits_held_is_refused_with_not_enough_cash_test() -> Nil {
  use <- owned_test.run(10_000)
  // 14838 costs 67: 66 held is one short, 67 held is enough.
  let short =
    Scene(
      ..scene(unique_id: position_14838, quantity: 1),
      credits: credits(total: 66),
    )
  assert codes(effects: refused(scene: short)) == [20]
    as "enum 20, Vendor_NotEnoughCash (Vendor.lua l.1490)"
  let exact =
    Scene(
      ..scene(unique_id: position_14838, quantity: 1),
      credits: credits(total: 67),
    )
  assert asked(scene: exact).cost == 67
    as "the credits held may equal the price"
}

pub fn an_id_the_vendor_does_not_sell_is_refused_with_unknown_item_test() -> Nil {
  use <- owned_test.run(10_000)
  // The stock has positions 1 to 3.
  assert codes(effects: refused(scene: scene(unique_id: 4, quantity: 1)))
    == [14]
    as "enum 14, Vendor_UnknownItem: position 4 is not in the window"
  assert codes(effects: refused(scene: scene(unique_id: 0, quantity: 1)))
    == [14]
    as "no item has the unique id 0"
}

pub fn a_quantity_of_0_is_refused_with_no_quantity_test() -> Nil {
  use <- owned_test.run(10_000)
  assert codes(
      effects: refused(scene: scene(unique_id: position_12078, quantity: 0)),
    )
    == [24]
    as "enum 24, Vendor_NoQuantity"
}

pub fn a_buy_that_does_not_fit_the_inventory_is_refused_with_inventory_full_test() -> Nil {
  use <- owned_test.run(10_000)
  // The 16 usable slots (no bag worn) each hold a full stack of 14838.
  let full =
    list.index_map(list.repeat(Nil, 16), fn(_, index) {
      in_bag(guid: 100 + index, item2_id: 14_838, index:, count: 50)
    })
  assert codes(effects: refused(
      scene: Scene(..scene(unique_id: position_14838, quantity: 1), items: full),
    ))
    == [27]
    as "enum 27, Item_InventoryFull: no slot has room, so the store is not asked"
  // One slot with room for 1 more takes one item but not two.
  let room = [
    in_bag(guid: 99, item2_id: 14_838, index: 15, count: 49),
    ..list.take(full, 15)
  ]
  assert asked(
      scene: Scene(..scene(unique_id: position_14838, quantity: 1), items: room),
    ).grow
    == [StackGrowth(item_guid: 99, held_count: 49, new_count: 50)]
  assert codes(effects: refused(
      scene: Scene(..scene(unique_id: position_14838, quantity: 2), items: room),
    ))
    == [27]
    as "the second item has no place"
}

pub fn a_buy_with_no_vendor_open_is_refused_with_not_a_vendor_test() -> Nil {
  use <- owned_test.run(10_000)
  // `opcode.0xbe`: the client sends the buy only in a vendor interaction, so a buy with
  // no window open is a modified or stale client.
  let none =
    Scene(..scene(unique_id: position_14838, quantity: 1), opened: None)
  let assert Ok(Refused(effects:, logged:)) = taken(scene: none)
    as "no window is open"
  assert logged_code(effects:) == #(LogWarning, 16)
    as "enum 16, Vendor_NotAVendor, with a warning the first time"
  assert logged_code(effects: refused(scene: Scene(..none, logged:)))
    == #(LogDebug, 16)
    as "a debug line the second time"
}

pub fn a_buy_by_a_dead_player_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let dead =
    Scene(
      ..scene(unique_id: position_14838, quantity: 1),
      life: player_life_support.dead(),
    )
  assert logged_code(effects: refused(scene: dead)) == #(LogWarning, 57)
    as "enum 57, Player_CantDoWhileDead (the client's sender sends nothing for a dead player)"
}

pub fn a_buy_from_a_vendor_now_out_of_reach_is_refused_with_too_far_test() -> Nil {
  use <- owned_test.run(10_000)
  // The edge to edge gap is 9.0 at most (`opcode.0x7ea`); the window stays open, as the
  // client's own window does until the client ends the interaction.
  let at_reach =
    Scene(..scene(unique_id: position_14838, quantity: 1), gap: 8.5)
  assert asked(scene: at_reach).unit_id == vendor_support.walker_unit
    as "a vendor within the reach is bought from"
  let far = Scene(..at_reach, gap: 9.5)
  assert logged_code(effects: refused(scene: far)) == #(LogWarning, 17)
    as "enum 17, Vendor_TooFar"
}

pub fn a_body_the_client_reader_refuses_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert Error(NotDecoded(undecoded:)) =
    taken(scene: Scene(..scene(unique_id: 1, quantity: 1), body: <<1, 2, 3>>))
    as "opcode.0xbe: the body is two 32-bit values; three bytes are no message"
  assert undecoded.message_id == vendor_purchase.message_id
  assert client_connection.describe_undecoded(undecoded:) != ""
}

/// The purchase of 5 items of 14838 into a stack of 48 and an empty slot, which the
/// answer tests answer.
fn two_places() -> #(vendor_purchase.Purchase, List(HeldItem)) {
  let items = [in_bag(guid: 12, item2_id: 14_838, index: 3, count: 48)]
  #(
    asked(
      scene: Scene(
        ..scene(unique_id: position_14838, quantity: 5),
        items:,
        credits: credits(total: 1000),
      ),
    ),
    items,
  )
}

pub fn a_saved_buy_sends_the_new_total_then_the_items_with_reason_vendor_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(purchase, items) = two_places()
  let made = in_bag(guid: 500, item2_id: 14_838, index: 0, count: 3)
  let listed = held_back()
  let #(held, held_credits, buyback, effects) =
    vendor_purchase.answered(
      purchase:,
      items:,
      currencies: credits(total: 1000),
      buyback: listed,
      answer: Bought(amount: 665, made: [made]),
    )
  assert buyback == listed
    as "a buy of the stock leaves the buyback list as it was"
  assert currency.credits(currencies: held_credits) == 665
    as "the credits the store left: 1000 less 5 x 67"
  assert list.sort(held, fn(a, b) { int.compare(a.item_guid, b.item_guid) })
    == [in_bag(guid: 12, item2_id: 14_838, index: 3, count: 50), made]
    as "the grown stack holds 50 and the new stack is held with the guid the store gave"
  let sent =
    list.filter_map(effects, fn(effect) {
      case effect {
        Send(frame:) -> Ok(frame)
        Log(..) | Refuse(..) -> Error(Nil)
      }
    })
  let assert [total, grown, added] = sent
    as "a 0x919, then a 0x17F for the grown stack and a 0x111 for the new one"
  assert total.message_id == currency_changed.message_id
  let assert Ok(CurrencyChanged(kind: 0, total: 665, field_3: 0, field_4: 0)) =
    currency_changed.decode(total.body)
    as "opcode.0x919: kind 0 sets credits to the new total, and the two 32-bit values are 0"
  assert grown.message_id == item_count_changed.message_id
  assert item_count_changed.decode(grown.body)
    == Ok(ItemCountChanged(item_guid: 12, count: 50, reason: 7))
    as "Item.CodeEnumItemUpdateReason: Vendor is 7"
  assert added.message_id == item_added.message_id
  let assert Ok(item_added.ItemAdded(held_item:)) =
    item_added.decode(added.body)
    as "0x111 decodes"
  assert held_item.reason == 7 as "Item.CodeEnumItemUpdateReason: Vendor is 7"
  assert held_item.item.item_guid == 500
  assert held_item.item.item_id == 14_838
  assert held_item.item.location == 1
  assert held_item.item.bag_index == 0
  assert held_item.item.stack_count == 3
}

pub fn a_buy_the_store_did_not_save_sends_db_failure_and_keeps_credits_and_items_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(purchase, items) = two_places()
  // A buy the store did not save leaves the items and credits as they were and answers
  // enum 5 (Vendor.lua tPurchaseFailEvent); a refusal by a constraint is a bug of the
  // server's, so it is an error line where a changed login is a warning.
  list.each(
    [
      #(ItemsNotSaved, LogWarning, "a later login"),
      #(SaveRefused(constraint: "item_place_key"), LogError, "item_place_key"),
    ],
    fn(case_) {
      let #(answer, level, naming) = case_
      let listed = held_back()
      let #(held, held_credits, buyback, effects) =
        vendor_purchase.answered(
          purchase:,
          items:,
          currencies: credits(total: 1000),
          buyback: listed,
          answer:,
        )
      assert buyback == listed as "the buyback list is as it was"
      assert held == items as "no item changed"
      assert currency.credits(currencies: held_credits) == 1000
        as "no credit was taken"
      let assert [Log(level: logged_at, text:), Refuse(code: 5)] = effects
        as "a log line and a 0x106 of DbFailure"
      assert logged_at == level
      assert string.contains(text, naming)
        as "the log says why the buy was not saved"
    },
  )
}

pub fn a_buy_is_priced_from_the_vendor_now_at_the_unit_not_the_one_the_window_opened_on_test() -> Nil {
  use <- owned_test.run(10_000)
  // The window opened while the unit was a vendor selling 12078, 14838 and 20791 at
  // positions 1 to 3 (67 credits for 14838 at position 2); the unit is now a vendor selling
  // 20791, 12078 and 14838, whose position 2 is 12078 at the 20 the window of that vendor
  // shows (`item_price_test`). The buy repeats the 0x7EA's checks against the unit as it is
  // now (opcode.0x7ea), so it is the stock the checks read that the buy is made from.
  let scene =
    Scene(
      ..scene(unique_id: position_14838, quantity: 1),
      vendors: vendor_support.stocking_items(creature_ids: [74_812], items: [
        20_791,
        12_078,
        14_838,
      ]),
    )
  let purchase = asked(scene:)
  assert purchase.item2_id == Item2Id(12_078)
    as "position 2 of the vendor now at the unit is 12078"
  assert purchase.cost == 20
    as "the price of 12078, not the 67 of the old window's 14838"
}

pub fn a_buy_back_takes_the_entry_price_and_returns_its_items_test() -> Nil {
  use <- owned_test.run(10_000)
  // Entry 2 is 3 of Item2 14838 for the 40 credits the sale paid; the credits held are 100,
  // the inventory holds a stack of 48 (limit 50) and an empty slot is at index 0.
  // `opcode.0xbb`: the client sends 0xBB under the conditions of 0xBE and the server takes
  // the entry's price (`lua.Vendor.buyback_price`: what the sale paid), not the stock price.
  let items = [in_bag(guid: 12, item2_id: 14_838, index: 3, count: 48)]
  let scene =
    Scene(..buying_back(buyback_id: 2), items:, credits: credits(total: 100))
  let purchase = asked_back(scene:)
  assert purchase
    == Purchase(
      kind: vendor_purchase.BoughtBack(buyback_id: 2),
      unit_id: vendor_support.walker_unit,
      item2_id: Item2Id(14_838),
      items_bought: 3,
      cost: 40,
      currency_type_id: 1,
      held: 100,
      grow: [StackGrowth(item_guid: 12, held_count: 48, new_count: 50)],
      make: [
        NewStack(location: 1, bag_index: 0, stack_count: 1, random_stats: 0),
      ],
    )
    as "the entry's 3 items for the entry's 40 credits, not the 3 x 67 of the stock, into the held stack's room then the first empty slot"
  assert vendor_purchase.request(
      purchase:,
      account_id: AccountId(7),
      character_id: CharacterId(42),
      session_epoch: character_support.epoch(1),
    )
    == store.Items(store.BuyFromVendor(
      account_id: AccountId(7),
      character_id: CharacterId(42),
      session_epoch: character_support.epoch(1),
      currency_type_id: 1,
      held: 100,
      cost: 40,
      grow: [StackGrowth(item_guid: 12, held_count: 48, new_count: 50)],
      make: [
        NewStack(location: 1, bag_index: 0, stack_count: 1, random_stats: 0),
      ],
      item2_id: Item2Id(14_838),
    ))
    as "the store is asked as for a buy: the entry's price off the total, the items added"
  // The store's answer: the new total, the grown stack's 0x17F, the new stack's 0x111, both
  // with the reason 16 (Item.CodeEnumItemUpdateReason Buyback), then the 0xBD naming the entry.
  let made = in_bag(guid: 500, item2_id: 14_838, index: 0, count: 1)
  let #(held, held_credits, buyback, effects) =
    vendor_purchase.answered(
      purchase:,
      items:,
      currencies: credits(total: 100),
      buyback: scene.buyback,
      answer: Bought(amount: 60, made: [made]),
    )
  assert currency.credits(currencies: held_credits) == 60
    as "the credits the store left: 100 less the entry's 40"
  assert list.sort(held, fn(a, b) { int.compare(a.item_guid, b.item_guid) })
    == [in_bag(guid: 12, item2_id: 14_838, index: 3, count: 50), made]
    as "the items are held as the answer says"
  assert buyback
    == Buyback(next_id: 4, entries: [
      BuybackEntry(
        buyback_id: 3,
        item2_id: Item2Id(20_791),
        quantity: 7,
        currency_type_id: 1,
        amount: 91,
        random_stats: 0,
      ),
    ])
    as "entry 2 leaves the list and nothing else changes, not even the next id"
  let assert [total, grown, added, removed] = frames(effects:)
    as "a 0x919, a 0x17F for the grown stack, a 0x111 for the new one, then a 0xBD"
  assert total.message_id == currency_changed.message_id
  assert currency_changed.decode(total.body)
    == Ok(CurrencyChanged(kind: 0, total: 60, field_3: 0, field_4: 0))
    as "opcode.0x919: kind 0 sets credits to the new total"
  assert grown.message_id == item_count_changed.message_id
  assert item_count_changed.decode(grown.body)
    == Ok(ItemCountChanged(item_guid: 12, count: 50, reason: 16))
    as "Item.CodeEnumItemUpdateReason: Buyback is 16"
  assert added.message_id == item_added.message_id
  let assert Ok(item_added.ItemAdded(held_item:)) =
    item_added.decode(added.body)
    as "0x111 decodes"
  assert held_item.reason == 16
    as "Item.CodeEnumItemUpdateReason: Buyback is 16"
  assert held_item.item.item_guid == 500
  assert held_item.item.stack_count == 1
  assert removed.message_id == buyback_removed.message_id
  assert buyback_removed.decode(removed.body)
    == Ok(buyback_removed.BuybackRemoved(buyback_id: 2))
    as "opcode.0xbd: the id of the entry bought back"
  // A buy back the store did not save leaves the list as it was.
  let #(held, held_credits, buyback, effects) =
    vendor_purchase.answered(
      purchase:,
      items:,
      currencies: credits(total: 100),
      buyback: scene.buyback,
      answer: ItemsNotSaved,
    )
  assert buyback == scene.buyback as "the entry stays on the list"
  assert held == items as "no item changed"
  assert currency.credits(currencies: held_credits) == 100
    as "no credit was taken"
  let assert [Log(level: LogWarning, text:), Refuse(code: 5)] = effects
    as "a log line and a 0x106 of DbFailure, and no 0xBD"
  assert string.contains(text, "buy back of entry 2")
    as "the log names the entry"
}

pub fn a_buy_back_works_at_a_vendor_other_than_the_one_sold_to_test() -> Nil {
  use <- owned_test.run(10_000)
  // `opcode.0xbb`: the list is the player's, not a vendor's, and an entry names no vendor.
  // The vendor at the unit now sells only 20791 and 12078, neither the entry's Item2 14838.
  let other =
    Scene(
      ..buying_back(buyback_id: 2),
      vendors: vendor_support.stocking_items(creature_ids: [74_812], items: [
        20_791,
        12_078,
      ]),
    )
  let purchase = asked_back(scene: other)
  assert purchase.item2_id == Item2Id(14_838)
    as "the entry's Item2 is returned though this vendor does not stock it"
  assert purchase.cost == 40
    as "the entry's price, whatever this vendor sells at"
  assert purchase.kind == vendor_purchase.BoughtBack(buyback_id: 2)
}

pub fn a_buy_back_of_an_id_not_in_the_list_is_refused_with_unknown_item_test() -> Nil {
  use <- owned_test.run(10_000)
  // The list holds ids 2 and 3; id 1 was bought back, 4 was never given, 0 is none.
  let #(effects, logged) = refused_back(scene: buying_back(buyback_id: 4))
  assert logged_code(effects:) == #(LogWarning, 14)
    as "enum 14, Vendor_UnknownItem, with a warning the first time"
  assert frames(effects:) == [] as "no 0xBD: nothing left the list"
  let again = refused_back(scene: Scene(..buying_back(buyback_id: 4), logged:))
  assert logged_code(effects: again.0) == #(LogDebug, 14)
    as "a debug line the second time"
  assert codes(effects: refused_back(scene: buying_back(buyback_id: 1)).0)
    == [14]
    as "an entry already bought back is no longer on the list"
  assert codes(effects: refused_back(scene: buying_back(buyback_id: 0)).0)
    == [14]
    as "no entry has the id 0"
  let empty =
    Scene(
      ..buying_back(buyback_id: 2),
      buyback: Buyback(next_id: 1, entries: []),
    )
  assert codes(effects: refused_back(scene: empty).0) == [14]
    as "an empty list holds no id"
}

pub fn a_buy_back_over_the_credits_held_or_the_room_left_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  // Entry 2 costs 40: 39 held is one short, 40 held is enough.
  let short = Scene(..buying_back(buyback_id: 2), credits: credits(total: 39))
  assert codes(effects: refused_back(scene: short).0) == [20]
    as "enum 20, Vendor_NotEnoughCash, against the entry's price"
  let exact = Scene(..buying_back(buyback_id: 2), credits: credits(total: 40))
  assert asked_back(scene: exact).cost == 40
    as "the credits held may equal the entry's price"
  // The 16 usable slots each hold a full stack of 14838: the 3 items have no place.
  let full =
    list.index_map(list.repeat(Nil, 16), fn(_, index) {
      in_bag(guid: 100 + index, item2_id: 14_838, index:, count: 50)
    })
  assert codes(
      effects: refused_back(
        scene: Scene(..buying_back(buyback_id: 2), items: full),
      ).0,
    )
    == [27]
    as "enum 27, Item_InventoryFull: the store is not asked and the list is not changed"
}

/// The buyback list of the sales in other places and currencies: entry 5 is 1 of Item2 16053
/// sold for 60 Glory (CurrencyType 7), entry 6 is 1 of 13176 sold for 78 credits from its
/// worn place.
fn sold_elsewhere() -> Buyback {
  Buyback(next_id: 7, entries: [
    BuybackEntry(
      buyback_id: 5,
      item2_id: Item2Id(16_053),
      quantity: 1,
      currency_type_id: 7,
      amount: 60,
      random_stats: 0,
    ),
    BuybackEntry(
      buyback_id: 6,
      item2_id: Item2Id(13_176),
      quantity: 1,
      currency_type_id: 1,
      amount: 78,
      random_stats: 0,
    ),
  ])
}

/// The credits and the 80 Glory a player holds for the entries sold in Glory.
fn credits_and_glory() -> Currencies {
  currency.with_amount(
    currencies: credits(total: 100),
    currency_type_id: 7,
    total: 80,
  )
}

pub fn a_buy_back_of_an_entry_sold_for_glory_takes_glory_and_sends_its_total_test() -> Nil {
  use <- owned_test.run(10_000)
  // `opcode.0xba.price`: an entry carries the currency type and the amount its sale paid, and
  // `lua.Vendor.buyback_price` is what the client shows for it. The player holds 100 credits
  // and 80 Glory; entry 5 costs 60 Glory.
  let scene =
    Scene(
      ..buying_back(buyback_id: 5),
      credits: credits_and_glory(),
      buyback: sold_elsewhere(),
    )
  let purchase = asked_back(scene:)
  assert purchase
    == Purchase(
      kind: vendor_purchase.BoughtBack(buyback_id: 5),
      unit_id: vendor_support.walker_unit,
      item2_id: Item2Id(16_053),
      items_bought: 1,
      cost: 60,
      currency_type_id: 7,
      held: 80,
      grow: [],
      make: [
        NewStack(location: 1, bag_index: 0, stack_count: 1, random_stats: 0),
      ],
    )
    as "the entry's 60 Glory against the 80 Glory held, not the credits"
  assert vendor_purchase.request(
      purchase:,
      account_id: AccountId(7),
      character_id: CharacterId(42),
      session_epoch: character_support.epoch(1),
    )
    == store.Items(store.BuyFromVendor(
      account_id: AccountId(7),
      character_id: CharacterId(42),
      session_epoch: character_support.epoch(1),
      currency_type_id: 7,
      held: 80,
      cost: 60,
      grow: [],
      make: [
        NewStack(location: 1, bag_index: 0, stack_count: 1, random_stats: 0),
      ],
      item2_id: Item2Id(16_053),
    ))
    as "the store is asked to take the 60 off the 80 Glory held"
  let made = in_bag(guid: 500, item2_id: 16_053, index: 0, count: 1)
  let #(_, held_currencies, buyback, effects) =
    vendor_purchase.answered(
      purchase:,
      items: [],
      currencies: credits_and_glory(),
      buyback: sold_elsewhere(),
      answer: Bought(amount: 20, made: [made]),
    )
  assert currency.held(currencies: held_currencies, currency_type_id: 7) == 20
    as "the Glory the store left: 80 less the entry's 60"
  assert currency.credits(currencies: held_currencies) == 100
    as "the credits are as they were"
  assert list.map(buyback.entries, fn(entry) { entry.buyback_id }) == [6]
    as "entry 5 leaves the list"
  let assert [total, _, removed] = frames(effects:)
    as "a 0x919, a 0x111 for the new stack, then a 0xBD"
  assert total.message_id == currency_changed.message_id
  assert currency_changed.decode(total.body)
    == Ok(CurrencyChanged(kind: 6, total: 20, field_3: 0, field_4: 0))
    as "opcode.0x919: the kind is the currency type 7 - 1, and the total is Glory's"
  assert buyback_removed.decode(removed.body)
    == Ok(buyback_removed.BuybackRemoved(buyback_id: 5))
    as "opcode.0xbd: the id of the entry bought back"
}

pub fn a_buy_back_over_the_amount_held_of_its_currency_is_refused_with_not_enough_cash_test() -> Nil {
  use <- owned_test.run(10_000)
  // Entry 5 costs 60 Glory. 100,000 credits are held, which the entry does not ask for, and
  // 59 Glory is one short; 60 is enough; no Glory row is 0 held.
  let with_glory = fn(glory) {
    Scene(
      ..buying_back(buyback_id: 5),
      credits: currency.with_amount(
        currencies: credits(total: 100_000),
        currency_type_id: 7,
        total: glory,
      ),
      buyback: sold_elsewhere(),
    )
  }
  assert codes(effects: refused_back(scene: with_glory(59)).0) == [20]
    as "enum 20, Vendor_NotEnoughCash: the credits held do not pay for an entry in Glory"
  assert asked_back(scene: with_glory(60)).cost == 60
    as "the Glory held may equal the entry's price"
  let none_held =
    Scene(
      ..buying_back(buyback_id: 5),
      credits: credits(total: 100_000),
      buyback: sold_elsewhere(),
    )
  assert codes(effects: refused_back(scene: none_held).0) == [20]
    as "a currency with no held row is 0 held"
}

pub fn a_bought_back_worn_item_returns_to_the_bags_test() -> Nil {
  use <- owned_test.run(10_000)
  // The entry names no place (`opcode.0xba.price`), so item 13176 sold from its worn place
  // (location 0) comes back as a new stack in the first empty inventory slot, here index 1
  // beside a stack at index 0. Wearing it again is left to the player.
  let items = [in_bag(guid: 12, item2_id: 20_791, index: 0, count: 5)]
  let scene =
    Scene(
      ..buying_back(buyback_id: 6),
      items:,
      credits: credits(total: 100),
      buyback: sold_elsewhere(),
    )
  let purchase = asked_back(scene:)
  assert purchase.item2_id == Item2Id(13_176)
  assert purchase.cost == 78
  assert purchase.grow == []
  assert purchase.make
    == [NewStack(location: 1, bag_index: 1, stack_count: 1, random_stats: 0)]
    as "a new stack in the bags: the entry holds no worn place"
  let made = in_bag(guid: 500, item2_id: 13_176, index: 1, count: 1)
  let #(held, held_credits, _, effects) =
    vendor_purchase.answered(
      purchase:,
      items:,
      currencies: credits(total: 100),
      buyback: scene.buyback,
      answer: Bought(amount: 22, made: [made]),
    )
  assert list.contains(held, made) as "the item is held again, in the bags"
  assert currency.credits(currencies: held_credits) == 22
  let assert [_, added, _] = frames(effects:) as "a 0x919, a 0x111 and a 0xBD"
  let assert Ok(item_added.ItemAdded(held_item:)) =
    item_added.decode(added.body)
    as "0x111 decodes"
  assert held_item.reason == 16
    as "Item.CodeEnumItemUpdateReason: Buyback is 16"
  assert held_item.item.location == 1
  assert held_item.item.bag_index == 1
}

pub fn a_buy_back_body_the_client_reader_refuses_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert Error(NotDecoded(undecoded:)) =
    taken_back(scene: Scene(..buying_back(buyback_id: 2), body: <<1, 2, 3>>))
    as "opcode.0xbb: the body is one 32-bit id; three bytes are no message"
  assert undecoded.message_id == vendor_purchase.buy_back_message_id
  assert client_connection.describe_undecoded(undecoded:) != ""
}

// ---- random stats ----

/// The bytes that give Item2 48169's three entries the fractions 0.0, 0.5 and 0.99 (the
/// 32-bit numbers 0x00000000, 0x80000000 and 0xFD70A3D7 over 2^32), which pick rows 1, 4 and 5
/// of the item's group (`random_stat_test`): the word 0x0100000000050401.
const bracer_entropy = <<
  0x00000000:size(32),
  0x80000000:size(32),
  0xFD70A3D7:size(32),
>>

/// The frame of a 0x111 among the effects, decoded.
fn added_item(effects effects: List(Effect)) -> item_added.ItemAdded {
  let assert [added] =
    list.filter(frames(effects:), fn(frame) {
      frame.message_id == item_added.message_id
    })
    as "one 0x111"
  let assert Ok(item) = item_added.decode(added.body) as "0x111 decodes"
  item
}

/// A buy back returns the item with the word it was sold with: the entry's word is the new
/// stack's, no entropy is asked for, and the 0x111 carries it (`opcode.0xba.random_stats`).
pub fn buying_back_an_item_keeps_its_word_and_draws_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let word = 0x0100000000030201
  let item2_id = fixture_tables.root("Item2", 48_169)
  let scene =
    Scene(
      ..buying_back(buyback_id: 9),
      buyback: Buyback(next_id: 10, entries: [
        BuybackEntry(
          buyback_id: 9,
          item2_id: Item2Id(item2_id),
          quantity: 1,
          currency_type_id: 1,
          amount: 40,
          random_stats: word,
        ),
      ]),
    )
  let purchase = asked_back(scene:)
  assert purchase.make
    == [NewStack(location: 1, bag_index: 0, stack_count: 1, random_stats: word)]
    as "the stack is placed with the word the item was sold with"
  assert vendor_purchase.entropy_needed(
      purchase:,
      tables: character_tables.shared(),
    )
    == 0
    as "a buy back draws no entropy"
  assert vendor_purchase.rolled(
      purchase:,
      tables: character_tables.shared(),
      entropy: <<>>,
    )
    == purchase
    as "and no roll replaces the word"
  let made =
    HeldItem(
      item_guid: 500,
      item2_id: Item2Id(item2_id),
      location: 1,
      bag_index: 0,
      stack_count: 1,
      random_stats: word,
    )
  let #(_, _, _, effects) =
    vendor_purchase.answered(
      purchase:,
      items: [],
      currencies: credits(total: 100),
      buyback: scene.buyback,
      answer: Bought(amount: 60, made: [made]),
    )
  assert added_item(effects:).held_item.item.random_stats == word
    as "opcode.0x111: the item is sent with its word"
}

/// A bought item with random stat entries is made with a roll: Item2 48169 has three kind-2
/// entries, 4 bytes of entropy each, and the bytes of `random_stat_test`'s pick give the word
/// 0x0100000000050401, which the 0x111 carries (`opcode.0x111.shared_item_random_stats`), with
/// the list `list_a` empty.
pub fn buying_a_random_stat_item_rolls_it_and_sends_the_word_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = character_tables.shared()
  let item2_id = fixture_tables.root("Item2", 48_169)
  let scene =
    Scene(
      ..scene(unique_id: 1, quantity: 1),
      vendors: vendor_support.stocking_items(creature_ids: [74_812], items: [
        item2_id,
      ]),
    )
  let purchase = asked(scene:)
  assert vendor_purchase.entropy_needed(purchase:, tables:) == 12
    as "ItemStat 432 has three kind-2 entries, 4 bytes each, for the one stack made"
  let rolled =
    vendor_purchase.rolled(purchase:, tables:, entropy: bracer_entropy)
  assert rolled.make
    == [
      NewStack(
        location: 1,
        bag_index: 0,
        stack_count: 1,
        random_stats: 0x0100000000050401,
      ),
    ]
    as "the stack is made with the rolled word"
  let made =
    HeldItem(
      item_guid: 500,
      item2_id: Item2Id(item2_id),
      location: 1,
      bag_index: 0,
      stack_count: 1,
      random_stats: 0x0100000000050401,
    )
  let #(_, _, _, effects) =
    vendor_purchase.answered(
      purchase: rolled,
      items: [],
      currencies: credits(total: 100_000),
      buyback: held_back(),
      answer: Bought(amount: 0, made: [made]),
    )
  let sent = added_item(effects:).held_item.item
  assert sent.random_stats == 0x0100000000050401
    as "the 0x111 is sent with the word"
  assert sent.list_a == [] as "the item's list is empty"
}

/// An item with no random stat entry is made with no roll: Item2 1375's ItemStat 4 has one
/// kind-1 entry and no kind-2 entry, so no byte is drawn and the word is 0.
pub fn buying_an_item_without_random_stats_draws_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = character_tables.shared()
  let item2_id = fixture_tables.root("Item2", 1375)
  let scene =
    Scene(
      ..scene(unique_id: 1, quantity: 1),
      vendors: vendor_support.stocking_items(creature_ids: [74_812], items: [
        item2_id,
      ]),
    )
  let purchase = asked(scene:)
  assert vendor_purchase.entropy_needed(purchase:, tables:) == 0
    as "no kind-2 entry, no byte"
  let rolled = vendor_purchase.rolled(purchase:, tables:, entropy: <<>>)
  assert rolled == purchase as "nothing is rolled"
  let made =
    HeldItem(
      item_guid: 500,
      item2_id: Item2Id(item2_id),
      location: 1,
      bag_index: 0,
      stack_count: 1,
      random_stats: 0,
    )
  let #(_, _, _, effects) =
    vendor_purchase.answered(
      purchase: rolled,
      items: [],
      currencies: credits(total: 100_000),
      buyback: held_back(),
      answer: Bought(amount: 0, made: [made]),
    )
  assert added_item(effects:).held_item.item.random_stats == 0
    as "the 0x111 word is 0"
}
