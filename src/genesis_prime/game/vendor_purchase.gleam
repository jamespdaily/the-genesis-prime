//// The player's buy from the open vendor, the client's 0x00BE, and buy back of an entry of
//// their buyback list, the client's 0x00BB: features of the game connection's rule
//// (genesis_prime/game/connection) taken from inside 0x038C with the player in the world.
//// The sequence is genesis_prime/game/connection/vendor_purchase's.
////
//// ```
//// 0x00BE {unique id, quantity} ─▶ take(body, items, currencies, opened, ...)
////                                 ├─ refused ─▶ Refused([Refuse(code), Log])   nothing asked, nothing changed
////                                 └─ accepted ─▶ Asks(purchase) ─▶ the connection asks the store (request(..))
//// the store's answer ─▶ answered(purchase, items, currencies, answer)
////                       Bought(amount, made): items and the currency spent updated, 0x919 then 0x111 / 0x17F
////                       ItemsNotSaved:       Warning, 0x106 5, nothing changed
////                       SaveRefused(c):      Warning naming c, 0x106 5, nothing changed
//// ```
////
//// - **The client checks neither stock nor cash in code** (`opcode.0xbe`): only the addon
////   does, so every check here is the server's, and each answers with the code the addon
////   shows. The sender sends nothing for a dead player or with no vendor interaction open.
//// - **The checks, in order**, each a 0x106 with its code (`GameLib.CodeEnumGenericError`):
////   1. a body the client's reader refuses ends the connection (`NotDecoded`)
////   2. no vendor window is open on the connection: 16 Vendor_NotAVendor, logged
////   3. the player is dead: 57 Player_CantDoWhileDead, logged
////   4. the open vendor's unit is gone from the picture, not a creature or dead, too far or
////      Hostile: 59, 16, 17 or 62, logged; the vendor-open checks, called again
////      (`interaction.vendor_opened`)
////   5. the unique id is not in the open vendor's stock: 14 Vendor_UnknownItem
////   6. the quantity is 0: 24 Vendor_NoQuantity
////   7. the price times the item's stack count times the quantity is over what is held of
////      the price's currency (credits for a stocked item, the entry's currency for a buy
////      back): 20 Vendor_NotEnoughCash
////   8. the items do not fit the usable inventory (`inventory.size`): 27 Item_InventoryFull
////   Cases 2 to 4 are a modified or stale client, answered and logged once for each reason
////   on the connection (a warning the first time, a debug line after): the picture can be
////   one news message stale, so the connection goes on.
//// - **The quantity counts lots.** Each lot is the Item2's buyFromVendorStackCount items
////   (Vendor.lua l.437 to 452): the player gets quantity times that many items and pays the
////   price the client's window shows for it (`item_price`)
////   times that count times the quantity. The vendor load refuses a stocked item whose lot is 0
////   (`vendor`), so a stocked item's lot is at least 1.
//// - **Where the items go** is a server choice, as no client code decides it: stacks of the
////   same Item2 in the usable inventory (location 1, bag index below `inventory.size`) that
////   are below `item_property.stack_limit` are filled lowest bag index first, then empty
////   slots lowest first, at most the stack limit each. An item that is not stackable has a
////   limit of 1. Items left over are check 8, before the store is asked.
//// - **The store's answer** decides the reply, so storage and the client agree after it:
////   `ItemsNotSaved` (a stale epoch, a total that moved, a stack that changed or too few
////   of the currency) and `SaveRefused` leave the items and the currency as they were and answer 0x106
////   code 5 DbFailure. A store that is unavailable, not running or past its deadline ends the
////   connection with reason 8, which the connection decides.
//// - **The answer's frames**: 0x919 with the currency's kind (type - 1) and the new total,
////   then 0x111 for each new stack
////   and 0x17F for each grown stack, with the reason 7 (Vendor), which makes the client show
////   "Bought <item>" (Vendor.lua OnItemAdded l.733, `ktVendorRespondEvent`).
//// - **The buy back, 0x00BB {buyback id}**, is taken under the conditions of 0xBE
////   (`opcode.0xbb`), so checks 1 to 4, 7 and 8 and their codes are the buy's. The entry is
////   one of the player's buyback list (`world_entry.Buyback`), not of a vendor's stock: an id
////   the list does not hold is 14 Vendor_UnknownItem, and the entry's Item2 is returned for
////   the amount the sale paid, in the currency it paid, at whichever vendor is open. The
////   answer is the buy's, with
////   the reason 16 (Item.CodeEnumItemUpdateReason Buyback) and then a 0xBD naming the entry,
////   which leaves the list; an answer that saved nothing leaves the list as it was.
//// - **Gaps, each left to the vendor system** (#333): the control states (60, 61), the
////   prerequisites (15), Item_Unique (30) and sold out (13) are not checked. No stock row has
////   a prerequisite or a stock limit (0x90B sends 0 for both), and the held-unique rule is not
////   read. A stocked item priced in another currency is #333's.
////
//// | Point | What happens |
//// |---|---|
//// | the held items' Item2 row is missing from the tables | the connection ends (`NoItemRow`) |
//// | the store changes nothing or refuses a place | 0x106 5, a warning, items and credits as before |
//// | the connection ends while the store works | the store finishes or rolls back; the next login loads whichever |

