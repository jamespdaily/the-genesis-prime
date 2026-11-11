//// The game connection's rule (`genesis_prime/game/connection`), run as the
//// pure function it is: inputs in, new state and effects out, with the
//// client's messages built by `game_client`. These tests cover one login per
//// account: the claim after the hand-off, the watch on Sessions, a takeover
//// and the timers that wait to claim again, and the messages the rule names.
////

import connection_rule_support as support
import game_connection_support
import genesis_prime/account_session.{Claimed, TakenOver}
import genesis_prime/client_connection.{
  type Request, AskStore, FromHandOff, FromSessions, FromStore, SentBySessions,
}
import genesis_prime/connection/frame
import genesis_prime/coverage/sent_message
import genesis_prime/game/connection as game_connection
import genesis_prime/hand_off.{Kept}
import genesis_prime/message/disconnect_reason.{
  AccountDisconnected, LostUserServer,
}
import genesis_prime/step.{
  type ConnectionStep, ConnectionId, EndedBeforeAnswer, LogError, LogInfo,
  LogWarning, NoAnswerInTime, NotRunning, OwnEffect, OwnEvent, Sessions,
  StartTimer, StoppedWaiting, TimerFired, TimerId, Unwatch, Watch, WatchEnded,
  WatchId, Woken,
}
import genesis_prime/store.{AccountId, ListCharacters, Select, Unavailable}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import login_support
import owned_test

// ---- one login per account ----
//
// Expected values come from these places: the rule's doc comment (the claim
// follows the hand-off and comes before the list; Sessions ending is claimed
// again after a short wait; a takeover disconnects the old connection), 0x036A
// reason 19 for a takeover and reason 8 for the server's own failure
// (0x1400168a0, opcode.0x36a), and the claim's contract in
// `genesis_prime/account_session`. The wait is 100 ms and the retries of a claim that
// finds Sessions not running are 5, as the rule's constants state.

/// The wait, in milliseconds, before a claim is made again.
const claim_wait_ms = 100

/// How many times a claim that finds Sessions not running is made again.
const claim_retries = 5

pub fn after_the_hand_off_the_account_is_claimed_with_a_watch_on_sessions_before_the_list_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, claim) = game_connection_support.claiming()
  assert support.effects_of(claim) == [Watch(WatchId(1), Sessions)]
    as "the rule watches Sessions with the claim, under its one watch id"
  assert game_connection_support.ask_request(claim)
    == game_connection_support.claim_ask()
  let assert Some(ask) = support.asked(claim)
  assert ask.deadline_ms == support.now_ms + 4000
    as "the settings' ask deadline from the time of the input"
  // 0x07E0 arriving while the claim is out waits; the list is asked only after
  // Sessions answers.
  let #(state, taken) =
    game_connection_support.read(state, game_connection_support.select_start())
  assert support.asked(taken) == None
  assert support.effects_of(taken) == []
  let #(_, taken) = game_connection_support.claimed(state:, taken: claim)
  assert game_connection_support.ask_request(taken)
    == AskStore(Select(ListCharacters(AccountId(7))))
    as "the claim comes before the list: the frame that waited is taken once Sessions answers"
}

/// A step that ended the connection as a takeover does: 0x036A reason 19 under
/// the connection's cipher (0x1400168a0: 19 is 'This account has been
/// disconnected', the account-level text), one info line naming the connection
/// and the account, no ask, and no warning or error.
fn assert_taken_over(taken: ConnectionStep(Request)) -> Nil {
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == AccountDisconnected
  let assert [line] = support.logs_of(step: taken, level: LogInfo)
    as "the takeover is logged at info, once"
  assert line.about.connection == Some(ConnectionId(1))
    && line.about.account_id == Some(7)
    as "the line names the connection and the account"
  assert support.asked(taken) == None
  assert support.logs_of(step: taken, level: LogWarning) == []
  assert support.logs_of(step: taken, level: LogError) == []
}

pub fn a_connection_given_taken_over_writes_0x036a_reason_19_under_its_cipher_and_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    game_connection_support.feed(
      game_connection_support.in_select_with_a_list(),
      game_connection_support.taken_over(),
    )
  assert_taken_over(taken)
}

pub fn a_claim_answered_taken_over_ends_the_connection_as_a_takeover_does_test() -> Nil {
  use <- owned_test.run(10_000)
  // A newer login holds the slot: Sessions answers the claim `TakenOver`, for
  // a first claim and for a claim made again after Sessions ended in
  // character select.
  let #(state, taken) = game_connection_support.claiming()
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromSessions(TakenOver)),
    )
  assert_taken_over(taken)
  let #(state, taken) =
    game_connection_support.claiming_again(
      game_connection_support.in_select_with_a_list(),
    )
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromSessions(TakenOver)),
    )
  assert_taken_over(taken)
}

