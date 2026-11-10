//// The player's sale to the open vendor: the client's 0x0166 (one stack, or part of one)
//// and 0x0167 (all junk), a feature of the game connection's rule
//// (genesis_prime/game/connection) taken from inside 0x038C with the player in the world.
//// The sequence is genesis_prime/game/connection/vendor_sale's.
////
//// ```
//// 0x166 {place, quantity} | 0x167 {} ─▶ take(request, items, currencies, opened, ...)
////                                       ├─ refused ─▶ Refused([Log, Refuse(code)])   nothing asked, nothing changed
////                                       └─ accepted ─▶ Asks(sale) ─▶ the connection asks the store (request(..))
//// the store's answer ─▶ answered(sale, items, currencies, buyback, answer)
////                       Sold(amount):    items, the currency paid and buyback list updated; 0x919, then per stack 0x148 / 0x17F and 0xBA
////                       ItemsNotSaved:   Warning, 0x106 5, nothing changed
////                       SaveRefused(c):  Error naming c, 0x106 5, nothing changed
//// the connection then ─▶ inventory.regeared: a changed worn set sends 0x933, LookChanged and 0x93a
//// ```
////
//// - **The price** is what the client's window shows (`opcode.0x166`, `0x14041bcc0.formula`):
////   per item `item_price.paid(sell_price, vendor sell multiplier)`, and the sale pays that
////   times the quantity, in the price's one currency. The base is the Item2's one SellToVendor
////   amount in its currency when either of its SellToVendor currency type columns is set,
////   else the computed buy price times GameFormula 1026 (0.15) in credits, at least 1
////   (`0x14040d160`; `item_price.sell_price`). A credit price is scaled by the vendor's sell
////   multiplier, a price in another currency is paid as the row gives it.
//// - **The checks, in the order of the client's CheckVendorSell** (`0x1403d3a60`, with
////   `0x1403d6a10` for the item), each a 0x106 with its code
////   (`GameLib.CodeEnumGenericError`); the first that fails answers:
////   1. a body the client's reader refuses ends the connection (`NotDecoded`)
////   2. no vendor window is open on the connection: 16 Vendor_NotAVendor, logged
////   3. the player is dead: 2 PlayerBusy, logged
////   4. the window's own checks, the unit gone from the picture, not a creature, without
////      stock, Hostile: 59, 16, 16 or 62, logged (`interaction.vendor_opened` with no
////      window reach: the sale's only range is the last check); the vendor dead is 23
////   5. the quantity is 0: 24 Vendor_NoQuantity
////   6. no held item at the place: 18 Vendor_BadItemRec, logged (the client sends nothing then)
////   7. the quantity is over the stack's count, a count of 0 reading as 1: 19
////   8. the item does not stack and the quantity is over 1: 11 Vendor_StackSize
////   9. a bank place (location 2 or 3): 23
////   10. a worn bag, location 0 with the bag's joined flag: 25 Vendor_BagIsNotEmpty, logged
////       (a worn item that is not a bag is sold: `0x1403d6a10` has no check for it)
////   11. the item is not sellable (`item_property.sellable`) or its shown price is 0: 23
////   12. the vendor is beyond 6.0 between the two edges, the sale's own range
////       (`opcode.0x166`): 17 Vendor_TooFar, logged
////   Then the refusal the client has no check for, 23 and logged, runs after all of the
////   above: a location the client has no check for (4 and up), which no open issue
////   builds. The logged cases
////   are a modified or stale client, or a gap this server has: each reason is a warning
////   the first time on the connection and a debug line after, and the connection goes on,
////   as the buy's cases do. The client's checks for the vendor's crowd-control states
////   (60, 61) are not modelled.
//// - **Junk** (0x167) sells every held item of Item2Category 94
////   (`lua.Item.CodeEnumItem2Category.Junk`) in the usable inventory that passes check 11
////   and is priced in credits, whole, in bag-index order, in one statement; the others stay.
////   A body that is not empty ends the connection. With nothing to sell nothing is sent.
////   The checks 2 to 4 and 12 apply to it.
//// - **What the sale and the buy share** is genesis_prime/game/vendor_trade's: the window
////   open and the player and vendor alive (the codes differ: 2 and 23 here, 57 and 16 in
////   the buy), the logged refusal, and the store's failed answers.
//// - **The cap** is the currency's (`currency.cap`, the client's GetCurrencyCap): the new total
////   is clamped to it and the excess is lost; a total already at the cap stays there and
////   the sale goes through (`currency.added`). A buyback entry carries the amount the sale
////   paid for its stack, in the sale's currency, before the clamp.
//// - **The store's answer** decides the reply, so storage and the client agree after it:
////   `ItemsNotSaved` and `SaveRefused` leave the items, currencies and buyback list as they were
////   and answer 0x106 code 5 DbFailure. A store that is unavailable, not running or past its
////   deadline ends the connection with reason 8, which the connection decides.
//// - **The answer's frames**: 0x919 with the currency's kind (type - 1) and the new total
////   once, then for each stack sold 0x148 (whole) or 0x17F (part) with the reason 7
////   (Vendor), which makes the client show "Sold <item>" (`lua.Vendor.respond_alerts`), and
////   a 0xBA that adds the entry to the buyback list (`opcode.0xba.price`), naming the
////   currency, the entry's id `buyback.next_id` and up. A worn item sold changes the worn
////   set, which the connection's `inventory.regeared` sends on.
//// - **The list** is `Entered.buyback`, oldest first, each entry with the id it was added
////   with: a buy back (genesis_prime/game/vendor_purchase) takes one off, a vendor window
////   opening sends the whole of it (0xBC), and the Holocrypt's join keeps it
////   (`world_entry.Joining`). It lives in the connection: a play starts it empty.
////
//// | Point | What happens |
//// |---|---|
//// | the held item's Item2 row, or a table row its price reads, is missing | the connection ends (`NoItemRow`) |
//// | GameFormula 1026 has no row | the load fails (`requirements`) |
//// | the item's Item2 row has an amount in both sell slots | the connection ends (`NoItemRow`) |
//// | the store changes nothing or refuses a place | 0x106 5, a log line, items, currencies and buyback as before |
//// | the connection ends while the store works | the store finishes or rolls back; the next login loads whichever |