import genesis_prime/client_connection
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/currency.{type Currencies}
import genesis_prime/game/interaction
import genesis_prime/game/inventory
import genesis_prime/game/item_property
import genesis_prime/game/player_life.{type Life}
import genesis_prime/game/shown.{type Picture}
import genesis_prime/game/vendor.{type Vendors}
import genesis_prime/game/vendor_trade.{
  type Effect, type Refusal, NoItemRow, NotDecoded, Refuse, Send,
}
import genesis_prime/game/world_entry.{type Buyback, Buyback}
import genesis_prime/message/buyback_removed
import genesis_prime/message/vendor_buyback
import genesis_prime/message/vendor_purchase as vendor_purchase_message
import genesis_prime/store.{
  type AccountId, type CharacterId, type HeldItem, type ItemsAnswer,
  type SessionEpoch, HeldItem, ItemsNotSaved, SaveRefused,
}
import genesis_prime/table/id.{type Item2Id, Item2Id}
import genesis_prime/table/item2
import genesis_prime/table/loader/store as table_store
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/set.{type Set}

/// The id of the message this rule takes.
pub const message_id = vendor_purchase_message.message_id

/// The id of the buy back's message.
pub const buy_back_message_id = vendor_buyback.message_id

/// What a purchase is: an item of the open vendor's stock (0x00BE), or an entry of the
/// player's buyback list, by the id it was added with (0x00BB). The store is asked the same
/// for both; they differ in the price, the reason the client shows and the entry that leaves
/// the list.
pub type Kind {
  Bought
  BoughtBack(buyback_id: Int)
}

/// A buy the rule accepted and the store is asked for: its kind, the unit it was made at, the
/// Item2 bought and how many items, what is paid and in which currency, what is held of that
/// currency when it was taken (which fences the store's statement), the stacks that grow and
/// the stacks that are made.
pub type Purchase {
  Purchase(
    kind: Kind,
    unit_id: Int,
    item2_id: Item2Id,
    items_bought: Int,
    cost: Int,
    currency_type_id: Int,
    held: Int,
    grow: List(store.StackGrowth),
    make: List(store.NewStack),
  )
}

/// What the rule makes of a buy the client sent, with the log keys met so far.
pub type Taken {
  /// The buy breaks a check: the effects answer it and nothing is asked or changed.
  Refused(effects: List(Effect), logged: Set(String))
  /// The buy passes every check: the store is asked for it.
  Asks(purchase: Purchase, logged: Set(String))
}

/// How the buy words and codes the refusals of its window and player: a dead player is 57
/// and a dead vendor 16, and the window's reach applies (`opcode.0xbe`).
const trade =
  vendor_trade.Trade(
    key: "buy",
    verb: "buys from",
    refused: "the interaction",
    dead_player_code: 57,
    dead_vendor_code: 16,
    reach: interaction.CheckReach,
  )

