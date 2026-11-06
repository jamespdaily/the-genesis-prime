//// The game connection's rule (`genesis_prime/game/connection`), run as the
//// pure function it is: inputs in, new state and effects out, with the
//// client's messages built by `game_client`. These tests cover the player
//// moving and the saves of its place.

import connection_rule_support as support
import game_client
import game_connection_support
import genesis_prime/client_connection.{type Answer, type Message, FromStore}
import genesis_prime/connection/frame
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/game/start_place.{Facing}
import genesis_prime/message/disconnect_reason.{
  AccountDisconnected, LostUserServer,
}
import genesis_prime/message/fall_value.{FallValue}
import genesis_prime/message/fell_below_floor.{FellBelowFloor}
import genesis_prime/message/move_speed_setting.{MoveSpeedSetting}
import genesis_prime/message/movement_command
import genesis_prime/message/movement_platform.{MovementPlatform}
import genesis_prime/message/movement_send_interval_answer.{
  MovementSendIntervalAnswer,
}
import genesis_prime/message/world_zone_changed.{WorldZoneChanged}
import genesis_prime/step.{
  type ConnectionEvent, type Event, CancelTimer, LogError, LogInfo, LogWarning,
  NoAnswerInTime, NotRunning, OtherSocketFailure, OwnEffect, OwnEvent,
  StartTimer, StoppedWaiting, TimerFired, TimerId, Unwatch, WatchEnded, WatchId,
}
import genesis_prime/store.{ForMove, NothingSaved, PlaceRefused}
import gleam/bit_array
import gleam/list
import gleam/option.{None, Some}
import owned_test

// ---- the player moves, and the place is saved ----
//
// Expected values come from the Client trace of the move step and the facts it
// names: opcode.0x637 (the message, its kinds, no echo), opcode.0x639 and
// opcode.0x638 (the server writes neither while the player moves),
// movement_command.position_bound, movement_command.kind_24 and kind_27,
// 0x140c45dd0 (the move speed setting), 0x140715350 (kind 14 is yaw, pitch and
// roll), 0x1404586e0 (0x262's kind 2 places the unit and a bit clear places it
// at once), opcode.0xad (the world and position it loads at), and 0x1400168a0
// (0x036A's reasons). The 60 s period, the order of the saves and what a drop
// writes are the step's own design: the Design artifact of the move step and
// its failure table.

fn platform_command(unit_id: Int) -> movement_command.MovementCommand {
  movement_command.Platform(MovementPlatform(unit_id:))
}

pub fn the_client_moving_gets_no_answer_and_every_later_move_is_read_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.read(
      game_connection_support.in_world(),
      game_connection_support.moves_message([
        game_client.position_command(x: 1.5, y: 2.5, z: 3.5),
      ]),
    )
  assert support.writes(taken) == []
    as "opcode.0x637: the server sends nothing in answer: no echo, no acknowledgement, no 0x638 for a unit under the client's control and no 0x639, which would end the client's control"
  assert support.asked(taken) == None && !support.stops(taken)
  assert support.logs(taken) == []
    as "the rule takes 0x637, so it is no unhandled message"
  let #(state, taken) =
    game_connection_support.read(
      state,
      bit_array.concat([
        game_connection_support.moves_message([
          game_client.position_command(x: 2.5, y: 2.5, z: 3.5),
        ]),
        game_connection_support.moves_message([
          game_client.position_command(x: 3.5, y: 2.5, z: 3.5),
        ]),
        support.ping(1),
      ]),
    )
  assert support.writes(taken) == [support.pong(1)]
    as "each move is read, and only the ping is answered"
  assert support.logs(taken) == []
  let #(_, taken) =
    game_connection_support.feed(state, step.OwnEvent(step.PeerClosed))
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      game_connection_support.standing_at(x: 3.5, y: 2.5, z: 3.5),
    )
    as "the moves were all read: the last one is where the player stands"
}