import genesis_prime/client_connection
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/currency.{type Currencies}
import genesis_prime/game/interaction
import genesis_prime/game/inventory
import genesis_prime/game/item_price
import genesis_prime/game/item_property
import genesis_prime/game/player_life.{type Life}
import genesis_prime/game/shown.{type Picture}
import genesis_prime/game/vendor
import genesis_prime/game/vendor_trade.{
  type Effect, type Refusal, Declined, NoItemRow, NotDecoded, Refuse, Send,
}
import genesis_prime/game/world_entry.{
  type Buyback, type BuybackEntry, Buyback, BuybackEntry,
}
import genesis_prime/message/buyback_added
import genesis_prime/message/buyback_entry
import genesis_prime/message/float32
import genesis_prime/message/item_place.{type ItemPlace}
import genesis_prime/message/vendor_sale as vendor_sale_message
import genesis_prime/message/vendor_sell_junk as vendor_sell_junk_message
import genesis_prime/store.{
  type AccountId, type CharacterId, type HeldItem, type ItemsAnswer,
  type SessionEpoch, HeldItem, ItemsNotSaved, SaveRefused, Sold,
}
import genesis_prime/table/id.{type Item2Id, Item2Id}
import genesis_prime/table/item2
import genesis_prime/table/loader/formula_requirement
import genesis_prime/table/loader/store as table_store
import gleam/bool
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}
import gleam/string

/// The id of the message that sells one stack or part of one.
pub const sale_message_id = vendor_sale_message.message_id

/// The id of the message that sells all junk.
pub const junk_message_id = vendor_sell_junk_message.message_id

