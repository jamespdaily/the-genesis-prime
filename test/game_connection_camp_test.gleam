//// The game connection's rule (`genesis_prime/game/connection`), run as the
//// pure function it is: inputs in, new state and effects out, with the
//// client's messages built by `game_client`. These tests cover the camp.

import character_support
import connection_rule_support as support
import game_client
import game_connection_support
import genesis_prime/account_session.{Claimed}
import genesis_prime/client_connection.{
  type Answer, type Message, AskStore, FromHandOff, FromMap, FromSessions,
  FromStore,
}
import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/game_settings.{GameSettings}
import genesis_prime/hand_off.{NoHolder}
import genesis_prime/message/camp_countdown
import genesis_prime/message/character_list
import genesis_prime/message/disconnect_reason.{
  AccountDisconnected, LostUserServer,
}
import genesis_prime/step.{
  type ConnectionEvent, type Event, type Outcome, CancelTimer, EndedBeforeAnswer,
  LogError, LogWarning, Map, NoAnswerInTime, NotRunning, OtherSocketFailure,
  OwnEffect, OwnEvent, StartTimer, StoppedWaiting, TimerId, Unwatch, WatchEnded,
  WatchId,
}
import genesis_prime/store.{
  AccountId, CharacterLoaded, ForSelect, ForWorld, ListCharacters, Listed,
  Select, Unavailable,
}
import genesis_prime/world_map/map.{Left}
import gleam/bit_array
import gleam/list
import gleam/option.{None, Some}
import owned_test

// ---- the camp ----
//
// Expected values come from the Client trace of the camp step and the facts it
// names: opcode.0xbf and opcode.0xc0 (the client's two camp messages, each
// inside 0x038C, 0xC0 sent at most once per camp and, for a Quit, at any time
// after the 0x92), opcode.0x92 and vector.opcode.0x92.body (the countdown, the
// cancel bit and the signature bonuses, 285 bytes),
// opcode.0x92.countdown_source and opcode.0x92.countdown_range (the length is
// the server's, under 60 s), lua.ExitWindow.OnPlayerCampCancel (a cancelling
// 0x92 is answered with another 0xBF 0, so the server sends none),
// opcode.0x594 and vector.opcode.0x594.body (the byte 01 is the bit set and
// reason 0), opcode.0x594.character_select (the client sends 0x7E0 only and the
// server answers it as at login), opcode.0x594.world_teardown (0x7EA and 0x549
// may follow) and opcode.0x262 (a unit id the client has seen is refused). The
// order of the save, the leave and 0x594, what each failure does and the
// shell's order for a close are the Design artifact's sequence and failure
// table.

/// The body of the 0x92 for a countdown with the cancel bit clear and every
/// bonus 0: the countdown in 32 bits, then 2248 zero bits (the cancel bit, the
/// 32-bit experience and elder points and the 34 amounts of 64 bits), which
/// pad the 2273 bits to the 285 bytes of vector.opcode.0x92.body.
fn countdown_body(countdown_ms: Int) -> BitArray {
  <<countdown_ms:size(32)-little, 0:size(2248)>>
}

pub fn message_0xbf_1_in_the_world_is_answered_with_one_0x92_of_the_settings_countdown_and_every_bonus_0_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.in_world(),
      game_connection_support.camp_request_message(True),
    )
  let assert [Frame(message_id: 0x0092, body:)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
    as "opcode.0xbf: sending 1 starts nothing on the client, which waits for the server's 0x92 (opcode.0x92)"
  assert body == countdown_body(12_345)
    as "vector.opcode.0x92.body's layout: the countdown in ms, the cancel bit 0 and the bonuses 0, 285 bytes; the countdown is the settings' 12,345 ms, not the default"
  assert bit_array.byte_size(body) == 285
  let assert Ok(decoded) = camp_countdown.decode(body)
  assert decoded
    == camp_countdown.CampCountdown(
      countdown_ms: 12_345,
      cancel: 0,
      experience: 0,
      elder_points: 0,
      currencies: <<0:size(960)>>,
      account_currencies: <<0:size(1216)>>,
    )
    as "opcode.0x92: 15 currencies and 19 account currencies of 64 bits, none given"
  assert support.asked(taken) == None && !support.stops(taken)
  assert support.logs(taken) == []
    as "the rule takes 0xBF, so it is no unhandled message"
}