pub fn the_place_kept_is_the_last_world_position_and_a_platforms_frame_is_not_kept_test() -> Nil {
  use <- owned_test.run(10_000)
  let state =
    game_connection_support.read(
      game_connection_support.in_world(),
      bit_array.concat([
        game_connection_support.moves_message([
          game_client.position_command(x: 5.5, y: 6.5, z: 7.5),
        ]),
        game_connection_support.moves_message([
          platform_command(9),
          game_client.position_command(x: 100.0, y: 100.0, z: 100.0),
        ]),
        game_connection_support.moves_message([
          game_client.position_command(x: 200.0, y: 200.0, z: 200.0),
        ]),
      ]),
    ).0
  let #(_, taken) =
    game_connection_support.feed(state, step.OwnEvent(step.PeerClosed))
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      game_connection_support.standing_at(x: 5.5, y: 6.5, z: 7.5),
    )
    as "opcode.0x637: a kind 2 under a platform is in that unit's frame, and the client sends only what changed, so the next message's kind 2 is under the platform still"
  let state =
    game_connection_support.read(
      state,
      game_connection_support.moves_message([
        platform_command(0),
        game_client.position_command(x: 8.5, y: 9.5, z: 10.5),
        game_client.rotation_command(yaw: 1.5, pitch: -0.25, roll: 0.5),
      ]),
    ).0
  let #(_, taken) =
    game_connection_support.feed(state, step.OwnEvent(step.PeerClosed))
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      start_place.turned(
        game_connection_support.standing_at(x: 8.5, y: 9.5, z: 10.5),
        Facing(yaw: 1.5, pitch: -0.25, roll: 0.5),
      ),
    )
    as "kind 1 at 0 is the world's frame again: the position and the rotation are kept"
}

pub fn a_position_beyond_the_worlds_box_is_kept_as_the_client_sent_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let state =
    game_connection_support.moved_to(
      state: game_connection_support.in_world(),
      x: 40_000.0,
      y: 3000.0,
      z: -40_000.0,
    )
  let #(_, taken) =
    game_connection_support.feed(state, step.OwnEvent(step.PeerClosed))
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      game_connection_support.standing_at(x: 40_000.0, y: 3000.0, z: -40_000.0),
    )
    as "movement_command.position_bound: x and z beyond 32768 and y above 2048 come from the client's own frames at the edge, so they are kept as sent"
}

pub fn a_command_the_clients_code_never_sends_ends_the_connection_after_saving_the_last_good_place_and_writes_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let state =
    game_connection_support.moved_to(
      state: game_connection_support.in_world(),
      x: 7.5,
      y: 8.5,
      z: 9.5,
    )
  list.each(game_connection_support.refused_messages(), fn(refused) {
    let #(bytes, what) = refused
    let #(refusing, taken) = game_connection_support.read(state, bytes)
    let assert [line] = support.logs_of(step: taken, level: LogError)
      as { what <> ": one error line says what the client sent" }
    assert line.about.account_id == Some(7)
      && line.about.character_id == Some(42)
      as "and whose it is"
    assert game_connection_support.ask_request(taken)
      == game_connection_support.save_asked(
        1,
        game_connection_support.standing_at(x: 7.5, y: 8.5, z: 9.5),
      )
      as {
        what
        <> ": the last good place is saved, and nothing of the message is kept"
      }
    assert support.writes(taken) == []
      as "nothing is written to a client that sent what its own code never does"
    assert !support.stops(taken)
      as "the connection ends once the save is answered"
    let #(_, taken) =
      game_connection_support.answer(
        state: refusing,
        taken:,
        outcome: game_connection_support.place_saved(),
      )
    assert support.effects_of(taken) == [step.Stop]
      as {
        what <> ": the save answered, the connection ends with nothing written"
      }
  })
}

/// The bodies of the messages the rule decodes and keeps nothing of.
fn decoded_and_dropped() -> List(#(Int, BitArray)) {
  let assert Ok(zone) =
    world_zone_changed.encode(WorldZoneChanged(
      old_world_zone_id: 6009,
      new_world_zone_id: 4962,
    ))
  let assert Ok(interval) =
    movement_send_interval_answer.encode(MovementSendIntervalAnswer(
      field_1: 4,
      field_2: 1,
      field_3: 14,
    ))
  let assert Ok(speed) =
    move_speed_setting.encode(MoveSpeedSetting(move_speed: 2))
  let assert Ok(fall) = fall_value.encode(FallValue(field_1: 0x40490FDB))
  let assert Ok(floor) =
    fell_below_floor.encode(FellBelowFloor(
      no_ground: 1,
      camera_x: 0x3F800000,
      camera_y: 0x40000000,
      camera_z: 0xC0400000,
    ))
  [
    #(0x063A, zone),
    #(0x00D5, interval),
    #(0x063B, speed),
    #(0x00FB, fall),
    #(0x00FC, floor),
  ]
}