/// A sale message the client sent, with its body.
pub type Request {
  /// The client's 0x0166: `quantity` items of the stack at a place.
  SellStack(body: BitArray)
  /// The client's 0x0167: every junk stack.
  SellJunk(body: BitArray)
}

/// One stack a sale sells from: the held stack (`item_guid`, its Item2, the location it is
/// held at and the count it is held with), how many of its items are sold, and what the vendor
/// pays for them in the sale's currency, before the cap.
pub type SoldItem {
  SoldItem(
    item_guid: Int,
    item2_id: Item2Id,
    location: Int,
    held_count: Int,
    sold_count: Int,
    paid: Int,
  )
}

/// A sale the rule accepted and the store is asked for: the unit it was made at, each stack
/// sold in bag-index order (at least one, `first` and `rest`), the currency the stacks are
/// paid in, what is held of it when the sale was taken (which fences the store's statement)
/// and what is held of it after the sale, capped.
pub type Sale {
  Sale(
    unit_id: Int,
    first: SoldItem,
    rest: List(SoldItem),
    currency_type_id: Int,
    held: Int,
    after: Int,
  )
}

/// What the rule makes of a sale message the client sent, with the log keys met so far.
pub type Taken {
  /// The sale breaks a check, or has nothing to sell: the effects answer it and nothing is
  /// asked or changed.
  Refused(effects: List(Effect), logged: Set(String))
  /// The sale passes every check: the store is asked for it.
  Asks(sale: Sale, logged: Set(String))
}

/// What a request asks to sell, once its body is read.
type Wanted {
  /// `quantity` of the stack at a place.
  Part(place: ItemPlace, quantity: Int)
  /// Every junk stack.
  Junk
}

/// The stacks a request sells, or the answer that stops it.
type Picked {
  /// The stacks the client's own checks let through, which may be none, and the one
  /// currency they are paid in.
  Picked(currency_type_id: Int, stacks: List(SoldItem))
  /// A sale the client's checks before the range refuse, with their code.
  Stopped(taken: Taken)
  /// A sale at a location the client's checks let through but the server holds no item at:
  /// it is refused with 23 once the range check has passed, since the client's checks come
  /// first.
  Withheld(reason: String, text: String)
}

/// How the sale words and codes the refusals of its window and player: a dead player is 2
/// (PlayerBusy) and a dead vendor 23 (`opcode.0x166`), and the window's reach does not apply,
/// as the sale's own range is checked last.
const trade =
  vendor_trade.Trade(
    key: "sell",
    verb: "sells to",
    refused: "the sale",
    dead_player_code: 2,
    dead_vendor_code: 23,
    reach: interaction.SkipReach,
  )

/// The client's code for a place that holds no item (Vendor_BadItemRec).
const bad_item_rec = 18

/// The client's code for a worn bag (Vendor_BagIsNotEmpty).
const bag_is_not_empty = 25

/// The client's code for a sale of a quantity of 0 (Vendor_NoQuantity).
const no_quantity = 24

/// The client's code for a quantity over the stack's count.
const over_the_count = 19

/// The client's code for more than one of an item that does not stack (Vendor_StackSize).
const stack_size = 11

/// The client's code for an item the vendor will not buy, a bank place and a dead vendor,
/// and the server's for a location it holds no item at.
const wont_buy = 23

/// The client's code for a vendor beyond the sale's range (Vendor_TooFar).
const too_far = 17

/// The reason a vendor sale's items are shown for (Item.CodeEnumItemUpdateReason 7,
/// Vendor): the client shows "Sold <item>".
const vendor_reason = 7

/// The worn items and bags are in this location (`inventory`).
const worn_location = 0

/// The usable slots of the inventory are in this location (`inventory`).
const inventory_location = 1

/// The bank's locations (`0x1403d6a10`: 2 and 3 are refused with 23).
const bank_location = 2

const bank_vault_location = 3

/// Item2Category Junk (`lua.Item.CodeEnumItem2Category`).
const junk_category = 94

/// The gap between the two edges the sale's sender allows (`opcode.0x166`: 0 to 6.0).
const sale_range = 6.0