pub fn the_countdown_in_0x92_is_the_one_in_the_game_settings_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([0, 1, 59_999], fn(countdown_ms) {
    let game =
      GameSettings(
        ..game_connection_support.settings().game,
        camp_countdown_ms: countdown_ms,
      )
    let fresh =
      game_connection_support.accepted(
        Settings(..game_connection_support.settings(), game:),
      ).0
    let #(state, _) =
      game_connection_support.entered_from(
        game_connection_support.in_select_from(fresh),
        game_connection_support.world_character(),
      )
    let #(_, taken) =
      game_connection_support.read(
        state,
        game_connection_support.camp_request_message(True),
      )
    let assert [Frame(message_id: 0x0092, body:)] =
      game_connection_support.heard(taken, game_connection_support.keyed())
    assert body == countdown_body(countdown_ms)
      as "opcode.0x92.countdown_range: the settings' time in ms, under 60 s, whatever it is"
  })
}

pub fn message_0xbf_0_during_a_camp_writes_nothing_and_a_following_0xc0_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.read(
      game_connection_support.camping(),
      game_connection_support.camp_request_message(False),
    )
  assert support.writes(taken) == []
    as "lua.ExitWindow.OnPlayerCampCancel: the client cleared its own camp, and a cancelling 0x92 would be answered by another 0xBF 0 without end"
  assert support.asked(taken) == None && !support.stops(taken)
  assert support.logs(taken) == []
  let #(state, taken) =
    game_connection_support.read(
      state,
      game_connection_support.camp_finished_message(),
    )
  let assert [line] = support.logs_of(step: taken, level: LogError)
    as "opcode.0xc0: the client sends it only for a camp the server started, so it is one the client never sends"
  assert support.says(line, "0x00C0") && support.says(line, "no camp")
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      game_connection_support.entry_place(),
    )
    as "the last good place is saved, as for a refused move"
  assert support.writes(taken) == []
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  assert support.effects_of(taken) == [step.Stop]
    as "nothing is written to a client that is no client"
}

pub fn message_0xbf_0_with_no_camp_writes_nothing_and_the_connection_goes_on_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.read(
      game_connection_support.in_world(),
      game_connection_support.camp_request_message(False),
    )
  assert support.writes(taken) == []
    as "lua.ExitWindow.OnPlayerCampCancel: the exit window sends it after any cancelling 0x92, with no camp running"
  assert support.asked(taken) == None && !support.stops(taken)
  assert support.logs(taken) == []
    as "it is taken and changes nothing: no unhandled line, no error"
  let #(_, taken) =
    game_connection_support.read(
      state,
      game_connection_support.camp_request_message(True),
    )
  assert game_connection_support.written_ids(taken) == [0x0092]
    as "a camp can still start"
}

pub fn a_second_0xbf_1_during_a_camp_is_answered_with_a_second_0x92_and_one_0xc0_finishes_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.read(
      game_connection_support.camping(),
      game_connection_support.camp_request_message(True),
    )
  let assert [Frame(message_id: 0x0092, body:)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
    as "opcode.0xbf: a second 0xBF 1 before the first 0x92 arrives restarts the client's countdown, so each is answered"
  assert body == countdown_body(12_345)
  let #(_, taken) =
    game_connection_support.read(
      state,
      game_connection_support.camp_finished_message(),
    )
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      game_connection_support.entry_place(),
    )
    as "one camp: one 0xC0 finishes it, and a save is asked once"
  assert support.logs(taken) == []
}

pub fn message_0xc0_at_once_after_the_0x92_as_a_quit_sends_it_is_taken_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.in_world(),
      bit_array.concat([
        game_connection_support.camp_request_message(True),
        game_connection_support.camp_finished_message(),
      ]),
    )
  assert game_connection_support.written_ids(taken) == [0x0092]
    as "opcode.0xc0: a Quit sends 0xC0 at any time after the 0x92, before the countdown ends, and the server cannot tell it from a camp's"
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      game_connection_support.entry_place(),
    )
    as "the camp finishes at once: the save is asked"
  assert support.logs(taken) == []
}

pub fn message_0xc0_with_no_camp_ends_the_connection_with_an_error_the_last_good_place_saved_and_nothing_written_test() -> Nil {
  use <- owned_test.run(10_000)
  let state =
    game_connection_support.moved_to(
      state: game_connection_support.in_world(),
      x: 4.5,
      y: 5.5,
      z: 6.5,
    )
  let #(state, taken) =
    game_connection_support.read(
      state,
      game_connection_support.camp_finished_message(),
    )
  let assert [line] = support.logs_of(step: taken, level: LogError)
    as "opcode.0xc0: the client sends it at most once per camp and only while a camp runs"
  assert support.says(line, "0x00C0")
  assert line.about.character_id == Some(42)
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      game_connection_support.standing_at(x: 4.5, y: 5.5, z: 6.5),
    )
    as "the last place the player stood at is saved"
  assert support.writes(taken) == []
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  assert support.effects_of(taken) == [step.Stop]
    as "no 0x0594 and no notice: nothing is written"
}