pub fn the_clients_0x063a_0x00d5_0x063b_0x00fb_and_0x00fc_are_decoded_and_the_connection_goes_on_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(decoded_and_dropped(), fn(message) {
    let #(message_id, body) = message
    let #(state, taken) =
      game_connection_support.read(
        game_connection_support.in_world(),
        game_connection_support.world_message(message_id, body),
      )
    assert support.logs(taken) == []
      as "opcode.0x63a, opcode.0xd5, opcode.0x63b, opcode.0xfb and opcode.0xfc: the rule takes each, so none is logged as unhandled"
    assert support.writes(taken) == [] && support.asked(taken) == None
    assert !support.stops(taken) as "none ends the connection"
    let #(_, taken) = game_connection_support.read(state, support.ping(1))
    assert support.writes(taken) == [support.pong(1)]
      as "the connection goes on"
  })
}

pub fn a_body_of_one_of_the_movement_messages_that_the_clients_reader_would_refuse_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([0x0637, 0x063A, 0x00D5, 0x063B, 0x00F2, 0x00FB, 0x00FC], fn(id) {
    let #(state, taken) =
      game_connection_support.read(
        game_connection_support.in_world(),
        game_connection_support.world_message(id, <<>>),
      )
    let assert [line] = support.logs_of(step: taken, level: LogError)
      as "an empty body is shorter than any of the messages' fields"
    assert support.says(line:, words: "does not decode")
    assert game_connection_support.ask_request(taken)
      == game_connection_support.save_asked(
        1,
        game_connection_support.entry_place(),
      )
      as "the player is in the world, so its place is saved before the connection ends"
    let #(_, taken) =
      game_connection_support.answer(
        state:,
        taken:,
        outcome: game_connection_support.place_saved(),
      )
    assert support.effects_of(taken) == [step.Stop]
  })
}

pub fn the_movement_messages_before_the_world_are_logged_as_unhandled_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([0x0637, 0x063A, 0x00D5, 0x063B, 0x00F2, 0x00FB, 0x00FC], fn(id) {
    let #(_, taken) =
      game_connection_support.read(
        game_connection_support.in_select_with_a_list(),
        game_connection_support.world_message(id, <<0, 0, 0, 0>>),
      )
    assert support.unhandled_ids(taken) == [Some(#("unhandled", id))]
      as "no player is in the world in character select, so there is no place to keep: the message is logged as unhandled as before"
    assert !support.stops(taken)
  })
}

pub fn a_movement_message_sent_on_its_own_and_not_inside_0x038c_is_logged_as_unhandled_even_in_the_world_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([0x0637, 0x063A, 0x00D5, 0x063B, 0x00F2, 0x00FB, 0x00FC], fn(id) {
    let #(_, taken) =
      game_connection_support.read(
        game_connection_support.in_world(),
        game_connection_support.move_message(id),
      )
    assert support.unhandled_ids(taken) == [Some(#("unhandled", id))]
      as "opcode.0x38c, opcode.0x637: the client sends every world message inside 0x038C and no other way, so one on its own is no message the rule takes"
    assert !support.stops(taken) && support.asked(taken) == None
  })
}

pub fn the_clients_0x0635_is_still_logged_as_unhandled_in_the_world_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.in_world(),
      game_connection_support.world_message(0x0635, <<0, 0, 0, 0>>),
    )
  assert support.unhandled_ids(taken) == [Some(#("unhandled", 0x0635))]
    as "opcode.0x635 answers 0x636 and is no part of the move step"
  assert !support.stops(taken)
}

// ---- every 60 s ----

pub fn the_save_timer_starts_when_the_player_enters_the_world_test() -> Nil {
  use <- owned_test.run(10_000)
  assert list.contains(
    support.effects_of(game_connection_support.entered().1),
    OwnEffect(StartTimer(TimerId(2), 60_000)),
  )
    as "a save every 60 s from the moment the player is in the world"
}

pub fn every_60_seconds_the_last_known_position_is_saved_also_when_no_move_came_since_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      OwnEvent(TimerFired(TimerId(2))),
    )
  assert support.effects_of(taken)
    == [OwnEffect(StartTimer(TimerId(2), 60_000))]
    as "the timer starts again at its firing"
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      game_connection_support.entry_place(),
    )
    as "opcode.0x637: a player standing still sends no 0x637, so the save writes the last place known, the one it entered at"
  let assert Some(ask) = support.asked(taken)
  assert ask.deadline_ms == support.now_ms + 4000
    as "the settings' ask deadline from the time of the input"
  assert support.writes(taken) == []
  let #(state, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  assert support.effects_of(taken) == [] && support.asked(taken) == None
    as "a saved place needs nothing more: the player goes on playing"
  let #(state, taken) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(2))))
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      2,
      game_connection_support.entry_place(),
    )
    as "the second save of the login is numbered 2"
  let #(state, _) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  let state =
    game_connection_support.moved_to(state: state, x: 1.5, y: 2.5, z: 3.5)
  let #(_, taken) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(2))))
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      3,
      game_connection_support.standing_at(x: 1.5, y: 2.5, z: 3.5),
    )
    as "a move since the last save is in the next"
}