/// How the buy back words and codes the refusals of its window and player: the client sends
/// 0xBB under the conditions of 0xBE (`opcode.0xbb`), so the codes and the reach are the buy's.
const buy_back_trade =
  vendor_trade.Trade(
    key: "buyback",
    verb: "buys back from",
    refused: "the interaction",
    dead_player_code: 57,
    dead_vendor_code: 16,
    reach: interaction.CheckReach,
  )

/// The client's code for a buy of an id the vendor does not sell, or a buy back of an id the
/// player's list does not hold (Vendor_UnknownItem).
const unknown_item = 14

/// The client's code for a buy of a quantity of 0 (Vendor_NoQuantity).
const no_quantity = 24

/// The client's code for a buy over the credits held (Vendor_NotEnoughCash).
const not_enough_cash = 20

/// The client's code for a buy the inventory has no place for (Item_InventoryFull).
const inventory_full = 27

/// The reason a vendor purchase's items are shown for (Item.CodeEnumItemUpdateReason 7,
/// Vendor): the client shows "Bought <item>".
const vendor_reason = 7

/// The reason a bought-back item is shown for (Item.CodeEnumItemUpdateReason 16, Buyback).
const buyback_reason = 16

/// What the client's 0x00BE is answered with: a refusal with the code of the first check it
/// breaks, or the store's ask, or the refusal for a body the client's reader refuses.
pub fn take(
  body body: BitArray,
  items items: List(HeldItem),
  currencies currencies: Currencies,
  opened opened: Option(vendor.Opened),
  life life: Life,
  player player: interaction.Player,
  picture picture: Picture,
  tables tables: table_store.Tables,
  vendors vendors: Vendors,
  now_ms now_ms: Int,
  logged logged: Set(String),
) -> Result(Taken, Refusal) {
  use buy <- result.try(
    vendor_purchase_message.decode(body)
    |> client_connection.decoded(message_id:)
    |> result.map_error(NotDecoded),
  )
  case
    vendor_trade.opened(
      trade:,
      label: "0x00BE",
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
    Error(vendor_trade.Declined(effects:, logged:)) ->
      Ok(Refused(effects:, logged:))
    Ok(window) -> buy_from(buy:, window:, items:, currencies:, tables:, logged:)
  }
}

/// What the client's 0x00BB is answered with: the checks of a buy that apply to an entry
/// (the window, the currency, the inventory) with the entry's items for the entry's amount of
/// its currency,
/// or 14 for an id the list does not hold, or the refusal for a body the client's reader refuses.
pub fn take_back(
  body body: BitArray,
  items items: List(HeldItem),
  currencies currencies: Currencies,
  opened opened: Option(vendor.Opened),
  buyback buyback: Buyback,
  life life: Life,
  player player: interaction.Player,
  picture picture: Picture,
  tables tables: table_store.Tables,
  vendors vendors: Vendors,
  now_ms now_ms: Int,
  logged logged: Set(String),
) -> Result(Taken, Refusal) {
  use back <- result.try(
    vendor_buyback.decode(body)
    |> client_connection.decoded(message_id: buy_back_message_id)
    |> result.map_error(NotDecoded),
  )
  case
    vendor_trade.opened(
      trade: buy_back_trade,
      label: "0x00BB",
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
    Error(vendor_trade.Declined(effects:, logged:)) ->
      Ok(Refused(effects:, logged:))
    Ok(window) ->
      case
        list.find(buyback.entries, fn(entry) {
          entry.buyback_id == back.buyback_id
        })
      {
        Error(Nil) -> {
          let vendor_trade.Declined(effects:, logged:) =
            vendor_trade.refused_logged(
              trade: buy_back_trade,
              reason: "unknown id",
              text: "0x00BB buys back entry "
                <> int.to_string(back.buyback_id)
                <> " that the buyback list does not hold: the client names only the entries it was sent, so the server answers "
                <> int.to_string(unknown_item),
              code: unknown_item,
              logged:,
            )
          Ok(Refused(effects:, logged:))
        }
        Ok(entry) ->
          asked(
            kind: BoughtBack(buyback_id: entry.buyback_id),
            window:,
            item2_id: entry.item2_id,
            items_bought: entry.quantity,
            cost: entry.amount,
            currency_type_id: entry.currency_type_id,
            items:,
            currencies:,
            tables:,
            logged:,
          )
      }
  }
}