pub fn message_0xc0_cancels_the_save_timer_saves_the_place_asks_the_map_run_to_let_the_player_leave_then_writes_0x594_with_the_byte_01_in_that_order_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = game_connection_support.saving_the_camp()
  assert support.effects_of(taken)
    == [
      OwnEffect(step.LeaveGroup(step.CharacterNamed("ab cd"))),
      OwnEffect(step.LeaveGroup(game_connection_support.zone_group(4961))),
      OwnEffect(CancelTimer(TimerId(2))),
    ]
    as "the player leaves its chat groups, and the 60 s save timer is cancelled before the save, so none fires while the player leaves"
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      game_connection_support.entry_place(),
    )
    as "the place is saved first"
  assert support.writes(taken) == []
  let #(state, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  assert game_connection_support.ask_request(taken)
    == game_connection_support.leave_asked()
    as "then the map's run that took the player is asked to take it out"
  let assert Some(ask) = support.asked(taken)
  assert ask.deadline_ms == support.now_ms + 4000
    as "the settings' ask deadline from the time of the input"
  assert support.writes(taken) == []
    as "nothing is written before the leave is answered: the client can pick a character only after 0x594, so a play never meets a save still out"
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromMap(Left)),
    )
  assert game_connection_support.heard(taken, game_connection_support.keyed())
    == [Frame(message_id: 0x0594, body: <<1>>)]
    as "vector.opcode.0x594.body: the byte 01 is the bit set and reason 0, which returns to character select"
  assert support.asked(taken) == None && !support.stops(taken)
  assert list.first(support.effects_of(taken)) == Ok(Unwatch(WatchId(2)))
    as "the watch on the map is dropped before 0x0594 is written: the map holds the player no longer"
  assert support.logs(taken) == []
}

pub fn after_0x594_a_0x07e0_is_answered_with_0x0036_and_0x0117_as_at_login_with_no_new_claim_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = game_connection_support.camped_out()
  let #(state, taken) =
    game_connection_support.read(state, game_connection_support.select_start())
  assert game_connection_support.ask_request(taken)
    == AskStore(Select(ListCharacters(AccountId(7))))
    as "opcode.0x594.character_select: the client's new character select sends 0x7E0 only, and the list is built as at login, from the store"
  assert support.effects_of(taken) == []
    as "no claim: the connection holds the account's slot still, and no watch is opened"
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(
          ForSelect(
            Listed([
              game_connection_support.character(id: 5, name: "Eve", seed: 1),
            ]),
          ),
        ),
      ),
    )
  let assert [
    Frame(message_id: 0x097F, ..),
    Frame(message_id: 0x0968, ..),
    Frame(message_id: 0x0036, ..),
    Frame(message_id: 0x0117, body:),
  ] = game_connection_support.heard(taken, game_connection_support.keyed())
    as "opcode.0x97f, opcode.0x968, opcode.0x36 then opcode.0x117, as at login"
  let assert Ok(sent) = character_list.decode(body)
  assert list.map(sent.characters, fn(entry) { entry.name }) == ["Eve"]
}