pub fn a_claim_made_again_in_the_world_and_answered_taken_over_saves_the_place_then_tells_the_client_reason_19_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.claiming_again(game_connection_support.in_world())
  let #(state, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromSessions(TakenOver)),
    )
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      game_connection_support.entry_place(),
    )
    as "a player in the world is saved before the client is told"
  assert support.writes(taken) == [] as "the notice follows the save's answer"
  let assert [line] = support.logs_of(step: taken, level: LogInfo)
    as "the takeover is logged at info, once, with the ask"
  assert line.about.account_id == Some(7)
  let #(_, saved) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  assert game_connection_support.disconnect(
      saved,
      game_connection_support.keyed(),
    )
    == AccountDisconnected
  assert support.logs(saved) == []
}

pub fn a_claim_made_again_in_the_world_that_sessions_does_not_answer_saves_the_place_then_tells_the_client_reason_8_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([NoAnswerInTime, EndedBeforeAnswer], fn(outcome) {
    let #(state, taken) =
      game_connection_support.claiming_again(game_connection_support.in_world())
    let #(state, taken) =
      game_connection_support.answer(state:, taken:, outcome:)
    assert game_connection_support.ask_request(taken)
      == game_connection_support.save_asked(
        1,
        game_connection_support.entry_place(),
      )
      as "a player in the world is saved before the client is told"
    assert support.writes(taken) == [] as "the notice follows the save's answer"
    let #(_, saved) =
      game_connection_support.answer(
        state:,
        taken:,
        outcome: game_connection_support.place_saved(),
      )
    assert game_connection_support.disconnect(
        saved,
        game_connection_support.keyed(),
      )
      == LostUserServer
  })
}

pub fn a_takeover_while_the_connection_waits_to_claim_again_ends_it_with_reason_19_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_select_with_a_list(),
      WatchEnded(WatchId(1)),
    )
  let #(_, taken) =
    game_connection_support.feed(state, game_connection_support.taken_over())
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == AccountDisconnected
    as "a takeover Sessions sent before it ended still disconnects the old connection"
}

pub fn a_message_sessions_never_sends_or_one_before_the_claim_is_a_bug_with_an_error_and_the_end_test() -> Nil {
  use <- owned_test.run(10_000)
  let answer_as_a_message =
    OwnEvent(Woken(message: SentBySessions(message: Claimed)))
  list.each(
    [
      game_connection_support.feed(
        game_connection_support.in_select(),
        answer_as_a_message,
      ).1,
      game_connection_support.feed(
        game_connection_support.connected(),
        game_connection_support.taken_over(),
      ).1,
      game_connection_support.feed(
        login_support.replied().0,
        game_connection_support.taken_over(),
      ).1,
    ],
    fn(taken) {
      assert support.stops(taken)
      assert list.length(support.logs_of(step: taken, level: LogError)) == 1
      assert support.writes(taken) == []
        as "a connection that was no one's session has nothing to be told"
    },
  )
}

pub fn the_end_of_the_watch_on_sessions_starts_a_timer_and_its_firing_claims_again_from_where_the_connection_is_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.feed(
      game_connection_support.in_select_with_a_list(),
      WatchEnded(WatchId(1)),
    )
  assert support.effects_of(taken)
    == [OwnEffect(StartTimer(TimerId(1), claim_wait_ms))]
    as "Sessions is likely still restarting, so the claim waits a moment"
  assert support.asked(taken) == None
  // Bytes that arrive during the wait are kept for after the claim.
  let #(state, taken) =
    game_connection_support.read(state, game_connection_support.select_start())
  assert support.asked(taken) == None && support.effects_of(taken) == []
  let #(state, taken) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(1))))
  assert support.effects_of(taken) == [Watch(WatchId(1), Sessions)]
    as "the ended watch is forgotten, so the one watch is opened again under its id"
  assert game_connection_support.ask_request(taken)
    == game_connection_support.claim_ask()
  assert support.writes(taken) == [] as "the client sees nothing"
  let #(_, taken) = game_connection_support.claimed(state:, taken:)
  assert game_connection_support.ask_request(taken)
    == AskStore(Select(ListCharacters(AccountId(7))))
    as "Claimed puts the connection back in character select with its state, and the 0x07E0 that waited is taken"
}