pub fn a_frame_that_arrives_while_the_save_is_out_waits_and_is_taken_after_the_answer_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      OwnEvent(TimerFired(TimerId(2))),
    )
  let #(state, held) = game_connection_support.read(state, support.ping(4))
  assert support.writes(held) == [] as "the ask is out: the frame waits"
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  assert support.writes(taken) == [support.pong(4)]
    as "taken once the answer comes, in the order it arrived"
}

pub fn a_60_s_save_the_store_cannot_make_is_a_warning_the_player_goes_on_and_the_next_timer_asks_again_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(game_connection_support.no_answers(), fn(outcome) {
    let #(state, taken) =
      game_connection_support.feed(
        game_connection_support.in_world(),
        OwnEvent(TimerFired(TimerId(2))),
      )
    let #(state, taken) =
      game_connection_support.answer(state:, taken:, outcome:)
    let assert [line] = support.logs_of(step: taken, level: LogWarning)
      as "an outside failure the server recovered from"
    assert line.about.account_id == Some(7)
      && line.about.character_id == Some(42)
      && line.about.map == Some(game_connection_support.camp_map())
      as "the line says who and where"
    assert !support.stops(taken) && support.writes(taken) == []
      as "the player stays in the world"
    let #(_, taken) =
      game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(2))))
    assert game_connection_support.ask_request(taken)
      == game_connection_support.save_asked(
        2,
        game_connection_support.entry_place(),
      )
      as "the next timer tries again, with the next number"
  })
}

pub fn a_60_s_save_that_changed_nothing_is_an_info_line_and_one_the_database_refused_is_an_error_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      OwnEvent(TimerFired(TimerId(2))),
    )
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForMove(NothingSaved))),
    )
  let assert [line] = support.logs(taken)
  assert line.level == LogInfo
    as "a later login holds the character, or a newer save of this one was stored first: nothing is wrong"
  assert !support.stops(taken)
  let #(state, taken) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      OwnEvent(TimerFired(TimerId(2))),
    )
  let #(state, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(
          ForMove(PlaceRefused(constraint: "character_position_is_finite")),
        ),
      ),
    )
  let assert [line] = support.logs(taken)
  assert line.level == LogError
    as "no place the rule keeps breaks a check, so a refusal is a bug"
  assert support.says(line, "character_position_is_finite")
    as "the log names the constraint that refused the place"
  assert !support.stops(taken)
  let #(_, taken) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(2))))
  assert support.asked(taken) != None
    as "the player goes on, and the timer tries again"
}

pub fn a_stop_during_the_60_s_save_leaves_the_player_in_the_world_and_the_stop_that_follows_saves_again_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      OwnEvent(TimerFired(TimerId(2))),
    )
  let #(state, taken) =
    game_connection_support.answer(state:, taken:, outcome: StoppedWaiting)
  assert support.effects_of(taken) == [] && !support.stops(taken)
    as "the shell's next input is Stopping, which says what the stop does"
  let #(_, taken) =
    game_connection_support.feed(state, step.Stopping(deadline_ms: 9000))
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      2,
      game_connection_support.entry_place(),
    )
    as "the save the stop cut short may have committed or not: the stop saves once more, with the next number"
}

pub fn a_drop_taken_after_a_60_s_save_saves_again_with_the_next_number_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      OwnEvent(TimerFired(TimerId(2))),
    )
  let #(state, _) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  let #(_, taken) =
    game_connection_support.feed(state, OwnEvent(step.PeerClosed))
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      2,
      game_connection_support.entry_place(),
    )
    as "the shell took the client's close after the save's answer: the drop saves, numbered after the timer's save"
}

