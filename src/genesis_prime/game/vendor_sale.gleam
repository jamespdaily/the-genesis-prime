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
////                       Sold(total):     items, credits and buyback list updated; 0x919, then per stack 0x148 / 0x17F and 0xBA
////                       ItemsNotSaved:   Warning, 0x106 5, nothing changed
////                       SaveRefused(c):  Error naming c, 0x106 5, nothing changed
//// ```
////
//// - **The price** is what the client's window shows (`opcode.0x166`, `0x14041bcc0.formula`):
////   per item `item_price.shown(base, vendor sell multiplier)`, and the sale pays that
////   times the quantity. The base is the Item2's SellToVendor credit amount when either of
////   its currency type columns is set, else the computed buy price times GameFormula 1026
////   (0.15), at least 1. A row that needs a currency other than credits is refused with 23
////   and a log line: worn items and those prices are #650's.
//// - **The checks, in order**, each a 0x106 with its code (`GameLib.CodeEnumGenericError`):
////   1. a body the client's reader refuses ends the connection (`NotDecoded`)
////   2. no vendor window is open on the connection: 16 Vendor_NotAVendor, logged
////   3. the player is dead: 2 PlayerBusy (`opcode.0x166`), logged
////   4. the open vendor's unit is gone from the picture, not a creature, without stock,
////      dead, beyond the window's reach or Hostile: 59, 16, 16, 23, 17 or 62, logged
////      (`interaction.vendor_opened`; the sale's code for a dead vendor is 23)
////   5. no held item at the place: 18 Vendor_BadItemRec, logged (the client sends nothing then)
////   6. a worn bag, location 0 with the bag's joined flag: 25 Vendor_BagIsNotEmpty
////      (`0x1403d6a10`), logged
////   7. a place that is not the usable inventory (location 1): 23; worn items (location 0)
////      are #650's and logged, the bank's (2 and 3) are the client's own 23
////   8. the quantity is 0: 24 Vendor_NoQuantity
////   9. the quantity is over the stack's count, a count of 0 reading as 1: 19
////   10. the item does not stack and the quantity is over 1: 11 Vendor_StackSize
////   11. the item is not sellable (`item_property.sellable`) or its shown price is 0: 23
////   12. the item is priced in a currency other than credits: 23, logged; #650's
////   13. the vendor is beyond 6.0 between the two edges, the sale's own range
////       (`opcode.0x166`; the window's reach is 9.0): 17 Vendor_TooFar, logged
////   The logged cases are a modified or stale client, or a gap this server has: each
////   reason is a warning the first time on the connection and a debug line after, and the
////   connection goes on, as the buy's cases do.
//// - **Junk** (0x167) sells every held item of Item2Category 94
////   (`lua.Item.CodeEnumItem2Category.Junk`) in the usable inventory that passes cases 11
////   and 12, whole, in bag-index order, in one statement; the others stay. A body that is
////   not empty ends the connection. With nothing to sell nothing is sent. The checks of
////   cases 2 to 4 and 13 apply to it.
//// - **The credit cap** is GameFormula 1115, 500,000 (`GetCurrencyCap.entitlement_14`): the
////   new total is clamped to it and the excess is lost; a total already at the cap stays
////   there and the sale goes through. A buyback entry carries the credits the sale paid for
////   its stack, before the clamp.
//// - **The store's answer** decides the reply, so storage and the client agree after it:
////   `ItemsNotSaved` and `SaveRefused` leave the items, credits and buyback list as they were
////   and answer 0x106 code 5 DbFailure. A store that is unavailable, not running or past its
////   deadline ends the connection with reason 8, which the connection decides.
//// - **The answer's frames**: 0x919 kind 0 with the new total once, then for each stack sold
////   0x148 (whole) or 0x17F (part) with the reason 7 (Vendor), which makes the client show
////   "Sold <item>" (`lua.Vendor.respond_alerts`), and a 0xBA that adds the entry to the
////   buyback list (`opcode.0xba.price`), the entry's id `buyback.next_id` and up.
//// - **Gaps**: buy back (0xBB), the list sent when a vendor window opens (0xBC) and the
////   list's lifetime are #651's; the vendor open still sends the empty list.
////
//// | Point | What happens |
//// |---|---|
//// | the held item's Item2 row, or a table row its price reads, is missing | the connection ends (`NoItemRow`) |
//// | GameFormula 1115 or 1026 has no row | the load fails (`requirements`) |
//// | the store changes nothing or refuses a place | 0x106 5, a log line, items, credits and buyback as before |
//// | the connection ends while the store works | the store finishes or rolls back; the next login loads whichever |

