//// The player's buy from the open vendor on the game connection
//// (genesis_prime/game/connection): the client's 0x00BE, and the store's answer to the buy
//// it asked for. The rule's decisions are genesis_prime/game/vendor_purchase's, which holds
//// the checks and the failure table; this module carries them out.
////
//// ```
//// 0xBE ─▶ vendor_purchase.take(entered, picture, body) ─▶ Refused(0x106 code, log once per reason)   status stays InWorld
////                                                      └▶ Asks(purchase) ─▶ AskStore(Items(BuyFromVendor ...))   status Buying(holder, entered, purchase), frames held
//// store worker: lock_character_for_save then buy_from_vendor.sql, one transaction
////    ─▶ Bought(total, made)    ─▶ answered: entered.currencies and entered.items updated; 0x919 kind 0, then 0x111 / 0x17F reason 7; status InWorld; held frames replayed
////    ─▶ ItemsNotSaved | SaveRefused(constraint) ─▶ 0x106 5 and a warning; nothing in memory changes; status InWorld
////    ─▶ unavailable, not running, past deadline ─▶ the connection ends, reason 8 (as an item move)
//// ```
////
//// | Case | Killed there | Twice at once | Times out |
//// |---|---|---|---|
//// | take, before asking | nothing written, and the client's window stays | a second 0xBE is held while Buying, then taken against the new totals | n/a |
//// | store asked, transaction open | Postgres rolls back; the monitor ends the connection with reason 8; the next login loads the old state | the epoch fence and the `credits.amount = $4` guard make the second change nothing | the connection ends with reason 8, and the result, if it commits, is loaded next login |
//// | store answered, before `answered` runs | the save is done; the next login loads the new state | n/a (frames held) | n/a |
//// | connection dies while Buying | the store finishes or rolls back; the next login loads whichever | n/a | n/a |

import genesis_prime/client_connection.{type Answer}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection/state.{type Session}
import genesis_prime/game/vendor_purchase
import genesis_prime/game/world_entry
import genesis_prime/hand_off.{type Holder}
import genesis_prime/step.{type Now, type Outcome}

/// The client's 0x00BE, taken from inside 0x038C with the player in the world: a refusal is
/// written and the player stays in the world; an accepted buy asks the store and the
/// connection waits in `Buying`; a body the client's reader would refuse ends the connection.
pub fn purchase_message(
  session _session: Session,
  now _now: Now,
  holder _holder: Holder,
  entered _entered: world_entry.Entered,
  inner _inner: Frame,
) -> client_connection.Handled(Session) {
  panic as "shape: #583 the shell takes a buy"
}

/// The store's answer to the buy: the player is in the world again with the items and credits
/// the answer leaves and the buy's replies or a 0x106 written; a store that failed ends the
/// connection with reason 8.
pub fn buy_answered(
  session _session: Session,
  now _now: Now,
  holder _holder: Holder,
  entered _entered: world_entry.Entered,
  purchase _purchase: vendor_purchase.Purchase,
  outcome _outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  panic as "shape: #583 the shell takes the store's answer"
}
