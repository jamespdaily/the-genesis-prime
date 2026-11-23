//// The sitting bot on the whole server: it and a player see each other appear, hear each
//// other's say lines and leave, it replays the moves of the player it follows, and a SIGTERM to
//// the node ends it.
//// Every wait is for bytes the server writes, with a deadline a passing test never
//// reaches. The tree, the logins and the players come from `game_wire_support`.

import driven_time
import game_client
import game_wire_support.{
  type Seat, Seat, new_player, send_play, unit_of, wait_for_frame,
}
import genesis_prime/message/float32
import genesis_prime/message/movement_command
import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/movement_state_flags
import genesis_prime/message/movement_velocity
import genesis_prime/message/relayed_movement
import genesis_prime/message/unit_create_player
import genesis_prime/message/unit_destroyed
import genesis_prime/message/unit_movement
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/sitting_bot
import gleam/erlang/process
import gleam/list
import gleam/option
import login_support
import open_wait
import owned_test
import pog
import unitest

// ---- the sitting bot on the whole server ----

/// Every event the bot reports, in order, up to and including the first for
/// which `done` holds of what has been seen so far; the test fails when the bot
/// reports no more within the event deadline.
fn events_until(
  events events: process.Subject(sitting_bot.Event),
  seen seen: List(sitting_bot.Event),
  done done: fn(List(sitting_bot.Event)) -> Bool,
) -> List(sitting_bot.Event) {
  case done(seen) {
    True -> list.reverse(seen)
    False -> {
      let event =
        open_wait.received(
          from: events,
          what: "the bot's report of what the test waits for",
        )
      events_until(events:, seen: [event, ..seen], done:)
    }
  }
}

pub fn a_sitting_bot_and_a_player_see_each_other_appear_hear_each_others_say_lines_and_the_player_sees_the_bot_leave_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let started = login_support.start(time:)
  let #(zed, zed_character) =
    new_player(started:, number: 1, character_name: "Zed Qu")
  send_play(game: zed, character_id: zed_character)
  let #(_burst, zed_have) = game_client.read_entry_kept(game: zed, have: <<>>)
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let assert Ok(seat) = sitting_bot.seat(pool:, near: "Zed Qu")
    as "the bot is seated near the player"
  let events = process.new_subject()
  let finished = process.new_subject()
  let bot =
    process.spawn_unlinked(fn() {
      process.send(
        finished,
        sitting_bot.sit(
          ports: login_support.ports(started),
          seat:,
          near: "Zed Qu",
          schedule: sitting_bot.Schedule(
            walk: sitting_bot.client_circle,
            chat_every_ms: 300,
            whisper_every_ms: 600,
            press: option.None,
          ),
          // Past the test's deadline: only the stop can end the bot inside it.
          for_ms: 300_000,
          report: fn(event) { process.send(events, event) },
        ),
      )
    })
  // The player sees the bot appear, then says a line the bot can hear.
  let zed_seat = Seat(game: zed, have: zed_have, zone_channel: 0)
  let #(appeared, zed_seat) = wait_for_frame(seat: zed_seat, message_id: 0x0262)
  let assert Ok(bot_unit) = unit_create_player.decode(appeared.body)
  assert bot_unit.name == "Sitting Bot"
    as "the player sees the bot's unit appear"
  game_client.say(game: zed, text: "hello bot", chat_message_id: 1)
  // The bot's own say reaches the player on Say, from the bot's name.
  let #(heard_by_player, have) =
    game_client.read_chat(game: zed, have: zed_seat.have)
  let zed_seat = Seat(..zed_seat, have:)
  assert heard_by_player
    == game_client.HeardLine(
      channel_type: 4,
      channel_id: 0,
      sender: "Sitting Bot",
      text: "bot say 1",
    )
    as "the sitting bot's first line is a say with the counter 1, and the player reads it"
  // The bot saw the player appear and heard the player's say.
  let heard_by_bot =
    sitting_bot.LineHeard(line: game_client.HeardLine(
      channel_type: 4,
      channel_id: 0,
      sender: "Zed Qu",
      text: "hello bot",
    ))
  let accepted_for_bot =
    sitting_bot.LineAccepted(chat_message_id: 1, name: "Sitting Bot")
  let seen_by_bot =
    events_until(events:, seen: [], done: fn(seen) {
      list.contains(seen, heard_by_bot) && list.contains(seen, accepted_for_bot)
    })
  assert list.contains(
    seen_by_bot,
    sitting_bot.UnitShown(unit_id: 1, name: "Zed Qu"),
  )
    as "the bot is shown the player's unit, the map's first, with its name"
  assert list.contains(seen_by_bot, heard_by_bot)
    as "the bot hears the player's say"
  assert list.contains(seen_by_bot, accepted_for_bot)
    as "the bot's first line, numbered 1 as the client numbers, is answered with its accept"
  // The bot stops and leaves: the player sees its unit go.
  sitting_bot.request_stop(bot)
  let tally =
    open_wait.received(
      from: finished,
      what: "the bot to end when asked to stop",
    )
  assert tally.lines_heard >= 1
    && tally.units_seen >= 1
    && tally.lines_sent >= 1
    as "the summary counts what the bot sent, was shown and heard"
  let #(gone, _zed_seat) = wait_for_frame(seat: zed_seat, message_id: 0x0355)
  let assert Ok(destroyed) = unit_destroyed.decode(gone.body)
  assert destroyed.unit_id == bot_unit.unit_id
    as "the bot's unit is removed for the player when the bot closes its connection"
  game_client.close(game: zed)
  login_support.stop(started)
}