import genesis_prime/client_connection.{type Undecoded}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/currency.{type Currencies}
import genesis_prime/game/interaction
import genesis_prime/game/inventory
import genesis_prime/game/item_price
import genesis_prime/game/item_property
import genesis_prime/game/player_life.{type Life}
import genesis_prime/game/shown.{type Picture}
import genesis_prime/game/vendor
import genesis_prime/game/world_entry.{
  type Buyback, type BuybackEntry, Buyback, BuybackEntry,
}
import genesis_prime/message/buyback_added
import genesis_prime/message/buyback_entry
import genesis_prime/message/item_place.{type ItemPlace}
import genesis_prime/message/vendor_sale as vendor_sale_message
import genesis_prime/message/vendor_sell_junk as vendor_sell_junk_message
import genesis_prime/step.{type LogLevel, LogError, LogWarning}
import genesis_prime/store.{
  type AccountId, type CharacterId, type HeldItem, type ItemsAnswer,
  type SessionEpoch, HeldItem, ItemsNotSaved, SaveRefused, Sold,
}
import genesis_prime/table/game_formula
import genesis_prime/table/id.{type Item2Id, GameFormulaId, Item2Id}
import genesis_prime/table/item2
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

/// What the rule asks the connection to do.
pub type Effect {
  /// Write a frame to the player's client.
  Send(frame: Frame)
  /// Write a 0x106 with the client's code for why the sale is refused.
  Refuse(code: Int)
  /// Write a log line.
  Log(level: LogLevel, text: String)
}

/// A sale message the client sent, with its body.
pub type Request {
  /// The client's 0x0166: `quantity` items of the stack at a place.
  SellStack(body: BitArray)
  /// The client's 0x0167: every junk stack.
  SellJunk(body: BitArray)
}

/// One stack a sale sells from: the held stack (`item_guid`, its Item2 and the count it is
/// held with), how many of its items are sold, and the credits the vendor pays for them,
/// before the credit cap.
pub type SoldItem {
  SoldItem(
    item_guid: Int,
    item2_id: Item2Id,
    held_count: Int,
    sold_count: Int,
    credits: Int,
  )
}

