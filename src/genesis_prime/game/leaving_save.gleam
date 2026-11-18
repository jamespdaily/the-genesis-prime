//// What a connection hands the leaving saver, and the ladder that saver tries
//// it on when the store gives no answer: the waits between tries, the deadline
//// as a time, and the decision after each failure. Pure: times are the
//// monotonic milliseconds an input carries, and the saver's shell starts the
//// timer.
////
//// ```
//// a connection's failed or stopped end ─▶ Handover(.., failed)
//// a try to make                        ─▶ request(handover, tries)            ─▶ the SavePlace to ask
//// a failed ask                         ─▶ after_failure(retries, failed, deadline, now) ─▶ RetryAfter(wait_ms) or GiveUp
//// an ask to make                       ─▶ ask_within_ms(deadline, now, ask)   ─▶ the time it may take; <= 0 is none
//// ```
////
//// - A retry is made only when its wait ends before the deadline; the deadline
////   decides, and `failed` only indexes the ladder, since each try may take an
////   ask's whole deadline.
//// - Each try is numbered one above the last, so a try that reaches the database
////   after a newer one of its own changes nothing (store `SavePlace`,
////   save_place.sql).
//// - The ladder and the window are the server's choice (genesis_prime's
////   settings); the client has no such wait.

import genesis_prime/game/start_place.{type Place}
import genesis_prime/step.{type About}
import genesis_prime/store.{
  type AccountId, type CharacterId, type MoveRequest, type QuestRow,
  type SessionEpoch, SavePlace,
}
import gleam/int
import gleam/list
import gleam/option.{type Option}

/// The ladder of waits between a kept save's tries, and how long it is tried.
/// `waits_ms` holds the waits after the first, second and later failures;
/// `then_ms` is every wait past the list; `within_ms` is the window from the
/// hand-over to the deadline.
pub type Retries {
  Retries(within_ms: Int, waits_ms: List(Int), then_ms: Int)
}

/// What a connection gives the saver: the save as the store's `SavePlace`
/// holds it, and what was already tried. `first_sequence` numbers the first try
/// the saver makes; `failed` is 0 when no try was made (a stop) and 1 when the
/// connection's own try failed.
pub type Handover {
  Handover(
    about: About,
    account_id: AccountId,
    character_id: CharacterId,
    session_epoch: SessionEpoch,
    first_sequence: Int,
    place: Place,
    health: Option(Int),
    experience: Int,
    level: Int,
    quests: List(QuestRow),
    failed: Int,
  )
}

/// What a failed try leads to.
pub type Next {
  RetryAfter(wait_ms: Int)
  GiveUp
}

/// The save of the hand-over for its `tries`th try (0 for the first the saver
/// makes): the handed-over values, numbered `first_sequence + tries`.
pub fn request(handover handover: Handover, tries tries: Int) -> MoveRequest {
  SavePlace(
    account_id: handover.account_id,
    character_id: handover.character_id,
    session_epoch: handover.session_epoch,
    save_sequence: handover.first_sequence + tries,
    place: handover.place,
    health: handover.health,
    experience: handover.experience,
    level: handover.level,
    quests: handover.quests,
  )
}

/// How long an ask made at `now_ms` may take: the ask deadline, or what the
/// deadline leaves when that is shorter. Zero or less means no time is left and
/// no ask is made.
pub fn ask_within_ms(
  deadline_ms deadline_ms: Int,
  now_ms now_ms: Int,
  ask_deadline_ms ask_deadline_ms: Int,
) -> Int {
  int.min(ask_deadline_ms, deadline_ms - now_ms)
}

/// The wait after `failed` earlier failures: the ladder's entry, then
/// `then_ms` past its end.
pub fn wait_ms(retries retries: Retries, failed failed: Int) -> Int {
  case list.drop(retries.waits_ms, failed) {
    [wait_ms, ..] -> wait_ms
    [] -> retries.then_ms
  }
}

/// What a failed try leads to: a retry after `wait_ms(failed)` when that wait
/// ends before the deadline, otherwise giving up. `failed` counts the failures
/// before this one.
pub fn after_failure(
  retries retries: Retries,
  failed failed: Int,
  deadline_ms deadline_ms: Int,
  now_ms now_ms: Int,
) -> Next {
  let wait_ms = wait_ms(retries:, failed:)
  case now_ms + wait_ms < deadline_ms {
    True -> RetryAfter(wait_ms:)
    False -> GiveUp
  }
}