pub fn a_sitting_bot_that_follows_replays_the_named_players_moves_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let started = login_support.start(time:)
  let #(zed, zed_character) =
    new_player(started:, number: 1, character_name: "Zed Qu")
  send_play(game: zed, character_id: zed_character)
  let #(_burst, zed_have) = game_client.read_entry_kept(game: zed, have: <<>>)
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let assert Ok(seat) = sitting_bot.seat(pool:, near: "Zed Qu")
  let finished = process.new_subject()
  let bot =
    process.spawn_unlinked(fn() {
      process.send(
        finished,
        sitting_bot.sit(
          ports: login_support.ports(started),
          seat:,
          near: "Zed Qu",
          schedule: sitting_bot.Schedule(
            walk: sitting_bot.Follow(delay_ms: 200),
            chat_every_ms: 600_000,
            whisper_every_ms: 600_000,
            press: option.None,
          ),
          for_ms: 60_000,
          report: fn(_event) { Nil },
        ),
      )
    })
  let zed_seat = Seat(game: zed, have: zed_have, zone_channel: 0)
  let #(appeared, zed_seat) = wait_for_frame(seat: zed_seat, message_id: 0x0262)
  let bot_unit = unit_of(appeared)
  // The player walks: a position, a velocity, a rotation and a state, as the
  // client's own batch holds them (opcode.0x637).
  let velocity =
    movement_velocity.MovementVelocity(
      x: 0x3C00,
      y: 0x0000,
      z: 0x4000,
      blends: 1,
    )
  let rotation = MovementRotation(yaw: 0x3F000000, pitch: 0, roll: 0, blends: 0)
  let flags = movement_state_flags.MovementStateFlags(flags: 0x1)
  game_client.send_world(
    game: zed,
    message_id: 0x0637,
    body: game_client.moves_body(client_clock: 0x1234, commands: [
      game_client.position_command(x: 100.5, y: 50.25, z: -200.75),
      movement_command.Velocity(velocity),
      movement_command.Rotation(rotation),
      movement_command.StateFlags(flags),
    ]),
  )
  // The bot's own 0x0637 follows after its delay: the player sees the bot's unit
  // move with the same commands, its position the player's own.
  let #(replayed, _zed_seat) =
    wait_for_move_of(seat: zed_seat, unit_id: bot_unit)
  assert replayed
    == [
      relayed_movement.Position(UnitPositionCommand(
        x: float32.to_bits(100.5),
        y: float32.to_bits(50.25),
        z: float32.to_bits(-200.75),
        blends: 0,
      )),
      relayed_movement.Velocity(velocity),
      relayed_movement.Rotation(rotation),
      relayed_movement.StateFlags(flags),
    ]
    as "the bot walks as the player did, every command as the client sent it"
  sitting_bot.request_stop(bot)
  let _tally =
    open_wait.received(
      from: finished,
      what: "the bot to end when asked to stop",
    )
  game_client.close(game: zed)
  login_support.stop(started)
}

/// Reads until a 0x638 of the unit and gives its commands.
fn wait_for_move_of(
  seat seat: Seat,
  unit_id unit_id: Int,
) -> #(List(relayed_movement.RelayedMovement), Seat) {
  let #(frame, seat) = wait_for_frame(seat:, message_id: 0x0638)
  let assert Ok(moved) = unit_movement.decode(frame.body) as "0x638 decodes"
  case moved.unit_id == unit_id {
    True -> #(moved.commands, seat)
    False -> wait_for_move_of(seat:, unit_id:)
  }
}

@external(erlang, "sitting_bot_signal_ffi", "send_sigterm")
fn send_sigterm() -> Nil

@external(erlang, "sitting_bot_signal_ffi", "restore_signal_handler")
fn restore_signal_handler() -> Nil

pub fn a_sigterm_to_the_node_ends_the_sitting_bot_which_leaves_and_gives_its_tally_test() -> Nil {
  use <- owned_test.run(120_000)
  // The VM's signal handling is the node's: the bot's handler replaces OTP's
  // while it sits, so no other test may be running.
  use <- unitest.tag("serial")
  let time = driven_time.new()
  let started = login_support.start(time:)
  let #(zed, zed_character) =
    new_player(started:, number: 1, character_name: "Zed Qu")
  send_play(game: zed, character_id: zed_character)
  let #(_burst, zed_have) = game_client.read_entry_kept(game: zed, have: <<>>)
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let assert Ok(seat) = sitting_bot.seat(pool:, near: "Zed Qu")
  let finished = process.new_subject()
  let _bot =
    process.spawn_unlinked(fn() {
      sitting_bot.stop_on_sigterm(process.self())
      process.send(
        finished,
        sitting_bot.sit(
          ports: login_support.ports(started),
          seat:,
          near: "Zed Qu",
          schedule: sitting_bot.client_schedule(walk: sitting_bot.client_circle),
          // Past the test's deadline: only the stop can end the bot inside it.
          for_ms: 300_000,
          report: fn(_event) { Nil },
        ),
      )
    })
  // The bot is in the map once the player is shown its unit; then the node
  // receives SIGTERM.
  let zed_seat = Seat(game: zed, have: zed_have, zone_channel: 0)
  let #(appeared, zed_seat) = wait_for_frame(seat: zed_seat, message_id: 0x0262)
  send_sigterm()
  let _tally =
    open_wait.received(
      from: finished,
      what: "the bot to end on SIGTERM and give its tally",
    )
  let #(gone, _zed_seat) = wait_for_frame(seat: zed_seat, message_id: 0x0355)
  let assert Ok(destroyed) = unit_destroyed.decode(gone.body)
  assert destroyed.unit_id == unit_of(appeared)
    as "the bot closed its connection, so the player sees its unit go"
  restore_signal_handler()
  game_client.close(game: zed)
  login_support.stop(started)
}