/// A sale the rule accepted and the store is asked for: the unit it was made at, each stack
/// sold in bag-index order (at least one, `first` and `rest`), the credits held when it was
/// taken (which fence the store's statement) and the credits held after it, capped.
pub type Sale {
  Sale(
    unit_id: Int,
    first: SoldItem,
    rest: List(SoldItem),
    credits_held: Int,
    credits_after: Int,
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

/// Why the sale ends the connection with no answer: the client's own code never sends it, or
/// the server's own state is broken.
pub type Refusal {
  /// A body the client's own reader would refuse.
  NotDecoded(undecoded: Undecoded)
  /// A held item whose row, or a row its price reads, the tables lack: the server's own
  /// state is broken, since the item rows require them.
  NoItemRow(item2_id: Item2Id)
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
  Picked(stacks: List(SoldItem))
  Stopped(taken: Taken)
}

/// The client's code for a sale the window is not open for (Vendor_NotAVendor).
const not_a_vendor = 16

/// The client's code for a player who is dead (PlayerBusy).
const player_busy = 2

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

/// The client's code for an item the vendor will not buy, a bank place and a dead vendor.
const wont_buy = 23

/// The client's code for a vendor beyond the sale's range (Vendor_TooFar).
const too_far = 17

/// The client's code for a change that was not saved (DbFailure).
const db_failure = 5

/// The reason a vendor sale's items are shown for (Item.CodeEnumItemUpdateReason 7,
/// Vendor): the client shows "Sold <item>".
const vendor_reason = 7

/// The usable slots of the inventory are in this location (`inventory`).
const inventory_location = 1

/// Item2Category Junk (`lua.Item.CodeEnumItem2Category`).
const junk_category = 94

/// The gap between the two edges the sale's sender allows (`opcode.0x166`: 0 to 6.0).
const sale_range = 6.0

/// The GameFormula row whose dataint0 is the most credits a character holds
/// (`GetCurrencyCap.entitlement_14`).
const credit_cap_formula = 1115

/// The GameFormula row whose datafloat0 is the fraction of the buy price an item sells for
/// (`0x14040bfb0`), read by `item_price.sell_base`.
const sell_fraction_formula = 1026

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
  case opened {
    None ->
      Ok(refused_logged(
        reason: "no window",
        text: label
          <> " sells to a vendor with no vendor window open on the connection: the client sends it only in a vendor interaction, so the server answers "
          <> int.to_string(not_a_vendor),
        code: not_a_vendor,
        logged:,
      ))
    Some(window) ->
      case player_life.state(life:) == player_life.Dead {
        True ->
          Ok(refused_logged(
            reason: "dead",
            text: label
              <> " sells to a vendor while the player is dead: the client sends nothing for a dead player, so the server answers "
              <> int.to_string(player_busy),
            code: player_busy,
            logged:,
          ))
        False ->
          case
            interaction.vendor_opened(
              unit_id: window.unit_id,
              player:,
              picture:,
              tables:,
              vendors:,
              now_ms:,
            )
          {
            Error(refusal) -> Ok(window_refused(label:, refusal:, logged:))
            Ok(stock) ->
              sold_to(
                wanted:,
                label:,
                window: vendor.Opened(..window, vendor: stock),
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
    Picked(stacks: []) -> Ok(Refused(effects: [], logged:))
    Picked(stacks: [first, ..rest]) -> {
      let assert Ok(shown.ShownCreature(path:, hit_radius:, ..)) =
        dict.get(picture, window.unit_id)
        as "interaction.vendor_opened passed, so the vendor's unit is a shown creature"
      case
        interaction.within(
          player:,
          tables:,
          path:,
          creature_radius: hit_radius,
          now_ms:,
          range: sale_range,
        )
      {
        False ->
          Ok(refused_logged(
            reason: "beyond the sale's range",
            text: label
              <> " sells to unit "
              <> int.to_string(window.unit_id)
              <> ", which is more than the sale's "
              <> float.to_string(sale_range)
              <> " from the player between the two edges: the client would refuse the sale with code "
              <> int.to_string(too_far)
              <> ", so the server answers that",
            code: too_far,
            logged:,
          ))
        True ->
          Ok(asked(
            unit_id: window.unit_id,
            first:,
            rest:,
            currencies:,
            tables:,
            logged:,
          ))
      }
    }
  }
}

/// The sale the store is asked for: the stacks picked, the credits held and the total they
/// come to once the price is paid and the cap applied.
fn asked(
  unit_id unit_id: Int,
  first first: SoldItem,
  rest rest: List(SoldItem),
  currencies currencies: Currencies,
  tables tables: table_store.Tables,
  logged logged: Set(String),
) -> Taken {
  let credits_held = currency.credits(currencies:)
  let paid =
    list.fold([first, ..rest], 0, fn(total, stack) { total + stack.credits })
  Asks(
    sale: Sale(
      unit_id:,
      first:,
      rest:,
      credits_held:,
      credits_after: capped(held: credits_held, paid:, cap: credit_cap(tables:)),
    ),
    logged:,
  )
}

/// The answer for a window the vendor's own checks refuse: their code, but a dead vendor is
/// refused with 23, not the window's 16 (the sale's sender).
fn window_refused(
  label label: String,
  refusal refusal: interaction.VendorRefusal,
  logged logged: Set(String),
) -> Taken {
  let code = case refusal.reason {
    "dead" -> wont_buy
    _ -> refusal.code
  }
  refused_logged(
    reason: refusal.reason,
    text: label
      <> " sells to unit "
      <> int.to_string(refusal.unit_id)
      <> ", "
      <> refusal.why
      <> ": the client would refuse the sale with code "
      <> int.to_string(code)
      <> ", so the server answers that",
    code:,
    logged:,
  )
}

/// The credits a character holds most (`GetCurrencyCap.entitlement_14`).
fn credit_cap(tables tables: table_store.Tables) -> Int {
  let assert Ok(row) =
    game_formula.get(tables:, id: GameFormulaId(credit_cap_formula))
    as "GameFormula row 1115 is required at load (requirements)"
  row.dataint0
}

/// The credits held after `paid` is added to `held`: the total stops at the cap, and a
/// total already at the cap stays.
fn capped(held held: Int, paid paid: Int, cap cap: Int) -> Int {
  int.max(held, int.min(cap, held + paid))
}

/// The stack at a place, sold in part or whole, or the answer for the first check it breaks.
fn part(
  place place: ItemPlace,
  quantity quantity: Int,
  label label: String,
  vendor stock: vendor.Vendor,
  items items: List(HeldItem),
  tables tables: table_store.Tables,
  logged logged: Set(String),
) -> Result(Picked, Refusal) {
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
    Ok(item) -> {
      let Item2Id(raw_id) = item.item2_id
      use bag <- result.try(
        item_property.bag_size(tables:, item2_id: raw_id)
        |> result.replace_error(NoItemRow(item2_id: item.item2_id)),
      )
      case item.location, bag {
        0, Some(_) ->
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
          ))
        0, None ->
          Ok(stopped_logged(
            reason: "worn item",
            text: label
              <> " sells the worn Item2 "
              <> int.to_string(raw_id)
              <> ", whose sale is #650's, so the server answers "
              <> int.to_string(wont_buy),
            code: wont_buy,
            logged:,
          ))
        location, _ if location == inventory_location ->
          priced(item:, quantity:, label:, vendor: stock, tables:, logged:)
        _, _ -> Ok(stopped(code: wont_buy, logged:))
      }
    }
  }
}

/// The stack in the usable inventory, sold for `quantity`, or the answer for the first of
/// the quantity, stacking, sellable and price checks it breaks.
fn priced(
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
  use <- bool.guard(quantity == 0, Ok(stopped(code: no_quantity, logged:)))
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
  use sellable <- result.try(
    item_property.sellable(tables:, item2_id: raw_id)
    |> result.replace_error(no_row),
  )
  use <- bool.guard(!sellable, Ok(stopped(code: wont_buy, logged:)))
  case each_pays(item:, vendor: stock, tables:) {
    Error(PricedOther(error:)) ->
      Ok(stopped_logged(
        reason: "priced in another currency",
        text: label
          <> " sells "
          <> item_price.describe(error:)
          <> "; the sale of it is #650's, so the server answers "
          <> int.to_string(wont_buy),
        code: wont_buy,
        logged:,
      ))
    Error(Unpriced(refusal:)) -> Error(refusal)
    Ok(0) -> Ok(stopped(code: wont_buy, logged:))
    Ok(each) ->
      Ok(
        Picked(stacks: [
          SoldItem(
            item_guid: item.item_guid,
            item2_id: item.item2_id,
            held_count: item.stack_count,
            sold_count: quantity,
            credits: each * quantity,
          ),
        ]),
      )
  }
}

/// Why an item has no credit price to pay.
type Unpaid {
  /// The item's price is in another currency or has an additive, which #650 and #333
  /// build.
  PricedOther(error: item_price.PriceError)
  /// A row the price reads is missing: the server's own state is broken.
  Unpriced(refusal: Refusal)
}

/// The credits the vendor pays for one of the item, which is 0 for an item it does not buy.
fn each_pays(
  item item: HeldItem,
  vendor stock: vendor.Vendor,
  tables tables: table_store.Tables,
) -> Result(Int, Unpaid) {
  case item_price.sell_base(tables:, item2_id: item.item2_id) {
    Ok(base) -> Ok(item_price.shown(base:, multiplier: stock.sell_multiplier))
    Error(item_price.OtherCurrency(..) as error)
    | Error(item_price.TradeskillAdditive(..) as error) ->
      Error(PricedOther(error:))
    Error(item_price.MissingRow(..)) | Error(item_price.NoCurveValue(..)) ->
      Error(Unpriced(refusal: NoItemRow(item2_id: item.item2_id)))
  }
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
  |> result.map(fn(stacks) { Picked(stacks: option.values(stacks)) })
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
  case each_pays(item:, vendor: stock, tables:) {
    Error(PricedOther(..)) | Ok(0) -> Ok(None)
    Error(Unpriced(refusal:)) -> Error(refusal)
    Ok(each) -> {
      let count = int.max(1, item.stack_count)
      Ok(
        Some(SoldItem(
          item_guid: item.item_guid,
          item2_id: item.item2_id,
          held_count: item.stack_count,
          sold_count: count,
          credits: each * count,
        )),
      )
    }
  }
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
  let #(level, logged) = interaction.log_level(key: "sell " <> reason, logged:)
  Refused(effects: [Log(level:, text:), Refuse(code:)], logged:)
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
    credits_held: sale.credits_held,
    credits_after: sale.credits_after,
    sold: list_sold(sale:),
  ))
}