pub fn a_second_end_of_sessions_claims_again_under_the_same_watch_id_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_select_with_a_list(),
      WatchEnded(WatchId(1)),
    )
  let #(state, taken) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(1))))
  let state = game_connection_support.claimed(state:, taken:).0
  let #(state, taken) =
    game_connection_support.feed(state, WatchEnded(WatchId(1)))
  assert support.effects_of(taken)
    == [OwnEffect(StartTimer(TimerId(1), claim_wait_ms))]
  let #(_, taken) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(1))))
  assert support.effects_of(taken) == [Watch(WatchId(1), Sessions)]
}

pub fn a_watch_or_timer_the_rule_did_not_open_is_a_bug_with_an_error_and_the_end_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(waiting, _) =
    game_connection_support.feed(
      game_connection_support.in_select_with_a_list(),
      WatchEnded(WatchId(1)),
    )
  list.each(
    [
      game_connection_support.feed(
        game_connection_support.in_select_with_a_list(),
        WatchEnded(WatchId(9)),
      ).1,
      game_connection_support.feed(
        game_connection_support.in_select_with_a_list(),
        OwnEvent(TimerFired(TimerId(1))),
      ).1,
      game_connection_support.feed(waiting, WatchEnded(WatchId(1))).1,
      game_connection_support.feed(waiting, OwnEvent(TimerFired(TimerId(2)))).1,
      game_connection_support.feed(
        login_support.replied().0,
        WatchEnded(WatchId(1)),
      ).1,
      game_connection_support.feed(
        game_connection_support.connected(),
        OwnEvent(TimerFired(TimerId(1))),
      ).1,
    ],
    fn(taken) {
      assert support.stops(taken)
      assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    },
  )
}

pub fn a_claim_timer_that_fires_while_the_claims_ask_is_out_is_a_bug_with_an_error_and_the_end_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(claim_after_the_hand_off, _) = game_connection_support.claiming()
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_select_with_a_list(),
      WatchEnded(WatchId(1)),
    )
  let #(claim_after_the_watch_ended, taken) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(1))))
  assert game_connection_support.ask_request(taken)
    == game_connection_support.claim_ask()
    as "the timer's firing made the claim, so its ask is out"
  list.each([claim_after_the_hand_off, claim_after_the_watch_ended], fn(state) {
    let #(_, taken) =
      game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(1))))
    assert support.stops(taken)
      as "the timer is waited on only before the claim is asked; a second claim would put two asks out"
    assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    assert support.asked(taken) == None
  })
}

pub fn a_claim_that_finds_sessions_not_running_is_made_again_after_a_wait_up_to_the_retries_then_reason_8_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = game_connection_support.claiming()
  let retry = fn(held: #(game_connection.State, ConnectionStep(Request)), _try) {
    let #(state, taken) = held
    let #(state, taken) =
      game_connection_support.answer(state:, taken:, outcome: NotRunning)
    assert support.effects_of(taken)
      == [Unwatch(WatchId(1)), OwnEffect(StartTimer(TimerId(1), claim_wait_ms))]
      as "the watch on a Sessions that is not running is dropped, and the claim waits"
    assert support.asked(taken) == None
    assert support.writes(taken) == []
    let #(state, taken) =
      game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(1))))
    assert support.effects_of(taken) == [Watch(WatchId(1), Sessions)]
    assert game_connection_support.ask_request(taken)
      == game_connection_support.claim_ask()
    #(state, taken)
  }
  let #(state, taken) =
    int.range(from: 1, to: claim_retries + 1, with: #(state, taken), run: retry)
  let #(_, taken) =
    game_connection_support.answer(state:, taken:, outcome: NotRunning)
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == LostUserServer
    as "after the retries the client is told the server failed, or it would wait on its prompt for good"
  let assert [line] = support.logs_of(step: taken, level: LogWarning)
  assert support.says(line:, words: "sessions was not running")
}

pub fn a_claim_that_finds_sessions_not_running_after_its_end_is_made_again_with_the_same_bound_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_select_with_a_list(),
      WatchEnded(WatchId(1)),
    )
  let #(state, taken) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(1))))
  let #(state, taken) =
    game_connection_support.answer(state:, taken:, outcome: NotRunning)
  assert support.effects_of(taken)
    == [Unwatch(WatchId(1)), OwnEffect(StartTimer(TimerId(1), claim_wait_ms))]
  let #(_, taken) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(1))))
  assert game_connection_support.ask_request(taken)
    == game_connection_support.claim_ask()
}