pub fn an_answer_that_is_none_a_save_asked_for_is_a_bug_with_reason_8_and_an_error_and_no_second_save_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(game_connection_support.answers_to_other_asks(), fn(outcome) {
    let #(state, taken) =
      game_connection_support.feed(
        game_connection_support.in_world(),
        OwnEvent(TimerFired(TimerId(2))),
      )
    let #(_, taken) = game_connection_support.answer(state:, taken:, outcome:)
    assert game_connection_support.disconnect(
        taken,
        game_connection_support.keyed(),
      )
      == LostUserServer
    assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    assert support.asked(taken) == None
      as "the save is over: a bug ends the connection without saving again"
    let #(state, taken) =
      game_connection_support.feed(
        game_connection_support.in_world(),
        step.Stopping(deadline_ms: 9000),
      )
    let #(_, taken) = game_connection_support.answer(state:, taken:, outcome:)
    assert game_connection_support.disconnect(
        taken,
        game_connection_support.keyed(),
      )
      == LostUserServer
    assert support.asked(taken) == None
  })
}

// ---- every drop saves ----

/// The socket's ends the shell gives the rule, with the log lines each makes
/// before the save.
fn socket_ends() -> List(#(Event(ConnectionEvent(Message, Answer)), Int)) {
  [
    #(OwnEvent(step.PeerClosed), 0),
    #(OwnEvent(step.ReadFailed(OtherSocketFailure(reason: "broken"))), 1),
    #(OwnEvent(step.WriteFailed(OtherSocketFailure(reason: "broken"))), 1),
  ]
}

pub fn a_client_close_or_a_failed_read_or_write_saves_the_last_place_then_ends_with_nothing_written_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(socket_ends(), fn(socket_end) {
    let #(event, warnings) = socket_end
    let state =
      game_connection_support.moved_to(
        state: game_connection_support.in_world(),
        x: 7.5,
        y: 8.5,
        z: 9.5,
      )
    let #(state, taken) = game_connection_support.feed(state, event)
    assert game_connection_support.ask_request(taken)
      == game_connection_support.save_asked(
        1,
        game_connection_support.standing_at(x: 7.5, y: 8.5, z: 9.5),
      )
      as "the place the player last stood at is saved when the connection drops"
    assert !support.stops(taken) && support.writes(taken) == []
    assert list.length(support.logs_of(step: taken, level: LogWarning))
      == warnings
      as "a failed socket is a warning, a client's own close is not"
    let #(_, taken) =
      game_connection_support.answer(
        state:,
        taken:,
        outcome: game_connection_support.place_saved(),
      )
    assert support.effects_of(taken) == [step.Stop]
      as "nothing is written to a client that is gone, and no more is logged"
  })
}

pub fn a_socket_that_fails_as_closed_ends_as_a_peer_close_saves_and_logs_no_warning_test() -> Nil {
  use <- owned_test.run(10_000)
  // A write to a socket the peer has closed fails as closed, and so does
  // arming the read of one (`inet:setopts` answers einval, which the shell's
  // Erlang file reports as closed): the client's own close may be waiting in
  // the mailbox behind the step that finds it out.
  list.each([step.WriteFailed, step.ReadFailed], fn(failed) {
    let state =
      game_connection_support.moved_to(
        state: game_connection_support.in_world(),
        x: 7.5,
        y: 8.5,
        z: 9.5,
      )
    let #(state, taken) =
      game_connection_support.feed(state, OwnEvent(failed(step.Closed)))
    assert game_connection_support.ask_request(taken)
      == game_connection_support.save_asked(
        1,
        game_connection_support.standing_at(x: 7.5, y: 8.5, z: 9.5),
      )
      as "the place the player last stood at is saved, as for a peer close"
    assert support.logs_of(step: taken, level: LogWarning) == []
      as "a socket the peer closed is no warning, whichever call found it out"
    let #(_, taken) =
      game_connection_support.answer(
        state:,
        taken:,
        outcome: game_connection_support.place_saved(),
      )
    assert support.effects_of(taken) == [step.Stop]
    let #(_, taken) =
      game_connection_support.feed(
        game_connection_support.connected(),
        OwnEvent(failed(step.Closed)),
      )
    assert support.effects_of(taken) == [step.Stop]
      as "before the world the same close ends the connection with nothing logged"
  })
}

pub fn a_drop_the_store_cannot_save_is_a_warning_and_the_connection_ends_anyway_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(game_connection_support.no_answers(), fn(outcome) {
    let #(state, taken) =
      game_connection_support.feed(
        game_connection_support.in_world(),
        OwnEvent(step.PeerClosed),
      )
    let #(_, taken) = game_connection_support.answer(state:, taken:, outcome:)
    let assert [line] = support.logs_of(step: taken, level: LogWarning)
    assert line.about.character_id == Some(42)
    assert support.stops(taken) && support.writes(taken) == []
      as "the last 60 s save stands: the connection ends, a store that is away does not keep it open"
  })
  let #(state, taken) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      OwnEvent(step.PeerClosed),
    )
  let #(_, taken) =
    game_connection_support.answer(state:, taken:, outcome: StoppedWaiting)
  assert support.stops(taken) && support.logs(taken) == []
    as "the server stopping is no failure: no warning"
}