pub fn after_a_camp_a_play_request_enters_the_world_again_as_a_new_unit_with_the_map_watched_and_the_save_timer_started_again_test() -> Nil {
  use <- owned_test.run(10_000)
  // The real map rule answers every ask: the first join, the leave, the second.
  let #(state, taken) = game_connection_support.joining()
  let #(map_state, joined) =
    game_connection_support.mapped(
      map_state: game_connection_support.map_with_four_players(),
      taken:,
    )
  let #(state, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromMap(joined)),
    )
  let first_unit = game_connection_support.player_in(taken).unit_id
  let #(state, _) =
    game_connection_support.read(
      state,
      game_connection_support.camp_request_message(True),
    )
  let #(state, taken) =
    game_connection_support.read(
      state,
      game_connection_support.camp_finished_message(),
    )
  let #(state, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  let #(map_state, left) = game_connection_support.mapped(map_state:, taken:)
  assert left == Left as "the map took the player out"
  let #(state, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromMap(left)),
    )
  assert game_connection_support.written_ids(taken) == [0x0594]
  let #(state, taken) =
    game_connection_support.read(state, game_connection_support.select_start())
  let #(state, _) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForSelect(Listed([])))),
    )
  let #(state, taken) = game_connection_support.playing_from(state, 42)
  let #(state, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(
          ForWorld(CharacterLoaded(
            game_connection_support.world_character(),
            character_support.epoch(1),
            None,
          )),
        ),
      ),
    )
  let #(_, joined_again) = game_connection_support.mapped(map_state:, taken:)
  let #(state, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromMap(joined_again)),
    )
  assert game_connection_support.written_ids(taken)
    == game_client.world_entry_ids
    as "the same nine messages as at the first entry"
  assert game_connection_support.player_in(taken).unit_id != first_unit
    && game_connection_support.player_in(taken).unit_id == 6
    as "opcode.0x262: the client refuses a unit id it has seen, so the play is a new unit: the map's next id after the five it gave"
  assert support.watches(taken)
    == [
      #(
        WatchId(2),
        Map(
          game_connection_support.camp_map(),
          game_connection_support.incarnation,
        ),
      ),
    ]
    as "the map is watched again, under the same watch id the leave dropped"
  assert list.contains(
    support.effects_of(taken),
    OwnEffect(StartTimer(TimerId(2), 60_000)),
  )
    as "the save timer starts again"
  let #(_, taken) =
    game_connection_support.read(
      state,
      game_connection_support.camp_finished_message(),
    )
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    as "the new life has no camp: a 0xC0 at once is refused"
}

pub fn moving_during_a_camp_keeps_the_camp_and_the_place_saved_at_0xc0_is_the_last_one_moved_to_test() -> Nil {
  use <- owned_test.run(10_000)
  let state =
    game_connection_support.moved_to(
      state: game_connection_support.camping(),
      x: 1.5,
      y: 2.5,
      z: 3.5,
    )
  let state = game_connection_support.moved_to(state:, x: 7.5, y: 8.5, z: 9.5)
  let #(state, taken) =
    game_connection_support.read(
      state,
      game_connection_support.camp_finished_message(),
    )
  assert support.logs(taken) == []
    as "lua.ExitWindow.OnCancel: nothing cancels the camp on the client but its exit window, so moving leaves it, and the finish is taken"
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      game_connection_support.standing_at(x: 7.5, y: 8.5, z: 9.5),
    )
    as "the place saved is the last one the client said the player stood at"
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  assert game_connection_support.ask_request(taken)
    == game_connection_support.leave_asked()
}

pub fn a_camp_save_the_store_cannot_make_is_a_warning_and_the_leave_goes_on_to_0x594_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(game_connection_support.no_answers(), fn(outcome) {
    let #(state, taken) = game_connection_support.saving_the_camp()
    let #(state, taken) =
      game_connection_support.answer(state:, taken:, outcome:)
    let assert [line] = support.logs_of(step: taken, level: LogWarning)
      as "an outside failure the server recovered from"
    assert support.says(line, "not saved")
    assert line.about.character_id == Some(42)
    assert game_connection_support.ask_request(taken)
      == game_connection_support.leave_asked()
      as "the last 60 s save stands: the player leaves all the same"
    assert !support.stops(taken)
    let #(_, taken) =
      game_connection_support.answer(
        state:,
        taken:,
        outcome: step.Answer(FromMap(Left)),
      )
    assert game_connection_support.written_ids(taken) == [0x0594]
      as "and the client is returned to character select"
  })
}

pub fn a_client_that_closes_after_0xc0_gets_its_save_its_leave_and_0x594_in_that_order_and_the_close_is_taken_after_them_without_a_second_save_test() -> Nil {
  use <- owned_test.run(10_000)
  // A Quit sends 0xC0 and the client ends itself. The shell takes no other
  // input while an ask is out, so the close waits: it is the rule's input
  // only once the 0x594 step is done, in character select.
  let #(state, taken) = game_connection_support.camped_out()
  assert game_connection_support.written_ids(taken) == [0x0594]
    as "the save, the leave and 0x594 all ran before the close was taken"
  let #(_, taken) =
    game_connection_support.feed(state, OwnEvent(step.PeerClosed))
  assert support.effects_of(taken) == [step.Stop]
    as "the client's close in character select ends the connection"
  assert support.asked(taken) == None
    as "no second save: the place was saved at 0xC0"
  let #(_, taken) =
    game_connection_support.feed(
      state,
      OwnEvent(step.WriteFailed(OtherSocketFailure(reason: "closed"))),
    )
  assert support.stops(taken) && support.asked(taken) == None
    as "the write of 0x0594 may have failed because the client is gone: the connection ends, and saves nothing"
}

