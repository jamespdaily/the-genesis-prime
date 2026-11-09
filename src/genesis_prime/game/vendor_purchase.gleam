//// The player's buy from the open vendor: the client's 0x00BE, a feature of the game
//// connection's rule (genesis_prime/game/connection) taken from inside 0x038C with the
//// player in the world. The sequence is genesis_prime/game/connection/vendor_purchase's.
////
//// ```
//// 0x00BE {unique id, quantity} ─▶ take(body, items, currencies, opened, ...)
////                                 ├─ refused ─▶ Refused([Refuse(code), Log])   nothing asked, nothing changed
////                                 └─ accepted ─▶ Asks(purchase) ─▶ the connection asks the store (request(..))
//// the store's answer ─▶ answered(purchase, items, currencies, answer)
////                       Bought(total, made): items and credits updated, 0x919 then 0x111 / 0x17F
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
////   7. the price times the item's stack count times the quantity is over the credits held:
////      20 Vendor_NotEnoughCash
////   8. the items do not fit the usable inventory (`inventory.size`): 27 Item_InventoryFull
////   Cases 2 to 4 are a modified or stale client, answered and logged once for each reason
////   on the connection (a warning the first time, a debug line after): the picture can be
////   one news message stale, so the connection goes on.
//// - **The quantity counts lots.** Each lot is the Item2's buyFromVendorStackCount items
////   (Vendor.lua l.437 to 452): the player gets quantity times that many items and pays the
////   price the client's window shows for it (`item_price`)
////   times that count times the quantity.
//// - **Where the items go** is a server choice, as no client code decides it: stacks of the
////   same Item2 in the usable inventory (location 1, bag index below `inventory.size`) that
////   are below `item_property.stack_limit` are filled lowest bag index first, then empty
////   slots lowest first, at most the stack limit each. An item that is not stackable has a
////   limit of 1. Items left over are check 8, before the store is asked.
//// - **The store's answer** decides the reply, so storage and the client agree after it:
////   `ItemsNotSaved` (a stale epoch, a total that moved, a stack that changed or too few
////   credits) and `SaveRefused` leave the items and credits as they were and answer 0x106
////   code 5 DbFailure. A store that is unavailable, not running or past its deadline ends the
////   connection with reason 8, which the connection decides.
//// - **The answer's frames**: 0x919 kind 0 with the new total, then 0x111 for each new stack
////   and 0x17F for each grown stack, with the reason 7 (Vendor), which makes the client show
////   "Bought <item>" (Vendor.lua OnItemAdded l.733, `ktVendorRespondEvent`).
//// - **Gaps, each left to the vendor system** (#333): the control states (60, 61), the
////   prerequisites (15), Item_Unique (30) and sold out (13) are not checked. No stock row has
////   a prerequisite or a stock limit (0x90B sends 0 for both), and the held-unique rule is not
////   read. Selling, buyback, other currencies and the credit cap are #333's.
////
//// | Point | What happens |
//// |---|---|
//// | the held items' Item2 row is missing from the tables | the connection ends (`NoItemRow`) |
//// | the store changes nothing or refuses a place | 0x106 5, a warning, items and credits as before |
//// | the connection ends while the store works | the store finishes or rolls back; the next login loads whichever |

import genesis_prime/client_connection.{type Undecoded}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/currency.{type Currencies}
import genesis_prime/game/interaction
import genesis_prime/game/player_life.{type Life}
import genesis_prime/game/shown.{type Picture}
import genesis_prime/game/vendor.{type Vendors}
import genesis_prime/message/vendor_purchase as vendor_purchase_message
import genesis_prime/step.{type LogLevel}
import genesis_prime/store.{
  type AccountId, type CharacterId, type HeldItem, type ItemsAnswer,
  type SessionEpoch,
}
import genesis_prime/table/id.{type Item2Id}
import genesis_prime/table/loader/store as table_store
import gleam/option.{type Option}
import gleam/set.{type Set}

/// The id of the message this rule takes.
pub const message_id = vendor_purchase_message.message_id

/// What the rule asks the connection to do.
pub type Effect {
  /// Write a frame to the player's client.
  Send(frame: Frame)
  /// Write a 0x106 with the client's code for why the buy is refused.
  Refuse(code: Int)
  /// Write a log line.
  Log(level: LogLevel, text: String)
}

/// A buy the rule accepted and the store is asked for: the unit it was made at, the Item2
/// bought and how many items, what is paid, the credits held when it was taken (which fence
/// the store's statement), the stacks that grow and the stacks that are made.
pub type Purchase {
  Purchase(
    unit_id: Int,
    item2_id: Item2Id,
    items_bought: Int,
    cost: Int,
    credits_held: Int,
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

/// Why the buy ends the connection with no answer: the client's own code never sends it, or
/// the server's own state is broken.
pub type Refusal {
  /// A body the client's own reader would refuse.
  NotDecoded(undecoded: Undecoded)
  /// A held item or the bought item whose row the tables lack: the server's own state is
  /// broken, since the vendor load and the item rows require them.
  NoItemRow(item2_id: Item2Id)
}

/// What the client's 0x00BE is answered with: a refusal with the code of the first check it
/// breaks, or the store's ask, or the refusal for a body the client's reader refuses.
pub fn take(
  body _body: BitArray,
  items _items: List(HeldItem),
  currencies _currencies: Currencies,
  opened _opened: Option(vendor.Opened),
  life _life: Life,
  player _player: interaction.Player,
  picture _picture: Picture,
  tables _tables: table_store.Tables,
  vendors _vendors: Vendors,
  now_ms _now_ms: Int,
  logged _logged: Set(String),
) -> Result(Taken, Refusal) {
  panic as "shape: #583 the buy's checks"
}

/// The store's request for the buy.
pub fn request(
  purchase _purchase: Purchase,
  account_id _account_id: AccountId,
  character_id _character_id: CharacterId,
  session_epoch _session_epoch: SessionEpoch,
) -> store.Request {
  panic as "shape: #583 the store's request"
}

/// What the store's answer leaves: the items, the credits held and the effects, in order.
pub fn answered(
  purchase _purchase: Purchase,
  items _items: List(HeldItem),
  currencies _currencies: Currencies,
  answer _answer: ItemsAnswer,
) -> #(List(HeldItem), Currencies, List(Effect)) {
  panic as "shape: #583 the store's answer"
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe(refusal _refusal: Refusal) -> String {
  panic as "shape: #583 the refusal's sentence"
}