/// What the client's sale message is answered with: a refusal with the code of the first
/// check it breaks, or the store's ask, or the refusal for a body the client's reader
/// refuses.
pub fn take(
  request request: Request,
  items items: List(HeldItem),
  currencies currencies: Currencies,
  opened opened: Option(vendor.Opened),
  life life: Life,
  player player: interaction.Player,
  picture picture: Picture,
  tables tables: table_store.Tables,
  vendors vendors: vendor.Vendors,
  now_ms now_ms: Int,
  logged logged: Set(String),
) -> Result(Taken, Refusal) {
  use wanted <- result.try(wanted(request:))
  let label = label(request:)
  case
    vendor_trade.opened(
      trade:,
      label:,
      opened:,
      life:,
      player:,
      picture:,
      tables:,
      vendors:,
      now_ms:,
      logged:,
    )
  {
    Error(Declined(effects:, logged:)) -> Ok(Refused(effects:, logged:))
    Ok(window) ->
      sold_to(
        wanted:,
        label:,
        window:,
        items:,
        currencies:,
        player:,
        picture:,
        tables:,
        now_ms:,
        logged:,
      )
  }
}

/// The request's body read, or the refusal for one the client's reader refuses.
fn wanted(request request: Request) -> Result(Wanted, Refusal) {
  case request {
    SellStack(body:) ->
      vendor_sale_message.decode(body)
      |> client_connection.decoded(message_id: sale_message_id)
      |> result.map(fn(sale) {
        Part(place: sale.place, quantity: sale.quantity)
      })
      |> result.map_error(NotDecoded)
    SellJunk(body:) ->
      vendor_sell_junk_message.decode(body)
      |> client_connection.decoded(message_id: junk_message_id)
      |> result.replace(Junk)
      |> result.map_error(NotDecoded)
  }
}

/// The message a request is, for the log.
fn label(request request: Request) -> String {
  case request {
    SellStack(..) -> "0x0166"
    SellJunk(..) -> "0x0167"
  }
}

/// The sale of the open vendor's window: the stacks the request sells, the vendor in the
/// sale's range and the credits they bring.
fn sold_to(
  wanted wanted: Wanted,
  label label: String,
  window window: vendor.Opened,
  items items: List(HeldItem),
  currencies currencies: Currencies,
  player player: interaction.Player,
  picture picture: Picture,
  tables tables: table_store.Tables,
  now_ms now_ms: Int,
  logged logged: Set(String),
) -> Result(Taken, Refusal) {
  use picked <- result.try(case wanted {
    Part(place:, quantity:) ->
      part(
        place:,
        quantity:,
        label:,
        vendor: window.vendor,
        items:,
        tables:,
        logged:,
      )
    Junk -> junk(vendor: window.vendor, items:, tables:)
  })
  case picked {
    Stopped(taken:) -> Ok(taken)
    Picked(stacks: [], ..) -> Ok(Refused(effects: [], logged:))
    Picked(currency_type_id:, stacks: [first, ..rest]) ->
      Ok(case in_range(window:, player:, picture:, tables:, now_ms:) {
        False -> beyond_range(label:, unit_id: window.unit_id, logged:)
        True ->
          asked(
            unit_id: window.unit_id,
            currency_type_id:,
            first:,
            rest:,
            currencies:,
            tables:,
            logged:,
          )
      })
    Withheld(reason:, text:) ->
      Ok(case in_range(window:, player:, picture:, tables:, now_ms:) {
        False -> beyond_range(label:, unit_id: window.unit_id, logged:)
        True -> refused_logged(reason:, text:, code: wont_buy, logged:)
      })
  }
}

/// Whether the vendor is within the sale's range of the player, between the two edges: the
/// last check of the client's (`0x1403d3a60`).
fn in_range(
  window window: vendor.Opened,
  player player: interaction.Player,
  picture picture: Picture,
  tables tables: table_store.Tables,
  now_ms now_ms: Int,
) -> Bool {
  let assert Ok(shown.ShownCreature(path:, hit_radius:, ..)) =
    dict.get(picture, window.unit_id)
    as "vendor_trade.opened passed, so the vendor's unit is a shown creature"
  interaction.within(
    player:,
    tables:,
    path:,
    creature_radius: hit_radius,
    now_ms:,
    range: sale_range,
  )
}