pub fn a_leave_answered_not_running_or_ended_before_its_answer_still_writes_0x594_and_returns_to_character_select_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([NotRunning, EndedBeforeAnswer], fn(outcome) {
    let #(state, taken) = game_connection_support.leaving_the_map()
    let #(state, taken) =
      game_connection_support.answer(state:, taken:, outcome:)
    assert game_connection_support.written_ids(taken) == [0x0594]
      as "the map run that held the player is gone, and its player with it: the leave is done"
    assert list.contains(support.effects_of(taken), Unwatch(WatchId(2)))
      as "the watch on the map is dropped, with an end already queued behind the ask"
    assert !support.stops(taken)
    let #(_, taken) =
      game_connection_support.read(
        state,
        game_connection_support.select_start(),
      )
    assert game_connection_support.ask_request(taken)
      == AskStore(Select(ListCharacters(AccountId(7))))
      as "the client is in character select: its 0x07E0 asks the store"
  })
}

pub fn the_map_ending_while_the_camp_save_is_out_returns_the_client_to_character_select_not_reason_8_test() -> Nil {
  use <- owned_test.run(10_000)
  // The map's end waits behind the save, which the shell takes no input
  // during. When the save is answered the leave finds no run (`NotRunning`),
  // and its step's `Unwatch` drops the end that waited, so the rule never
  // takes it.
  let #(state, taken) = game_connection_support.leaving_the_map()
  assert game_connection_support.ask_request(taken)
    == game_connection_support.leave_asked()
  let #(_, taken) =
    game_connection_support.answer(state:, taken:, outcome: NotRunning)
  assert game_connection_support.written_ids(taken) == [0x0594]
    as "the client is told to return to character select"
  assert !support.stops(taken)
    && !list.contains(game_connection_support.written_ids(taken), 0x036A)
    as "and not told 'Lost connection with user server.' (reason 8)"
  assert list.contains(support.effects_of(taken), Unwatch(WatchId(2)))
    as "the queued end of watch 2 is dropped with the watch"
}

pub fn a_leave_that_gets_no_answer_in_time_tells_the_client_reason_8_and_ends_the_connection_with_no_second_save_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = game_connection_support.leaving_the_map()
  let #(_, taken) =
    game_connection_support.answer(state:, taken:, outcome: NoAnswerInTime)
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == LostUserServer
    as "0x1400168a0: 8; the map may still hold the player, and its watch on the connection drops it"
  assert support.asked(taken) == None
    as "the place was saved at 0xC0: no second save"
  let assert [line] = support.logs_of(step: taken, level: LogWarning)
  assert support.says(line, "the map")
}

pub fn the_server_stopping_during_the_camp_save_or_the_leave_stops_the_connection_with_no_second_save_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = game_connection_support.saving_the_camp()
  let #(_, taken) =
    game_connection_support.answer(state:, taken:, outcome: StoppedWaiting)
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == LostUserServer
    as "the server never ends a connection after the hello without telling the client"
  assert support.asked(taken) == None && support.logs(taken) == []
    as "the stop is no failure, and the leave is not asked"
  let #(state, taken) = game_connection_support.leaving_the_map()
  let #(_, taken) =
    game_connection_support.answer(state:, taken:, outcome: StoppedWaiting)
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == LostUserServer
  assert support.asked(taken) == None && support.logs(taken) == []
    as "no second save, and no 0x594"
}

/// The answers a leave never gets: those of the store, the hand-off and
/// Sessions, and the map's join.
fn answers_to_no_leave() -> List(Outcome(Answer)) {
  [
    game_connection_support.place_saved(),
    step.Answer(FromStore(Unavailable)),
    step.Answer(FromHandOff(NoHolder)),
    step.Answer(FromSessions(Claimed)),
    step.Answer(FromMap(game_connection_support.a_join_answer())),
  ]
}

pub fn an_answer_in_the_leave_that_is_not_the_maps_is_a_bug_with_reason_8_an_error_and_no_save_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(answers_to_no_leave(), fn(outcome) {
    let #(state, taken) = game_connection_support.leaving_the_map()
    let #(_, taken) = game_connection_support.answer(state:, taken:, outcome:)
    assert game_connection_support.disconnect(
        taken,
        game_connection_support.keyed(),
      )
      == LostUserServer
    assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    assert support.asked(taken) == None
      as "the place was saved at 0xC0: a bug ends the connection without saving again"
  })
}