pub fn a_takeover_in_the_world_saves_the_place_then_writes_0x036a_reason_19_and_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  let state =
    game_connection_support.moved_to(
      state: game_connection_support.in_world(),
      x: 7.5,
      y: 8.5,
      z: 9.5,
    )
  let #(state, taken) =
    game_connection_support.feed(state, game_connection_support.taken_over())
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      game_connection_support.standing_at(x: 7.5, y: 8.5, z: 9.5),
    )
    as "a newer login took the account: the older connection saves at its own epoch, which changes nothing once the newer login has loaded the character"
  assert support.writes(taken) == [] && !support.stops(taken)
    as "the notice is written after the save"
  let assert [line] = support.logs_of(step: taken, level: LogInfo)
  assert line.about.account_id == Some(7)
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
    as "0x1400168a0: 19 is 'This account has been disconnected'"
  assert support.logs(taken) == []
}

pub fn the_end_of_the_players_map_saves_the_place_then_writes_0x036a_reason_8_and_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      WatchEnded(WatchId(2)),
    )
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      game_connection_support.entry_place(),
    )
  assert support.writes(taken) == [] && !support.stops(taken)
  let assert [line] = support.logs_of(step: taken, level: LogWarning)
  assert line.about.map == Some(game_connection_support.camp_map())
  let #(_, taken) =
    game_connection_support.answer(state:, taken:, outcome: NoAnswerInTime)
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == LostUserServer
    as "the player is gone from the world with its map: the client is told whether or not the save was answered"
  assert list.length(support.logs_of(step: taken, level: LogWarning)) == 1
    as "a save with no answer is a warning of its own"
}

pub fn a_notice_that_fails_to_write_after_the_leaving_save_does_not_save_again_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.taken_over(),
    )
  let #(state, _) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  let #(_, taken) =
    game_connection_support.feed(
      state,
      OwnEvent(step.WriteFailed(OtherSocketFailure(reason: "gone"))),
    )
  assert support.asked(taken) == None
    as "the leaving save was answered: the failed write of the notice ends the connection and saves nothing again"
  assert support.stops(taken)
  assert list.length(support.logs_of(step: taken, level: LogWarning)) == 1
}

pub fn an_end_reached_while_a_save_is_out_never_saves_a_second_time_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      OwnEvent(step.PeerClosed),
    )
  list.each(
    [
      OwnEvent(step.ReadFailed(OtherSocketFailure(reason: "gone"))),
      OwnEvent(step.WriteFailed(OtherSocketFailure(reason: "gone"))),
      OwnEvent(step.PeerClosed),
      step.Stopping(deadline_ms: 9000),
      game_connection_support.taken_over(),
      WatchEnded(WatchId(2)),
    ],
    fn(event) {
      let #(_, taken) = game_connection_support.feed(state, event)
      assert support.asked(taken) == None
        as "the connection is already leaving, with its save out: no second save is asked"
      assert support.stops(taken)
    },
  )
}

pub fn the_rate_and_the_held_bytes_limits_end_the_connection_in_the_world_without_a_save_test() -> Nil {
  use <- owned_test.run(10_000)
  // The last 60 s save stands: a client past a limit is no client, and the
  // limits end the connection inside the shared client connection code.
  let state =
    game_connection_support.entered_from(
      game_connection_support.in_select_from(
        game_connection_support.accepted(
          Settings(
            ..game_connection_support.settings(),
            rate: support.bucket(burst: 10, per_second: 1),
          ),
        ).0,
      ),
      game_connection_support.world_character(),
    ).0
  let #(state, taken) =
    game_connection_support.read(state, support.pings(count: 8))
  assert !support.stops(taken)
  let #(_, taken) = game_connection_support.read(state, support.ping(8))
  assert support.stops(taken) && support.asked(taken) == None
    as "a frame past the rate ends the connection and asks nothing"
  let #(_, taken) =
    game_connection_support.read(game_connection_support.in_world(), <<
      0:size(
        { support.held_limit + 1 }
        * 8
      ),
    >>)
  assert support.stops(taken) && support.asked(taken) == None
    as "bytes past the held limit end it the same way"
}

/// A 0x0244 whose body is no frame under the session key.
fn bad_wrapper() -> BitArray {
  let assert Ok(bytes) = frame.encode(0x0244, <<1, 2, 3>>)
    as "a wrapper's frame encodes"
  bytes
}

