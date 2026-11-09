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

import character_support
import character_tables
import game_connection_support as connection_support
import genesis_prime/client_connection
import genesis_prime/game/currency.{type Currencies}
import genesis_prime/game/interaction.{Player}
import genesis_prime/game/player_life.{type Life}
import genesis_prime/game/shown
import genesis_prime/game/vendor
import genesis_prime/game/vendor_purchase.{
  type Effect, type Taken, Asks, Log, NotDecoded, Purchase, Refuse, Refused,
  Send,
}
import genesis_prime/message/currency_changed.{CurrencyChanged}
import genesis_prime/message/item_added
import genesis_prime/message/item_count_changed.{ItemCountChanged}
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
  currency.with_credits(
    currencies: currency.from_held(held: []),
    credits: total,
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
    logged: set.Set(String),
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
    logged: set.new(),
  )
}

fn taken(scene scene: Scene) -> Result(Taken, vendor_purchase.Refusal) {
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
    vendors: vendor_support.stocking(creature_ids: [74_812]),
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
      unit_id: vendor_support.walker_unit,
      item2_id: Item2Id(14_838),
      items_bought: 1,
      cost: 67,
      credits_held: 100,
      grow: [],
      make: [NewStack(location: 1, bag_index: 0, stack_count: 1)],
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
      credits_held: 100,
      cost: 67,
      grow: [],
      make: [NewStack(location: 1, bag_index: 0, stack_count: 1)],
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
  assert purchase.make == [NewStack(location: 1, bag_index: 0, stack_count: 15)]
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
  assert purchase.make == [NewStack(location: 1, bag_index: 0, stack_count: 3)]
    as "the rest goes to the lowest empty slot"
  // A buy larger than a stack limit makes stacks of the limit, lowest slot first, the
  // last holding the rest: 120 items into an empty inventory is 50, 50 and 20.
  let large = asked(scene: scene(unique_id: position_14838, quantity: 120))
  assert large.make
    == [
      NewStack(location: 1, bag_index: 0, stack_count: 50),
      NewStack(location: 1, bag_index: 1, stack_count: 50),
      NewStack(location: 1, bag_index: 2, stack_count: 20),
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
  let #(held, held_credits, effects) =
    vendor_purchase.answered(
      purchase:,
      items:,
      currencies: credits(total: 1000),
      answer: Bought(credits: 665, made: [made]),
    )
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
      let #(held, held_credits, effects) =
        vendor_purchase.answered(
          purchase:,
          items:,
          currencies: credits(total: 1000),
          answer:,
        )
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