/// The answer for a vendor beyond the sale's range.
fn beyond_range(
  label label: String,
  unit_id unit_id: Int,
  logged logged: Set(String),
) -> Taken {
  refused_logged(
    reason: "beyond the sale's range",
    text: label
      <> " sells to unit "
      <> int.to_string(unit_id)
      <> ", which is more than the sale's "
      <> float.to_string(sale_range)
      <> " from the player between the two edges: the client would refuse the sale with code "
      <> int.to_string(too_far)
      <> ", so the server answers that",
    code: too_far,
    logged:,
  )
}

/// The sale the store is asked for: the stacks picked, the amount held of their currency
/// and the total they come to once the price is paid and the cap applied.
fn asked(
  unit_id unit_id: Int,
  currency_type_id currency_type_id: Int,
  first first: SoldItem,
  rest rest: List(SoldItem),
  currencies currencies: Currencies,
  tables tables: table_store.Tables,
  logged logged: Set(String),
) -> Taken {
  let held = currency.held(currencies:, currency_type_id:)
  let paid =
    list.fold([first, ..rest], 0, fn(total, stack) { total + stack.paid })
  Asks(
    sale: Sale(
      unit_id:,
      first:,
      rest:,
      currency_type_id:,
      held:,
      after: currency.added(
        held:,
        paid:,
        cap: currency.cap(tables:, currency_type_id:),
      ),
    ),
    logged:,
  )
}

/// The stack at a place, sold in part or whole, or the answer for the first check it breaks,
/// in the order of the client's (`0x1403d3a60`, `0x1403d6a10`).
fn part(
  place place: ItemPlace,
  quantity quantity: Int,
  label label: String,
  vendor stock: vendor.Vendor,
  items items: List(HeldItem),
  tables tables: table_store.Tables,
  logged logged: Set(String),
) -> Result(Picked, Refusal) {
  use <- bool.guard(quantity == 0, Ok(stopped(code: no_quantity, logged:)))
  case
    list.find(items, fn(item) {
      item.location == place.location && item.bag_index == place.bag_index
    })
  {
    Error(Nil) ->
      Ok(stopped_logged(
        reason: "no item",
        text: label
          <> " sells from location "
          <> int.to_string(place.location)
          <> " bag index "
          <> int.to_string(place.bag_index)
          <> ", where the player holds no item: the client sends nothing for an empty place, so the server answers "
          <> int.to_string(bad_item_rec),
        code: bad_item_rec,
        logged:,
      ))
    Ok(item) ->
      checked(item:, quantity:, label:, vendor: stock, tables:, logged:)
  }
}

