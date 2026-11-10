//// The player's turn-in of a quest on the game connection (genesis_prime/game/connection): the
//// client's 0x035D, and the store's answer to the turn-in it asked for. The rule's decisions are
//// genesis_prime/game/quest_turn_in's, which holds the checks and the rewards; this module carries
//// them out.
////
//// ```
//// 0x35D ─▶ quest_turn_in.take(entered, picture, body) ─▶ Refused(log once per reason, or 0x106 27)   status stays InWorld
////                                                     └▶ Asks(turn_in) ─▶ AskStore(Items(TurnInQuest ...))   status TurningIn(holder, entered, turn_in), frames held
//// store worker: lock_character_for_save, save_place.sql, then turn_in_rewards.sql, one transaction
////    ─▶ TurnedIn(credits, made) ─▶ answered: entered.items, entered.currencies and entered.quests updated; then in order
////                                  0x111 reason 8 per stack made, a count change per stack grown,
////                                  the experience's frames (0x1ac kind 3, 0x938 and the Level news, the Base Health),
////                                  0x919, 0x35C {quest, 3, 0}; status InWorld; held frames replayed
////    ─▶ ItemsNotSaved | SaveRefused(constraint) ─▶ a warning or an error line; nothing in memory changes; status InWorld
////    ─▶ unavailable, not running, past deadline ─▶ the connection ends, reason 8 (as a buy)
//// ```
////
//// | Case | Killed there | Twice at once | Times out |
//// |---|---|---|---|
//// | take, before asking | nothing written, and the client's dialog stays | a second 0x35D is held while TurningIn, then taken against the new log | n/a |
//// | store asked, transaction open | Postgres rolls back; the monitor ends the connection with reason 8; the next login loads the old state | the epoch fence, the save's number and the guard on the credits held make the second change nothing | the connection ends with reason 8, and the result, if it commits, is loaded next login |
//// | store answered, before `answered` runs | the turn-in is saved; the next login loads it | n/a (frames held) | n/a |
//// | connection dies while TurningIn | the store finishes or rolls back; the next login loads whichever | n/a | n/a |

import genesis_prime/client_connection
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection/state.{type Session}
import genesis_prime/game/quest_turn_in
import genesis_prime/game/world_entry
import genesis_prime/hand_off.{type Holder}
import genesis_prime/step.{type Now, type Outcome}

/// The client's 0x035D, taken from inside 0x038C with the player in the world: a refusal is
/// written or logged and the player stays in the world; an accepted turn-in asks the store and
/// the connection waits in `TurningIn`; a body the client's reader would refuse ends the
/// connection.
pub fn turn_in_message(
  session _session: Session,
  now _now: Now,
  holder _holder: Holder,
  entered _entered: world_entry.Entered,
  inner _inner: Frame,
) -> client_connection.Handled(Session) {
  panic as "shape: #593"
}

/// The store's answer to the turn-in: the player is in the world again with the quest
/// Completed and the rewards the answer leaves, and the frames written; a store that failed
/// ends the connection with reason 8.
pub fn turn_in_answered(
  session _session: Session,
  now _now: Now,
  holder _holder: Holder,
  entered _entered: world_entry.Entered,
  turn_in _turn_in: quest_turn_in.TurnIn,
  outcome _outcome: Outcome(client_connection.Answer),
) -> client_connection.Handled(Session) {
  panic as "shape: #593"
}