pub fn a_claim_sessions_does_not_answer_gets_0x036a_reason_8_a_warning_and_the_connection_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([NoAnswerInTime, EndedBeforeAnswer], fn(outcome) {
    let #(state, taken) = game_connection_support.claiming()
    let #(_, taken) = game_connection_support.answer(state:, taken:, outcome:)
    assert game_connection_support.disconnect(
        taken,
        game_connection_support.keyed(),
      )
      == LostUserServer
      as "0x1400168a0: 8 is 'Lost connection with user server.', as for the store"
    let assert [line] = support.logs_of(step: taken, level: LogWarning)
    assert line.about.peer == Some(support.peer)
    assert line.about.account_id == Some(7)
  })
  // A claim that Sessions does not answer on a claim made again after its end.
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_select_with_a_list(),
      WatchEnded(WatchId(1)),
    )
  let #(state, taken) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(1))))
  let #(_, taken) =
    game_connection_support.answer(state:, taken:, outcome: NoAnswerInTime)
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == LostUserServer
}

pub fn an_answer_to_the_claim_that_is_none_a_claim_gets_is_a_bug_with_reason_8_and_an_error_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      step.Answer(FromStore(Unavailable)),
      step.Answer(FromHandOff(Kept)),
    ],
    fn(outcome) {
      let #(state, taken) = game_connection_support.claiming()
      let #(_, taken) = game_connection_support.answer(state:, taken:, outcome:)
      assert game_connection_support.disconnect(
          taken,
          game_connection_support.keyed(),
        )
        == LostUserServer
      assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    },
  )
}

pub fn the_server_stopping_while_a_claim_is_out_or_waited_for_gets_reason_8_with_no_log_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = game_connection_support.claiming()
  let #(_, out) =
    game_connection_support.answer(state:, taken:, outcome: StoppedWaiting)
  assert game_connection_support.disconnect(
      out,
      game_connection_support.keyed(),
    )
    == LostUserServer
  assert support.logs(out) == [] as "a stop is no failure"
  let #(waiting, _) =
    game_connection_support.feed(
      game_connection_support.in_select_with_a_list(),
      WatchEnded(WatchId(1)),
    )
  let #(_, stopping) =
    game_connection_support.feed(waiting, step.Stopping(deadline_ms: 9000))
  assert game_connection_support.disconnect(
      stopping,
      game_connection_support.keyed(),
    )
    == LostUserServer
  let #(_, closed) =
    game_connection_support.feed(waiting, step.OwnEvent(step.PeerClosed))
  assert support.effects_of(closed) == [step.Stop]
    as "a client that closes while the connection waits is not told"
}

pub fn a_takeover_queued_behind_a_failing_store_ask_ends_with_reason_8_not_reason_19_test() -> Nil {
  use <- owned_test.run(10_000)
  // The shell takes no other input while an ask is out, so a takeover that
  // arrives meanwhile is taken after the ask's outcome; the outcome here ends
  // the connection, so the takeover is never taken. This is the gap the rule
  // states: the client gets the server-failure text, not the account's. Both
  // end the connection.
  let #(state, taken) = game_connection_support.listing()
  let #(_, taken) =
    game_connection_support.answer(state:, taken:, outcome: NoAnswerInTime)
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == LostUserServer
    as "a failing ask ends with reason 8 though a takeover waits behind it"
}