/// The stack at a place, sold for `quantity`, or the answer for the first of the count,
/// stacking, bank, bag, sellable and price checks it breaks. A stack at a location the
/// client's checks let through but the server holds no item at is `Withheld`.
fn checked(
  item item: HeldItem,
  quantity quantity: Int,
  label label: String,
  vendor stock: vendor.Vendor,
  tables tables: table_store.Tables,
  logged logged: Set(String),
) -> Result(Picked, Refusal) {
  let Item2Id(raw_id) = item.item2_id
  let no_row = NoItemRow(item2_id: item.item2_id)
  // A held count of 0 reads as 1 (`0x1403d6a10`).
  use <- bool.guard(
    quantity > int.max(1, item.stack_count),
    Ok(stopped(code: over_the_count, logged:)),
  )
  use limit <- result.try(
    item_property.stack_limit(tables:, item2_id: raw_id)
    |> result.replace_error(no_row),
  )
  use <- bool.guard(
    option.is_none(limit) && quantity > 1,
    Ok(stopped(code: stack_size, logged:)),
  )
  use <- bool.guard(
    item.location == bank_location || item.location == bank_vault_location,
    Ok(stopped(code: wont_buy, logged:)),
  )
  use bag <- result.try(
    item_property.bag_size(tables:, item2_id: raw_id)
    |> result.replace_error(no_row),
  )
  use <- bool.guard(
    item.location == worn_location && option.is_some(bag),
    Ok(stopped_logged(
      reason: "worn bag",
      text: label
        <> " sells the worn bag Item2 "
        <> int.to_string(raw_id)
        <> ": the client refuses a worn bag with code "
        <> int.to_string(bag_is_not_empty)
        <> ", so the server answers that",
      code: bag_is_not_empty,
      logged:,
    )),
  )
  use sellable <- result.try(
    item_property.sellable(tables:, item2_id: raw_id)
    |> result.replace_error(no_row),
  )
  use <- bool.guard(!sellable, Ok(stopped(code: wont_buy, logged:)))
  use price <- result.try(each_pays(item:, vendor: stock, tables:))
  case item.location {
    _ if price.amount == 0 -> Ok(stopped(code: wont_buy, logged:))
    location if location != worn_location && location != inventory_location ->
      Ok(Withheld(
        reason: "unknown location",
        text: label
          <> " sells from location "
          <> int.to_string(location)
          <> ", which the client's checks do not name and the server holds no item at; no open issue builds it, so the server answers "
          <> int.to_string(wont_buy),
      ))
    location ->
      Ok(
        Picked(currency_type_id: price.currency_type_id, stacks: [
          SoldItem(
            item_guid: item.item_guid,
            item2_id: item.item2_id,
            location:,
            held_count: item.stack_count,
            sold_count: quantity,
            paid: price.amount * quantity,
          ),
        ]),
      )
  }
}

/// What the vendor pays for one of the item, in the currency of its price.
fn each_pays(
  item item: HeldItem,
  vendor stock: vendor.Vendor,
  tables tables: table_store.Tables,
) -> Result(item_price.SellPrice, Refusal) {
  item_price.sell_price(tables:, item2_id: item.item2_id)
  |> result.replace_error(NoItemRow(item2_id: item.item2_id))
  |> result.map(fn(price) {
    item_price.paid(price:, multiplier: stock.sell_multiplier)
  })
}

/// Every junk stack of the usable inventory the vendor pays for, whole, in bag-index order.
fn junk(
  vendor stock: vendor.Vendor,
  items items: List(HeldItem),
  tables tables: table_store.Tables,
) -> Result(Picked, Refusal) {
  items
  |> list.filter(fn(item) { item.location == inventory_location })
  |> list.sort(fn(a, b) { int.compare(a.bag_index, b.bag_index) })
  |> list.try_map(fn(item) { junk_stack(item:, vendor: stock, tables:) })
  |> result.map(fn(stacks) {
    Picked(
      currency_type_id: currency.credits_type,
      stacks: option.values(stacks),
    )
  })
}

/// The whole stack as a sold stack when it is junk, sellable and paid for.
fn junk_stack(
  item item: HeldItem,
  vendor stock: vendor.Vendor,
  tables tables: table_store.Tables,
) -> Result(Option(SoldItem), Refusal) {
  let Item2Id(raw_id) = item.item2_id
  let no_row = NoItemRow(item2_id: item.item2_id)
  use row <- result.try(
    item2.get(tables:, id: item.item2_id) |> result.replace_error(no_row),
  )
  use <- bool.guard(row.item2_category_id != junk_category, Ok(None))
  use sellable <- result.try(
    item_property.sellable(tables:, item2_id: raw_id)
    |> result.replace_error(no_row),
  )
  use <- bool.guard(!sellable, Ok(None))
  use price <- result.try(each_pays(item:, vendor: stock, tables:))
  use <- bool.guard(
    price.currency_type_id != currency.credits_type || price.amount == 0,
    Ok(None),
  )
  let count = int.max(1, item.stack_count)
  Ok(
    Some(SoldItem(
      item_guid: item.item_guid,
      item2_id: item.item2_id,
      location: item.location,
      held_count: item.stack_count,
      sold_count: count,
      paid: price.amount * count,
    )),
  )
}