/// What the store's answer leaves: the items, the credits held, the buyback list and the
/// effects, in order.
pub fn answered(
  sale sale: Sale,
  items items: List(HeldItem),
  currencies currencies: Currencies,
  buyback buyback: Buyback,
  answer answer: ItemsAnswer,
) -> #(List(HeldItem), Currencies, Buyback, List(Effect)) {
  case answer {
    Sold(credits:) -> {
      let stacks = [sale.first, ..sale.rest]
      let entries =
        list.index_map(stacks, fn(stack, position) {
          BuybackEntry(
            buyback_id: buyback.next_id + position,
            item2_id: stack.item2_id,
            quantity: stack.sold_count,
            credits: stack.credits,
          )
        })
      #(
        sold_from(items:, stacks:),
        currency.with_credits(currencies:, credits:),
        Buyback(
          next_id: buyback.next_id + list.length(stacks),
          entries: list.append(buyback.entries, entries),
        ),
        [
          Send(currency.changed_frame(total: credits)),
          ..list.flat_map(list.zip(stacks, entries), fn(pair) {
            let #(stack, entry) = pair
            [Send(stack_frame(stack:)), Send(buyback_frame(entry:))]
          })
        ],
      )
    }
    ItemsNotSaved -> #(items, currencies, buyback, [
      Log(
        level: LogWarning,
        text: not_sold(sale:)
          <> ": a later login holds the character, or the credits or the items are not as the connection holds them",
      ),
      Refuse(code: db_failure),
    ])
    SaveRefused(constraint:) -> #(items, currencies, buyback, [
      Log(
        level: LogError,
        text: not_sold(sale:)
          <> ": the store refused the change by the constraint "
          <> constraint,
      ),
      Refuse(code: db_failure),
    ])
    store.ItemsSaved | store.ItemMade(..) | store.Bought(..) ->
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

