//// The player's sale to the open vendor on the game connection
//// (genesis_prime/game/connection): the client's 0x0166 and 0x0167, and the store's answer
//// to the sale it asked for. The rule's decisions are genesis_prime/game/vendor_sale's, which
//// holds the checks; this module carries them out.
////
//// ```
//// 0x166 / 0x167 ─▶ vendor_sale.take(entered, picture, body) ─▶ Refused(0x106 code, log once per reason)   status stays InWorld
////                                                           └▶ Asks(sale) ─▶ AskStore(Items(SellToVendor ...))   status Selling(holder, entered, sale), frames held
//// store worker: lock_character_for_save then sell_to_vendor.sql, one transaction
////    ─▶ Sold(credits) ─▶ answered: entered.items, currencies and buyback updated; 0x919, then per stack 0x148 / 0x17F reason 7 and 0xBA; status InWorld; held frames replayed
////    ─▶ ItemsNotSaved | SaveRefused ─▶ 0x106 5 and a warning; nothing in memory changes; status InWorld
////    ─▶ unavailable, not running, past deadline ─▶ the connection ends, reason 8 (as the buy)
//// ```
////
//// | Where | Killed there | Twice at once | Times out |
//// |---|---|---|---|
//// | take, before asking | nothing written; the window stays | a second 0x166 or the auto-sell 0x167 is held while Selling, then taken against the new items and credits | n/a |
//// | store asked, transaction open | Postgres rolls back; the connection ends, reason 8; the next login loads the old credits and items | the epoch fence, the credits guard and the held-count guard make the second change nothing | the connection ends, reason 8; a committed result is what the next login loads |
//// | store answered, before `answered` runs | the save is done; the next login loads the new credits and items; the buyback entries are lost with the connection (#651 owns the list's lifetime) | n/a (frames held) | n/a |
//// | connection dies while Selling | the store finishes or rolls back on its own | n/a | n/a |

import genesis_prime/client_connection.{type Answer}
import genesis_prime/game/connection/state.{type Session}
import genesis_prime/game/vendor_sale
import genesis_prime/game/world_entry
import genesis_prime/hand_off.{type Holder}
import genesis_prime/step.{type Outcome}

/// The client's 0x0166 or 0x0167, taken from inside 0x038C with the player in the world: a
/// refusal is written and the player stays in the world; an accepted sale asks the store and
/// the connection waits in `Selling`; a body the client's reader would refuse ends the
/// connection.
pub fn sale_message(
  session _session: Session,
  now _now: step.Now,
  holder _holder: Holder,
  entered _entered: world_entry.Entered,
  request _request: vendor_sale.Request,
) -> client_connection.Handled(Session) {
  panic as "shape: #584"
}

/// The store's answer to the sale: the player is in the world again with the items, credits
/// and buyback list the answer leaves and the sale's replies or a 0x106 written; a store that
/// failed ends the connection with reason 8.
pub fn sale_answered(
  session _session: Session,
  now _now: step.Now,
  holder _holder: Holder,
  entered _entered: world_entry.Entered,
  sale _sale: vendor_sale.Sale,
  outcome _outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  panic as "shape: #584"
}