/// A buy the player may make from the window's stock: the checks of the stock, the quantity,
/// the credits and the inventory.
fn buy_from(
  buy buy: vendor_purchase_message.VendorPurchase,
  window window: vendor.Opened,
  items items: List(HeldItem),
  currencies currencies: Currencies,
  tables tables: table_store.Tables,
  logged logged: Set(String),
) -> Result(Taken, Refusal) {
  let stocked =
    list.find(window.vendor.items, fn(stocked) {
      stocked.position == buy.unique_id
    })
  use <- bool.guard(
    when: result.is_error(stocked),
    return: Ok(refused(code: unknown_item, logged:)),
  )
  use <- bool.guard(
    when: buy.quantity == 0,
    return: Ok(refused(code: no_quantity, logged:)),
  )
  let assert Ok(stocked) = stocked
    as "the guard above returned for an id the stock does not hold"
  let item2_id = stocked.item_id
  use lot <- result.try(
    item2.get(tables:, id: item2_id)
    |> result.map(fn(row) { row.buy_from_vendor_stack_count })
    |> result.replace_error(NoItemRow(item2_id:)),
  )
  let items_bought = buy.quantity * lot
  asked(
    kind: Bought,
    window:,
    item2_id:,
    items_bought:,
    cost: stocked.price * items_bought,
    currency_type_id: currency.credits_type,
    items:,
    currencies:,
    tables:,
    logged:,
  )
}

