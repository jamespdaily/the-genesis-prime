//// The player's sale to the open vendor: the client's 0x0166 (one stack, or part of one)
//// and 0x0167 (all junk), a feature of the game connection's rule
//// (genesis_prime/game/connection) taken from inside 0x038C with the player in the world.
//// The sequence is genesis_prime/game/connection/vendor_sale's.
////
//// ```
//// 0x166 {place, quantity} | 0x167 {} ─▶ take(request, items, currencies, opened, ...)
////                                       ├─ refused ─▶ Refused([Refuse(code), Log])   nothing asked, nothing changed
////                                       └─ accepted ─▶ Asks(sale) ─▶ the connection asks the store (request(..))
//// the store's answer ─▶ answered(sale, items, currencies, buyback, answer)
////                       Sold(total):     items, credits and buyback list updated; 0x919, then per stack 0x148 / 0x17F and 0xBA
////                       ItemsNotSaved:   Warning, 0x106 5, nothing changed
////                       SaveRefused(c):  Warning naming c, 0x106 5, nothing changed
//// ```
////
//// - **The price** is what the client's window shows (`opcode.0x166`, `0x14041bcc0.formula`):
////   per item `item_price.sell_shown(base, vendor sell multiplier)`, and the sale pays that
////   times the quantity. The base is the Item2's SellToVendor credit amount when either of
////   its currency type columns is set, else the computed buy price times GameFormula 1026
////   (0.15), at least 1. A row that needs a currency other than credits is refused with 23
////   and a log line: worn items and those prices are #650's.
//// - **The checks, in order**, each a 0x106 with its code (`GameLib.CodeEnumGenericError`):
////   1. a body the client's reader refuses ends the connection (`NotDecoded`)
////   2. no vendor window is open on the connection: 16 Vendor_NotAVendor, logged
////   3. the player is dead: 2 PlayerBusy (`opcode.0x166`), logged
////   4. the open vendor's unit is gone from the picture, not a creature, dead, too far or
////      Hostile: 59, 16, 23, 17 or 62, logged (`interaction.vendor_opened`; the sale's code
////      for a dead vendor is 23)
////   5. no held item at the place: 18 Vendor_BadItemRec, logged (the client sends nothing then)
////   6. a worn bag, location 0 with the bag's joined flag: 25 Vendor_BagIsNotEmpty
////      (`0x1403d6a10`)
////   7. a place that is not the usable inventory (location 1): 23, logged; worn items are #650's
////   8. the quantity is 0: 24 Vendor_NoQuantity
////   9. the quantity is over the stack's count, a count of 0 reading as 1: 19
////   10. the item does not stack and the quantity is over 1: 11 Vendor_StackSize
////   11. the item is not sellable (`item_property.sellable`) or its price is 0: 23
////   12. the item is priced in a currency other than credits: 23, logged; #650's
////   Cases 2 to 7 are a modified or stale client, answered and logged once for each reason
////   on the connection (a warning the first time, a debug line after), and the connection
////   goes on, as the buy's cases do.
//// - **Junk** (0x167) sells every held item of Item2Category 94
////   (`lua.Item.CodeEnumItem2Category.Junk`) in the usable inventory that passes cases 10
////   to 12, whole, in bag-index order, in one statement; the others stay. A body that is not
////   empty ends the connection. With nothing to sell nothing is sent.
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
//// | GameFormula 1115 has no row | the connection ends (`NoCreditCap`) |
//// | the store changes nothing or refuses a place | 0x106 5, a warning, items, credits and buyback as before |
//// | the connection ends while the store works | the store finishes or rolls back; the next login loads whichever |

import genesis_prime/client_connection.{type Undecoded}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/currency.{type Currencies}
import genesis_prime/game/interaction
import genesis_prime/game/player_life.{type Life}
import genesis_prime/game/shown.{type Picture}
import genesis_prime/game/vendor
import genesis_prime/game/world_entry.{type Buyback}
import genesis_prime/message/vendor_sale as vendor_sale_message
import genesis_prime/message/vendor_sell_junk as vendor_sell_junk_message
import genesis_prime/step.{type LogLevel}
import genesis_prime/store.{
  type AccountId, type CharacterId, type HeldItem, type ItemsAnswer,
  type SessionEpoch,
}
import genesis_prime/table/id.{type Item2Id}
import genesis_prime/table/loader/store as table_store
import gleam/list
import gleam/option.{type Option}
import gleam/set.{type Set}

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
/// sold in bag-index order, the credits held when it was taken (which fence the store's
/// statement) and the credits held after it, capped.
pub type Sale {
  Sale(
    unit_id: Int,
    sold: List(SoldItem),
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
  /// GameFormula 1115, the credit cap, is not in the tables.
  NoCreditCap
}

/// What the client's sale message is answered with: a refusal with the code of the first
/// check it breaks, or the store's ask, or the refusal for a body the client's reader
/// refuses.
pub fn take(
  request _request: Request,
  items _items: List(HeldItem),
  currencies _currencies: Currencies,
  opened _opened: Option(vendor.Opened),
  life _life: Life,
  player _player: interaction.Player,
  picture _picture: Picture,
  tables _tables: table_store.Tables,
  vendors _vendors: vendor.Vendors,
  now_ms _now_ms: Int,
  logged _logged: Set(String),
) -> Result(Taken, Refusal) {
  panic as "shape: #584"
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
  sale _sale: Sale,
  items _items: List(HeldItem),
  currencies _currencies: Currencies,
  buyback _buyback: Buyback,
  answer _answer: ItemsAnswer,
) -> #(List(HeldItem), Currencies, Buyback, List(Effect)) {
  panic as "shape: #584"
}

/// A sentence that says which sale was not saved, for the log.
pub fn not_sold(sale _sale: Sale) -> String {
  panic as "shape: #584"
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe(refusal _refusal: Refusal) -> String {
  panic as "shape: #584"
}

/// The stacks of the sale as the store's request names them.
fn list_sold(sale sale: Sale) -> List(store.SoldStack) {
  list.map(sale.sold, fn(stack) {
    store.SoldStack(
      item_guid: stack.item_guid,
      held_count: stack.held_count,
      sold_count: stack.sold_count,
    )
  })
}
