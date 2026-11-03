//// The camp's rule (`genesis_prime/game/camp`), run as the pure function it is.
//// Expected values come from these places.
//// - The client's camp messages: 0xBF with the bit 1 starts a camp and is
////   answered with 0x92, a second one while the client has not had its first
////   0x92 restarts the client's countdown (opcode.0xbf); 0xBF with 0 is the
////   client's own cancel, which it has already cleared, and is never answered,
////   since a cancelling 0x92 would be answered with another 0xBF 0 without end
////   (lua.ExitWindow.OnPlayerCampCancel); with no camp running it changes
////   nothing (lua.ExitWindow.OnPlayerCampCancel); 0xC0 is sent only while a
////   camp the server started with 0x92 runs (opcode.0xc0).
//// - The module's doc comment: the server never cancels a camp itself.

import genesis_prime/game/camp.{
  Answer, Cancelled, Finished, FinishedWithNoCamp, Ignored,
}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test

const countdown = 12_345

pub fn a_start_runs_a_camp_and_is_answered_with_the_countdown_test() -> Nil {
  use <- owned_test.run(5000)
  let #(running, decision) =
    camp.requested(camp.none(), start: True, countdown_ms: countdown)
  assert decision == Answer(countdown_ms: countdown)
    as "each 0xBF 1 is answered with the setting's countdown (opcode.0x92)"
  assert camp.finished(running) == Ok(Finished)
    as "0xC0 is taken while a camp runs, whenever it comes: a Quit sends it at once (opcode.0xc0)"
}

pub fn a_second_start_while_a_camp_runs_is_answered_again_and_is_still_one_camp_test() -> Nil {
  use <- owned_test.run(5000)
  let #(running, _) =
    camp.requested(camp.none(), start: True, countdown_ms: countdown)
  let #(running, decision) =
    camp.requested(running, start: True, countdown_ms: countdown)
  assert decision == Answer(countdown_ms: countdown)
    as "opcode.0xbf: a second 0xBF 1 before the first 0x92 restarts the client's countdown, so it is answered"
  assert camp.finished(running) == Ok(Finished) as "one 0xC0 finishes it"
}

pub fn a_cancel_clears_a_running_camp_and_is_never_answered_test() -> Nil {
  use <- owned_test.run(5000)
  let #(running, _) =
    camp.requested(camp.none(), start: True, countdown_ms: countdown)
  let #(cleared, decision) =
    camp.requested(running, start: False, countdown_ms: countdown)
  assert decision == Cancelled
  assert camp.finished(cleared) == Error(FinishedWithNoCamp)
    as "the client sends 0xC0 only for a camp the server started and the client has not cancelled: after a cancel it is refused"
}

pub fn a_cancel_with_no_camp_changes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(none, decision) =
    camp.requested(camp.none(), start: False, countdown_ms: countdown)
  assert decision == Ignored
    as "lua.ExitWindow.OnPlayerCampCancel: the exit window sends 0xBF 0 after any cancelling 0x92, with no camp running"
  assert camp.finished(none) == Error(FinishedWithNoCamp)
  assert camp.requested(none, start: True, countdown_ms: countdown).1
    == Answer(countdown_ms: countdown)
    as "and a camp can still start"
}

pub fn a_finish_with_no_camp_is_refused_and_says_why_test() -> Nil {
  use <- owned_test.run(5000)
  assert camp.finished(camp.none()) == Error(FinishedWithNoCamp)
    as "opcode.0xc0: the client sends it at most once per camp and only while one runs"
  let text = camp.describe(FinishedWithNoCamp)
  assert string.contains(text, "0x00C0") && string.contains(text, "no camp")
    as "the line names the message and what is wrong with it"
}

/// Every sequence of 0xBF starts (True) and cancels (False) of `length`.
fn sequences(length: Int) -> List(List(Bool)) {
  case length {
    0 -> [[]]
    _ ->
      list.flat_map(sequences(length - 1), fn(shorter) {
        [[True, ..shorter], [False, ..shorter]]
      })
  }
}

pub fn a_camp_runs_exactly_when_the_last_request_was_a_start_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(list.flat_map([0, 1, 2, 3, 4, 5, 6], sequences), fn(sequence) {
    let #(state, last) =
      list.fold(sequence, #(camp.none(), None), fn(held, start) {
        let #(state, _) = held
        let #(state, decision) =
          camp.requested(state, start:, countdown_ms: countdown)
        #(state, Some(#(start, decision)))
      })
    assert camp.finished(state)
      == case last {
        Some(#(True, _)) -> Ok(Finished)
        Some(#(False, _)) | None -> Error(FinishedWithNoCamp)
      }
      as "the client's 0xBF 1 starts a camp and its 0xBF 0 clears it, whatever came before"
  })
}