/// A refusal of a sale by the client's code, with nothing to log.
fn stopped(code code: Int, logged logged: Set(String)) -> Picked {
  Stopped(taken: Refused(effects: [Refuse(code:)], logged:))
}

/// A refusal of a sale that a client following its own code never sends, or that this
/// server cannot yet make, with a line to log once for each reason on the connection.
fn stopped_logged(
  reason reason: String,
  text text: String,
  code code: Int,
  logged logged: Set(String),
) -> Picked {
  Stopped(taken: refused_logged(reason:, text:, code:, logged:))
}

fn refused_logged(
  reason reason: String,
  text text: String,
  code code: Int,
  logged logged: Set(String),
) -> Taken {
  let Declined(effects:, logged:) =
    vendor_trade.refused_logged(trade:, reason:, text:, code:, logged:)
  Refused(effects:, logged:)
}

/// The store's request for the sale: the character's currency and items in one change.
pub fn request(
  sale sale: Sale,
  account_id account_id: AccountId,
  character_id character_id: CharacterId,
  session_epoch session_epoch: SessionEpoch,
) -> store.Request {
  store.Items(store.SellToVendor(
    account_id:,
    character_id:,
    session_epoch:,
    currency_type_id: sale.currency_type_id,
    held: sale.held,
    after: sale.after,
    sold: list_sold(sale:),
  ))
}

/// What the store's answer leaves: the items, the amounts held, the buyback list and the
/// effects, in order.
pub fn answered(
  sale sale: Sale,
  items items: List(HeldItem),
  currencies currencies: Currencies,
  buyback buyback: Buyback,
  answer answer: ItemsAnswer,
) -> #(List(HeldItem), Currencies, Buyback, List(Effect)) {
  case answer {
    Sold(amount:) -> {
      let stacks = [sale.first, ..sale.rest]
      let entries =
        list.index_map(stacks, fn(stack, position) {
          BuybackEntry(
            buyback_id: buyback.next_id + position,
            item2_id: stack.item2_id,
            quantity: stack.sold_count,
            currency_type_id: sale.currency_type_id,
            amount: stack.paid,
          )
        })
      #(
        sold_from(items:, stacks:),
        currency.with_amount(
          currencies:,
          currency_type_id: sale.currency_type_id,
          total: amount,
        ),
        Buyback(
          next_id: buyback.next_id + list.length(stacks),
          entries: list.append(buyback.entries, entries),
        ),
        [
          Send(currency.changed_frame(
            currency_type_id: sale.currency_type_id,
            total: amount,
          )),
          ..list.flat_map(list.zip(stacks, entries), fn(pair) {
            let #(stack, entry) = pair
            [Send(stack_frame(stack:)), Send(buyback_frame(entry:))]
          })
        ],
      )
    }
    ItemsNotSaved -> #(
      items,
      currencies,
      buyback,
      vendor_trade.not_saved(what: not_sold(sale:)),
    )
    SaveRefused(constraint:) -> #(
      items,
      currencies,
      buyback,
      vendor_trade.save_refused(what: not_sold(sale:), constraint:),
    )
    store.ItemsSaved
    | store.ItemMade(..)
    | store.Bought(..)
    | store.TurnedIn(..) ->
      panic as "the store answers a sale with Sold, ItemsNotSaved or SaveRefused"
  }
}

/// Whether the sale takes the whole stack: it sells every item the stack holds.
fn whole(stack stack: SoldItem) -> Bool {
  stack.sold_count >= stack.held_count
}

