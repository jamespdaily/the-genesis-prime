//// The player's item moves on the game connection (genesis_prime/game/connection):
//// the client's 0x182 and the store's answer to the move it asked for. The
//// rule's decisions are genesis_prime/game/inventory's, which holds the sequence
//// and the failure table; this module carries them out.
////
//// ```
//// InWorld ─ 0x182 ─▶ refused: the 0x56A written, the status stays
////                    accepted: ask the store (MoveItems), MovingItem, frames held
//// MovingItem ─ the store's answer ─▶ InWorld with the items the answer leaves
////                                    and the 0x569, 0x568 or 0x56A written
////             the store unavailable, not running, ended or past its deadline
////                                 ─▶ the connection ends with reason 8
//// ```

import genesis_prime/client_connection.{type Answer}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection/state.{type Session}
import genesis_prime/game/inventory
import genesis_prime/game/world_entry
import genesis_prime/hand_off.{type Holder}
import genesis_prime/step.{type Now, type Outcome}

/// The client's 0x182, taken from inside 0x038C with the player in the world: a
/// refusal is written and the player stays in the world; an accepted move asks
/// the store and the connection waits in `MovingItem`; a body the client's
/// reader would refuse ends the connection.
pub fn item_message(
  session _session: Session,
  now _now: Now,
  holder _holder: Holder,
  entered _entered: world_entry.Entered,
  inner _inner: Frame,
  message _message: inventory.Message,
) -> client_connection.Handled(Session) {
  panic as "shape: #579 item_message is filled by inventory.take and the ask of inventory.request"
}

/// The store's answer to the move: the player is in the world again with the
/// items the answer leaves and its 0x569, 0x568 or 0x56A written; a store that
/// failed ends the connection with reason 8.
pub fn move_answered(
  session _session: Session,
  now _now: Now,
  holder _holder: Holder,
  entered _entered: world_entry.Entered,
  moving _moving: inventory.Moving,
  outcome _outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  panic as "shape: #579 move_answered is filled by inventory.answered and the failures every store ask shares"
}