pub fn every_other_end_with_the_player_in_the_world_saves_first_test() -> Nil {
  use <- owned_test.run(10_000)
  let breaks = [
    #(
      game_connection_support.read(
        game_connection_support.in_world(),
        game_connection_support.keyed_message(0x058F, <<>>),
      ),
      "0x058F sent a second time",
    ),
    #(
      game_connection_support.read(
        game_connection_support.in_world(),
        game_connection_support.keyed_message(0x038C, <<>>),
      ),
      "a world message with no kind byte",
    ),
    #(
      game_connection_support.read(
        game_connection_support.in_world(),
        bad_wrapper(),
      ),
      "a wrapped frame that is no frame",
    ),
    #(
      game_connection_support.read(game_connection_support.in_world(), <<
        0xFF,
        0xFF,
        0x01,
        0x00,
      >>),
      "a frame of a length no frame has",
    ),
    #(
      game_connection_support.feed(
        game_connection_support.in_world(),
        WatchEnded(WatchId(9)),
      ),
      "a watch the rule did not open",
    ),
    #(
      game_connection_support.feed(
        game_connection_support.in_world(),
        OwnEvent(TimerFired(TimerId(999))),
      ),
      "a timer the rule did not start",
    ),
    #(
      game_connection_support.feed(
        game_connection_support.in_world(),
        OwnEvent(step.Answered(ask: step.AskId(99), outcome: NoAnswerInTime)),
      ),
      "an answer when no ask was out",
    ),
  ]
  list.each(breaks, fn(broken) {
    let #(#(state, taken), what) = broken
    assert game_connection_support.ask_request(taken)
      == game_connection_support.save_asked(
        1,
        game_connection_support.entry_place(),
      )
      as {
        what <> ": the connection holds a player, so its place is saved first"
      }
    assert support.writes(taken) == [] && !support.stops(taken)
    assert list.length(support.logs_of(step: taken, level: LogError)) == 1
      as "and one error line says what the client did"
    let #(_, taken) =
      game_connection_support.answer(
        state:,
        taken:,
        outcome: game_connection_support.place_saved(),
      )
    assert support.effects_of(taken) == [step.Stop]
      as { what <> ": nothing is written to a client that is no client" }
  })
}

// ---- the stop ----

pub fn the_server_stopping_in_the_world_saves_within_the_stops_deadline_then_tells_the_client_and_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      step.Stopping(deadline_ms: 9000),
    )
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      game_connection_support.entry_place(),
    )
  let assert Some(ask) = support.asked(taken)
  assert ask.deadline_ms == support.now_ms + 4000
    as "the ask's own deadline is the shorter: 4000 ms against the 8000 ms the stop leaves"
  assert support.writes(taken) == [] && !support.stops(taken)
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
    as "the save answered, the client is told 0x036A reason 8, as before"
  assert support.logs(taken) == [] as "a stop is no failure"
  let #(_, taken) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      step.Stopping(deadline_ms: 3000),
    )
  let assert Some(ask) = support.asked(taken)
  assert ask.deadline_ms == 3000
    as "a stop that leaves less than the ask's deadline bounds the save: it must be done by the stop's own deadline"
}

pub fn a_stop_whose_deadline_has_passed_skips_the_save_tells_the_client_and_ends_with_a_warning_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([support.now_ms, support.now_ms - 500], fn(deadline_ms) {
    let #(_, taken) =
      game_connection_support.feed(
        game_connection_support.in_world(),
        step.Stopping(deadline_ms:),
      )
    assert support.asked(taken) == None
      as "no time is left to ask: an ask with a deadline that has passed would only be waited for"
    assert game_connection_support.disconnect(
        taken,
        game_connection_support.keyed(),
      )
      == LostUserServer
    assert list.length(support.logs_of(step: taken, level: LogWarning)) == 1
      as "the place is not saved by this stop, and the warning says so"
  })
}

pub fn a_save_at_shutdown_the_store_cannot_make_is_a_warning_and_the_client_is_still_told_and_the_connection_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(game_connection_support.no_answers(), fn(outcome) {
    let #(state, taken) =
      game_connection_support.feed(
        game_connection_support.in_world(),
        step.Stopping(deadline_ms: 9000),
      )
    let #(_, taken) = game_connection_support.answer(state:, taken:, outcome:)
    assert game_connection_support.disconnect(
        taken,
        game_connection_support.keyed(),
      )
      == LostUserServer
    assert list.length(support.logs_of(step: taken, level: LogWarning)) == 1
  })
  let #(state, taken) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      step.Stopping(deadline_ms: 9000),
    )
  let #(_, taken) =
    game_connection_support.answer(state:, taken:, outcome: StoppedWaiting)
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == LostUserServer
  assert support.logs(taken) == []
}