/// The held items with each sold stack taken away, or lowered by the part sold.
fn sold_from(
  items items: List(HeldItem),
  stacks stacks: List(SoldItem),
) -> List(HeldItem) {
  list.filter_map(items, fn(item) {
    case list.find(stacks, fn(stack) { stack.item_guid == item.item_guid }) {
      Error(Nil) -> Ok(item)
      Ok(stack) ->
        case whole(stack:) {
          True -> Error(Nil)
          False ->
            Ok(
              HeldItem(..item, stack_count: stack.held_count - stack.sold_count),
            )
        }
    }
  })
}

/// The frame that takes a whole stack away, or gives a part-sold stack its count, shown for
/// the reason Vendor.
fn stack_frame(stack stack: SoldItem) -> Frame {
  case whole(stack:) {
    True ->
      inventory.item_removed_frame(guid: stack.item_guid, reason: vendor_reason)
    False ->
      inventory.count_changed_frame(
        guid: stack.item_guid,
        count: stack.held_count - stack.sold_count,
        reason: vendor_reason,
      )
  }
}

/// The 0xBA that adds the entry to the client's Buyback list (`opcode.0xba.price`).
fn buyback_frame(entry entry: BuybackEntry) -> Frame {
  let assert Ok(body) =
    buyback_added.encode(
      buyback_added.BuybackAdded(entry: buyback_entry_message(entry:)),
    )
    as "an entry whose fields are held values of their widths is written"
  frame.Frame(message_id: buyback_added.message_id, body:)
}

/// An entry of the buyback list as the client's 0xBA and 0xBC carry it: the amount paid is
/// its first amount, in its first currency type, the five multipliers are 1.0
/// (`opcode.0xba.random_stats`), and every other field the client's code gives no use is 0
/// (`opcode.0xba.price`).
pub fn buyback_entry_message(
  entry entry: BuybackEntry,
) -> buyback_entry.BuybackEntry {
  let Item2Id(item_id) = entry.item2_id
  // 1.0 leaves a fixed-budget stat as it is: the client multiplies each such stat point by
  // its multiplier (`opcode.0xba.random_stats`).
  let unchanged_multiplier = float32.to_bits(1.0)
  buyback_entry.BuybackEntry(
    buyback_id: entry.buyback_id,
    item_id:,
    quantity: entry.quantity,
    field_4: 0,
    field_5: 0,
    field_6: 0,
    field_7: 0,
    field_8: 0,
    multiplier_1: unchanged_multiplier,
    multiplier_2: unchanged_multiplier,
    multiplier_3: unchanged_multiplier,
    multiplier_4: unchanged_multiplier,
    multiplier_5: unchanged_multiplier,
    field_14: 0,
    field_15: 0,
    field_16: 0,
    field_17: 0,
    field_18: 0,
    field_19: 0,
    field_20: 0,
    field_21: 0,
    amount_1: entry.amount,
    amount_2: 0,
    currency_type_1: entry.currency_type_id,
    currency_type_2: 0,
    field_26: 0,
  )
}

/// A sentence that says which sale was not saved, for the log.
pub fn not_sold(sale sale: Sale) -> String {
  let stacks =
    [sale.first, ..sale.rest]
    |> list.map(fn(stack) {
      int.to_string(stack.sold_count)
      <> " of Item2 "
      <> int.to_string({ stack.item2_id }.value)
    })
    |> string.join(", ")
  "the sale of "
  <> stacks
  <> " for "
  <> int.to_string(sale.after - sale.held)
  <> " of currency type "
  <> int.to_string(sale.currency_type_id)
  <> " was not saved"
}

/// What the tables must hold at load for a sale: the sell fraction. The currencies' caps are
/// `currency.requirements`.
pub fn requirements() -> List(table_store.Requirement) {
  [
    formula_requirement.row_present(
      from_table: "the server's sell price fraction",
      id: item_price.sell_fraction_formula,
    ),
  ]
}

/// The stacks of the sale as the store's request names them.
fn list_sold(sale sale: Sale) -> List(store.SoldStack) {
  list.map([sale.first, ..sale.rest], fn(stack) {
    store.SoldStack(
      item_guid: stack.item_guid,
      location: stack.location,
      held_count: stack.held_count,
      sold_count: stack.sold_count,
    )
  })
}