pub fn the_game_rule_names_the_client_messages_it_takes_test() -> Nil {
  use <- owned_test.run(10_000)
  let named = list.sort(game_connection.taken_message_ids(), int.compare)
  assert named
    == [
      0x0097, 0x009A, 0x009D, 0x00B3, 0x00BB, 0x00BE, 0x00BF, 0x00C0, 0x00D5,
      0x00F2, 0x00FB, 0x00FC, 0x012B, 0x0149, 0x015A, 0x0166, 0x0167, 0x016F,
      0x017D, 0x0180, 0x0182, 0x018F, 0x01C3, 0x01D4, 0x023C, 0x023D, 0x023E,
      0x023F, 0x0240, 0x0241, 0x025B, 0x025C, 0x0269, 0x0352, 0x0356, 0x035A,
      0x035B, 0x035D, 0x035E, 0x0360, 0x0364, 0x0365, 0x038C, 0x03EC, 0x03ED,
      0x04DB, 0x0570, 0x058F, 0x0637, 0x063A, 0x063B, 0x0786, 0x07DD, 0x07E0,
      0x07EA, 0x0801, 0x0805,
    ]
    as "the ids the rule's doc comment lists, with the dropped reports and requests of genesis_prime/game/dropped (0x023C, 0x0240, 0x023F, 0x023E, 0x023D, 0x012B, 0x0180, 0x03ED, 0x03EC, 0x0269, 0x018F and 0x0570 inside the world carrier, and 0x0241 on its own): 0x058F, 0x07E0, 0x07DD, 0x025C with the 0x025B it carries, 0x0352, 0x0786, the world carrier 0x038C (the direct ids of sent_message, fact 0x140332920, and 0x038C, fact 0x1403f4900), and the movement, camp and chat messages of the player in the world, 0x0637, 0x063A, 0x00D5, 0x063B, 0x00F2, 0x00FB, 0x00FC, 0x00BF, 0x00C0, 0x01C3 and 0x01D4, the cast messages 0x009A, 0x0097, 0x009D, 0x04DB, 0x0801 and 0x0805 (opcode.0x9a, opcode.0x97, opcode.0x9d, opcode.0x4db, opcode.0x801, opcode.0x805), the use of a unit with no activate spell, 0x00B3 (opcode.0xb3), the choice of how to come back, 0x015A (opcode.0x15a), the choice of an innate, 0x016F (opcode.0x16f), the interaction messages 0x07EA and 0x0356 (opcode.0x7ea, opcode.0x356), the move of a held item, 0x0182 (opcode.0x182), the split of a stack, 0x017D (opcode.0x17d), the destroy of a held item, 0x0149 (opcode.0x149), the buy from a vendor and the buy back of a sold item, 0x00BE and 0x00BB (opcode.0xbe, opcode.0xbb), the sale to a vendor and the sale of junk, 0x0166 and 0x0167 (opcode.0x166, opcode.0x167), the accept and retry of a quest, 0x035B and 0x0365 (opcode.0x35b, opcode.0x365), and the turn-in of a quest, 0x035D (opcode.0x35d)"
  assert list.sort(game_connection.carried_message_ids(), int.compare)
    == [
      0x0097, 0x009A, 0x009D, 0x00B3, 0x00BB, 0x00BE, 0x00BF, 0x00C0, 0x00D5,
      0x00F2, 0x00FB, 0x00FC, 0x012B, 0x0149, 0x015A, 0x0166, 0x0167, 0x016F,
      0x017D, 0x0180, 0x0182, 0x018F, 0x01C3, 0x01D4, 0x023C, 0x023D, 0x023E,
      0x023F, 0x0240, 0x0269, 0x0356, 0x035A, 0x035B, 0x035D, 0x035E, 0x0360,
      0x0364, 0x0365, 0x03EC, 0x03ED, 0x04DB, 0x0570, 0x0637, 0x063A, 0x063B,
      0x07EA, 0x0801, 0x0805,
    ]
    as "the movement, camp, chat, cast, death, innate, interaction, quest, inventory and dropped report and request messages are taken only with the player in the world"
}

pub fn character_select_takes_exactly_the_ids_the_rule_names_and_logs_every_other_client_id_as_unhandled_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) = game_connection_support.listed(characters: [])
  let named = game_connection.taken_message_ids()
  list.each(sent_message.all(), fn(id) {
    let #(_, taken) =
      game_connection_support.read(
        state,
        game_connection_support.keyed_message(id, <<>>),
      )
    let logged_unhandled =
      support.unhandled_ids(taken) == [Some(#("unhandled", id))]
    // 0x025B travels only inside 0x025C, so on its own it is no message the
    // rule takes (opcode.0x25c), and the movement messages are taken only with
    // the player in the world; every other named id is taken as sent.
    let taken_as_sent =
      list.contains(named, id)
      && id != 0x025B
      && !list.contains(game_connection.carried_message_ids(), id)
    assert logged_unhandled == !taken_as_sent
      as {
        "id "
        <> int.to_string(id)
        <> ": logged as unhandled exactly when the rule's list does not name it"
      }
  })
}

pub fn the_create_carrier_takes_only_the_message_the_rule_names_as_carried_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) = game_connection_support.listed(characters: [])
  list.each(sent_message.all(), fn(id) {
    let assert Ok(carried) = frame.encode(id, <<>>)
      as "the carried frame encodes"
    let #(_, taken) =
      game_connection_support.read(
        state,
        game_connection_support.keyed_message(0x025C, carried),
      )
    let refused_as_not_0x025b =
      list.any(support.logs(taken), support.says(_, words: "not 0x025B"))
    assert refused_as_not_0x025b == { id != 0x025B }
      as {
        "id "
        <> int.to_string(id)
        <> " inside 0x025C: opcode.0x25c, 0x025C carries a 0x025B and no other message"
      }
  })
}