/// A buy of `items_bought` of an Item2 for `cost` of a currency that the player may make: the
/// checks of the currency and the inventory, shared by the buy and the buy back.
fn asked(
  kind kind: Kind,
  window window: vendor.Opened,
  item2_id item2_id: Item2Id,
  items_bought items_bought: Int,
  cost cost: Int,
  currency_type_id currency_type_id: Int,
  items items: List(HeldItem),
  currencies currencies: Currencies,
  tables tables: table_store.Tables,
  logged logged: Set(String),
) -> Result(Taken, Refusal) {
  let held = currency.held(currencies:, currency_type_id:)
  use <- bool.guard(
    when: cost > held,
    return: Ok(refused(code: not_enough_cash, logged:)),
  )
  use limit <- result.try(
    item_property.stack_limit(tables:, item2_id: item2_id.value)
    |> result.map(option.unwrap(_, 1))
    |> result.replace_error(NoItemRow(item2_id:)),
  )
  use size <- result.try(
    inventory.size(items:, tables:) |> result.map_error(inventory_row),
  )
  case
    inventory.placed(items:, item2_id:, size:, limit:, wanted: items_bought)
  {
    Error(Nil) -> Ok(refused(code: inventory_full, logged:))
    Ok(#(grow, make)) ->
      Ok(Asks(
        purchase: Purchase(
          kind:,
          unit_id: window.unit_id,
          item2_id:,
          items_bought:,
          cost:,
          currency_type_id:,
          held:,
          grow:,
          make:,
        ),
        logged:,
      ))
  }
}

/// A refusal of a buy by the client's code, with nothing to log.
fn refused(code code: Int, logged logged: Set(String)) -> Taken {
  Refused(effects: [Refuse(code:)], logged:)
}

/// The row a held item lacks, which only the inventory's size reads.
fn inventory_row(refusal refusal: inventory.Refusal) -> Refusal {
  case refusal {
    inventory.NoItemRow(item2_id:) -> NoItemRow(item2_id:)
    inventory.NotDecoded(..) | inventory.EquipCheckBroken(..) ->
      panic as "the inventory's size reads only the rows of the held bags"
  }
}

/// The store's request for the buy.
pub fn request(
  purchase purchase: Purchase,
  account_id account_id: AccountId,
  character_id character_id: CharacterId,
  session_epoch session_epoch: SessionEpoch,
) -> store.Request {
  store.Items(store.BuyFromVendor(
    account_id:,
    character_id:,
    session_epoch:,
    currency_type_id: purchase.currency_type_id,
    held: purchase.held,
    cost: purchase.cost,
    grow: purchase.grow,
    make: purchase.make,
    item2_id: purchase.item2_id,
  ))
}

/// What the store's answer leaves: the items, the amounts held, the buyback list and the
/// effects, in order. A buy back takes its entry off the list, after the items it returns.
pub fn answered(
  purchase purchase: Purchase,
  items items: List(HeldItem),
  currencies currencies: Currencies,
  buyback buyback: Buyback,
  answer answer: ItemsAnswer,
) -> #(List(HeldItem), Currencies, Buyback, List(Effect)) {
  case answer {
    store.Bought(amount:, made:) -> {
      let reason = case purchase.kind {
        Bought -> vendor_reason
        BoughtBack(..) -> buyback_reason
      }
      let #(buyback, removal) = case purchase.kind {
        Bought -> #(buyback, [])
        BoughtBack(buyback_id:) -> #(
          Buyback(
            ..buyback,
            entries: list.filter(buyback.entries, fn(entry) {
              entry.buyback_id != buyback_id
            }),
          ),
          [Send(removed_frame(buyback_id:))],
        )
      }
      #(
        list.append(grown(items:, grow: purchase.grow), made),
        currency.with_amount(
          currencies:,
          currency_type_id: purchase.currency_type_id,
          total: amount,
        ),
        buyback,
        list.flatten([
          [
            Send(currency.changed_frame(
              currency_type_id: purchase.currency_type_id,
              total: amount,
            )),
          ],
          list.map(purchase.grow, fn(growth) {
            Send(inventory.count_changed_frame(
              guid: growth.item_guid,
              count: growth.new_count,
              reason:,
            ))
          }),
          list.map(made, fn(item) {
            let Item2Id(item_id) = item.item2_id
            Send(inventory.item_added_frame(
              item_guid: item.item_guid,
              item_id:,
              location: item.location,
              bag_index: item.bag_index,
              stack_count: item.stack_count,
              reason:,
            ))
          }),
          removal,
        ]),
      )
    }
    ItemsNotSaved -> #(
      items,
      currencies,
      buyback,
      vendor_trade.not_saved(what: not_bought(purchase:)),
    )
    SaveRefused(constraint:) -> #(
      items,
      currencies,
      buyback,
      vendor_trade.save_refused(what: not_bought(purchase:), constraint:),
    )
    store.ItemsSaved
    | store.ItemMade(..)
    | store.Sold(..)
    | store.TurnedIn(..) ->
      panic as "the store answers a purchase with Bought, ItemsNotSaved or SaveRefused"
  }
}

/// The 0xBD that takes an entry off the client's Buyback list (`opcode.0xbd`).
fn removed_frame(buyback_id buyback_id: Int) -> Frame {
  let assert Ok(body) =
    buyback_removed.encode(buyback_removed.BuybackRemoved(buyback_id:))
    as "an id the list held, a 32-bit value, is written"
  frame.Frame(message_id: buyback_removed.message_id, body:)
}

/// The held items with each grown stack at its new count.
fn grown(
  items items: List(HeldItem),
  grow grow: List(store.StackGrowth),
) -> List(HeldItem) {
  list.map(items, fn(item) {
    case list.find(grow, fn(growth) { growth.item_guid == item.item_guid }) {
      Ok(growth) -> HeldItem(..item, stack_count: growth.new_count)
      Error(Nil) -> item
    }
  })
}

/// What a buy that was not saved did not do, for the log.
pub fn not_bought(purchase purchase: Purchase) -> String {
  case purchase.kind {
    Bought -> "the purchase of "
    BoughtBack(buyback_id:) ->
      "the buy back of entry " <> int.to_string(buyback_id) <> ", "
  }
  <> int.to_string(purchase.items_bought)
  <> " of Item2 "
  <> int.to_string({ purchase.item2_id }.value)
  <> " for "
  <> int.to_string(purchase.cost)
  <> " of currency type "
  <> int.to_string(purchase.currency_type_id)
  <> " was not saved"
}