pub fn a_stop_while_the_connection_waits_to_claim_again_saves_then_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      WatchEnded(WatchId(1)),
    )
  let #(state, taken) =
    game_connection_support.feed(state, step.Stopping(deadline_ms: 9000))
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      game_connection_support.entry_place(),
    )
    as "the player is in the world still, whatever the claim is doing"
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
}

pub fn a_stop_that_interrupts_the_claim_with_the_player_in_the_world_goes_back_to_the_world_and_the_stop_that_follows_saves_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      WatchEnded(WatchId(1)),
    )
  let #(state, taken) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(1))))
  assert game_connection_support.ask_request(taken)
    == game_connection_support.claim_ask()
  let #(state, taken) =
    game_connection_support.answer(state:, taken:, outcome: StoppedWaiting)
  assert !support.stops(taken) && support.writes(taken) == []
    as "the claim is cut short by the stop, with nothing told: the shell's next input is Stopping"
  let #(state, taken) =
    game_connection_support.feed(state, step.Stopping(deadline_ms: 9000))
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      game_connection_support.entry_place(),
    )
    as "a player in the world is saved by the stop whatever the claim was doing"
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
}

// ---- the save timer and the claim ----

pub fn the_save_timer_is_cancelled_while_the_connection_claims_again_and_started_on_the_claim_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      WatchEnded(WatchId(1)),
    )
  assert support.effects_of(taken)
    == [
      OwnEffect(CancelTimer(TimerId(2))),
      OwnEffect(StartTimer(TimerId(1), 100)),
    ]
    as "the save timer is cancelled with the claim's wait, so no save fires while the claim is out; a firing already queued is dropped by the shell"
  let #(state, taken) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(1))))
  let #(state, taken) = game_connection_support.claimed(state:, taken:)
  assert support.effects_of(taken)
    == [OwnEffect(StartTimer(TimerId(2), 60_000))]
    as "the claim answered, the player is in the world and the save timer runs again"
  let state =
    game_connection_support.moved_to(state: state, x: 4.5, y: 5.5, z: 6.5)
  let #(_, taken) =
    game_connection_support.feed(state, OwnEvent(step.PeerClosed))
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      game_connection_support.standing_at(x: 4.5, y: 5.5, z: 6.5),
    )
    as "the claim kept where the player stands"
}

pub fn a_claim_that_finds_sessions_not_running_keeps_the_save_timer_cancelled_until_it_is_claimed_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      WatchEnded(WatchId(1)),
    )
  let #(state, taken) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(1))))
  let #(state, taken) =
    game_connection_support.answer(state:, taken:, outcome: NotRunning)
  assert support.effects_of(taken)
    == [Unwatch(WatchId(1)), OwnEffect(StartTimer(TimerId(1), 100))]
    as "the claim is made again after a wait, and the save timer is not started in between"
  let #(state, taken) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(1))))
  let #(_, taken) = game_connection_support.claimed(state:, taken:)
  assert support.effects_of(taken)
    == [OwnEffect(StartTimer(TimerId(2), 60_000))]
}

pub fn a_save_timer_that_fires_while_the_connection_claims_again_is_a_bug_that_saves_and_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(waiting, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      WatchEnded(WatchId(1)),
    )
  let #(claiming, _) =
    game_connection_support.feed(waiting, OwnEvent(TimerFired(TimerId(1))))
  list.each([waiting, claiming], fn(state) {
    let #(state, taken) =
      game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(2))))
    assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    assert game_connection_support.ask_request(taken)
      == game_connection_support.save_asked(
        1,
        game_connection_support.entry_place(),
      )
      as "the player is in the world, so even this end saves"
    let #(_, taken) =
      game_connection_support.answer(
        state:,
        taken:,
        outcome: game_connection_support.place_saved(),
      )
    assert support.effects_of(taken) == [step.Stop]
  })
}

pub fn the_save_timer_firing_in_character_select_is_a_bug_with_an_error_and_the_end_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    game_connection_support.feed(
      game_connection_support.in_select_with_a_list(),
      OwnEvent(TimerFired(TimerId(2))),
    )
  assert support.stops(taken) && support.asked(taken) == None
    as "no player is in the world, so no save timer runs, and there is nothing to save"
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
}