/// The inputs that end a connection, as they reach the rule.
fn ending_inputs() -> List(Event(ConnectionEvent(Message, Answer))) {
  [
    OwnEvent(step.PeerClosed),
    OwnEvent(step.ReadFailed(OtherSocketFailure(reason: "gone"))),
    OwnEvent(step.WriteFailed(OtherSocketFailure(reason: "gone"))),
    step.Stopping(deadline_ms: 9000),
    game_connection_support.taken_over(),
  ]
}

pub fn an_end_reached_during_the_leave_saves_nothing_more_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = game_connection_support.leaving_the_map()
  list.each(ending_inputs(), fn(event) {
    let #(_, taken) = game_connection_support.feed(state, event)
    assert support.asked(taken) == None
      as "the place was saved at 0xC0: the end of a connection that is leaving its map saves nothing more"
    assert support.stops(taken)
  })
}

pub fn an_end_reached_during_the_camp_save_never_saves_a_second_time_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = game_connection_support.saving_the_camp()
  list.each(ending_inputs(), fn(event) {
    let #(_, taken) = game_connection_support.feed(state, event)
    assert support.asked(taken) == None
    assert support.stops(taken)
  })
}

pub fn a_takeover_during_the_camp_saves_first_and_one_after_it_is_the_one_of_character_select_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.feed(
      game_connection_support.camping(),
      game_connection_support.taken_over(),
    )
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      game_connection_support.entry_place(),
    )
    as "as in the world today: the place is saved before the client is told"
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == AccountDisconnected
  let #(state, _) = game_connection_support.camped_out()
  let #(_, taken) =
    game_connection_support.feed(state, game_connection_support.taken_over())
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == AccountDisconnected
    as "taken after the answers, when the connection is between steps: in character select, with no player to save"
  assert support.asked(taken) == None
}

pub fn the_end_of_sessions_during_a_camp_claims_again_with_the_player_in_the_world_and_the_camp_kept_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.claiming_again(game_connection_support.camping())
  let #(state, taken) = game_connection_support.claimed(state:, taken:)
  assert support.writes(taken) == []
  let #(_, taken) =
    game_connection_support.read(
      state,
      game_connection_support.camp_finished_message(),
    )
  assert support.logs(taken) == []
    as "the camp is kept in the player's world state, so the claim again leaves it running and the 0xC0 is taken"
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      game_connection_support.entry_place(),
    )
}

pub fn the_end_of_the_map_during_a_camp_saves_the_place_then_tells_the_client_reason_8_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.feed(
      game_connection_support.camping(),
      WatchEnded(WatchId(2)),
    )
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      game_connection_support.entry_place(),
    )
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == LostUserServer
    as "a map that ends while the camp counts down takes its player with it: as today, the client is told"
}

/// The ids of the messages the client's old world and its camp may send in
/// character select, which the rule does not take there.
fn world_ids() -> List(Int) {
  [0x07EA, 0x0549, 0x00BF, 0x00C0]
}

pub fn a_0x038c_holding_0x7ea_0x549_0xbf_or_0xc0_in_character_select_is_logged_as_unhandled_and_the_connection_goes_on_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(after_camp, _) = game_connection_support.camped_out()
  list.each([game_connection_support.in_select(), after_camp], fn(state) {
    list.each(world_ids(), fn(id) {
      let #(_, taken) =
        game_connection_support.read(
          state,
          game_connection_support.world_message(id, <<1>>),
        )
      assert support.unhandled_ids(taken) == [Some(#("unhandled", id))]
        as "opcode.0x594.world_teardown: the client's old world may send 0x7EA and 0x549 around 0x7E0, and the camp messages are taken in the world only; each is logged under its own id"
      assert !support.stops(taken) && support.writes(taken) == []
      assert support.asked(taken) == None
    })
  })
}

pub fn an_answer_in_the_camp_save_that_is_not_the_stores_is_a_bug_with_reason_8_an_error_and_no_leave_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(game_connection_support.answers_to_other_asks(), fn(outcome) {
    let #(state, taken) = game_connection_support.saving_the_camp()
    let #(_, taken) = game_connection_support.answer(state:, taken:, outcome:)
    assert game_connection_support.disconnect(
        taken,
        game_connection_support.keyed(),
      )
      == LostUserServer
    assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    assert support.asked(taken) == None
      as "the save is over and the camp's leave is not asked: a bug ends the connection without a second save"
  })
}
