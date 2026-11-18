//// The spend of an item's charge on the game connection (genesis_prime/game/connection):
//// the cast a 0x943 started is held while the store saves what the use spends, and the
//// store's answer releases it or cancels it. The rule is genesis_prime/game/item_charge's,
//// which holds the diagram and the failure table; this module carries it out.
////
//// ```
//// InWorld ─ cast.use_item gave Started ─▶ item_charge.spend
////             NothingToSpend ─▶ the cast adopted and its effects carried out, InWorld
////             otherwise      ─▶ ask the store (SpendItem or DeleteItem), SpendingCharge,
////                               the cast's state and effects held
//// SpendingCharge ─ the store's answer ─▶ ItemsSaved: the inventory frame, the cast adopted
////                                        with the press id, the effects, InWorld
////                                      ItemsNotSaved | SaveRefused: 0x7fc result 1 and a
////                                        log line, the items and the cast as before, InWorld
////                  the store unavailable, not running, ended or past its deadline
////                                      ─▶ the connection ends with reason 8, nothing released
//// ```
////
//// - **The shell takes no input while the ask is out**, so a second 0x943 waits behind the
////   answer and meets the lowered item and the recorded press id.
//// - **A refused save is the server's failure**, shown with result 1 (`UnableToCreateSpell`,
////   text 119668), and the connection goes on: the store is not known to be away.

import genesis_prime/client_connection.{type Answer}
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/connection/state.{type Session}
import genesis_prime/game/item_charge
import genesis_prime/game/world_entry
import genesis_prime/hand_off.{type Holder}
import genesis_prime/step.{type Now, type Outcome}

/// The cast the player's 0x943 started, taken from `cast.use_item`: the item the press
/// named is spent from (`item_charge.spend`); a spend that takes nothing applies the cast
/// at once, any other asks the store and the connection waits in `SpendingCharge` with the
/// cast's state and effects held.
pub fn started(
  session _session: Session,
  now _now: Now,
  holder _holder: Holder,
  entered _entered: world_entry.Entered,
  press _press: cast_state.ItemPress,
  cast _cast: cast_state.State,
  effects _effects: List(cast_state.Effect),
) -> client_connection.Handled(Session) {
  panic as "shape: the held-back start is built in the next commit"
}

/// The store's answer to the spend, as the diagram says: the inventory frame, the cast and
/// its effects after `ItemsSaved`; 0x7fc result 1 and the items and cast as before after
/// `ItemsNotSaved` or `SaveRefused`; the connection ends with reason 8 when the store
/// failed.
pub fn answered(
  session _session: Session,
  now _now: Now,
  holder _holder: Holder,
  entered _entered: world_entry.Entered,
  spending _spending: item_charge.Spending,
  outcome _outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  panic as "shape: the spend's answer is built in the next commit"
}