/// The 0xBA that adds the entry to the client's Buyback list: the credits paid are its first
/// amount in credits (currency type 1), and every field the client's code gives no use is 0
/// (`opcode.0xba.price`).
fn buyback_frame(entry entry: BuybackEntry) -> Frame {
  let Item2Id(item_id) = entry.item2_id
  let assert Ok(body) =
    buyback_added.encode(
      buyback_added.BuybackAdded(entry: buyback_entry.BuybackEntry(
        buyback_id: entry.buyback_id,
        item_id:,
        quantity: entry.quantity,
        field_4: 0,
        field_5: 0,
        field_6: 0,
        field_7: 0,
        field_8: 0,
        field_9: 0,
        field_10: 0,
        field_11: 0,
        field_12: 0,
        field_13: 0,
        field_14: 0,
        field_15: 0,
        field_16: 0,
        field_17: 0,
        field_18: 0,
        field_19: 0,
        field_20: 0,
        field_21: 0,
        amount_1: entry.credits,
        amount_2: 0,
        currency_type_1: credits_currency_type,
        currency_type_2: 0,
        field_26: 0,
      )),
    )
    as "an entry whose fields are held values of their widths is written"
  frame.Frame(message_id: buyback_added.message_id, body:)
}

/// The CurrencyType row of credits (`currency`).
const credits_currency_type = 1

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
  <> int.to_string(sale.credits_after - sale.credits_held)
  <> " credits was not saved"
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  case refusal {
    NotDecoded(undecoded:) -> client_connection.describe_undecoded(undecoded:)
    NoItemRow(item2_id:) ->
      "a held item has no row in the client's tables, or a row its price reads: Item2 "
      <> int.to_string(item2_id.value)
  }
}

/// What the tables must hold at load for a sale: the credit cap and the sell fraction.
pub fn requirements() -> List(table_store.Requirement) {
  [
    table_store.Requirement(
      from_table: "the server's credit cap",
      column: "GameFormula id",
      to_table: "GameFormula",
      missing: fn(tables) { missing_formula(tables:, id: credit_cap_formula) },
    ),
    table_store.Requirement(
      from_table: "the server's sell price fraction",
      column: "GameFormula id",
      to_table: "GameFormula",
      missing: fn(tables) {
        missing_formula(tables:, id: sell_fraction_formula)
      },
    ),
  ]
}

/// The GameFormula row's id when the tables lack it.
fn missing_formula(tables tables: table_store.Tables, id id: Int) -> List(Int) {
  case game_formula.get(tables:, id: GameFormulaId(id)) {
    Ok(_) -> []
    Error(Nil) -> [id]
  }
}

/// The stacks of the sale as the store's request names them.
fn list_sold(sale sale: Sale) -> List(store.SoldStack) {
  list.map([sale.first, ..sale.rest], fn(stack) {
    store.SoldStack(
      item_guid: stack.item_guid,
      held_count: stack.held_count,
      sold_count: stack.sold_count,
    )
  })
}
