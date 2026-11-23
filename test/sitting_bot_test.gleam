//// Where the sitting bot (`genesis_prime/sitting_bot`) is seated in a database,
//// which is the database Jim plays on: a character of another account is
//// refused and left as it is, seating twice makes no second account, and a
//// refusal adds nothing. Its whole path against a server is proven here too: it
//// and a player see each other appear, hear each other's say lines and leave, it
//// replays the moves of the player it follows, and a SIGTERM to the node ends it.
//// Every wait on the server is for bytes it writes, with a deadline a passing test
//// never reaches; the tree, the logins and the players come from
//// `game_wire_support`. Expected values come from these places.
//// - The tool's contract, its module doc: `--near` names the character.
//// - A character with no saved place is world 0 (genesis_prime/add_character).

import character_support
import database_support
import driven_time
import fixture_tables
import game_client
import game_wire_support.{
  type Seat, Seat, new_player, send_play, unit_of, wait_for_frame,
}
import genesis_prime/add_account
import genesis_prime/dev_database
import genesis_prime/game/item_property
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
import genesis_prime/sitting_bot.{Place}
import genesis_prime/store.{AccountId}
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/list
import gleam/option
import login_support
import open_wait
import owned_test
import pog
import unitest

/// A pool on a migrated database of the test's own.
fn pool() -> pog.Connection {
  let shared = database_support.shared()
  let database = database_support.new_database(on: shared)
  let name = process.new_name("pool")
  let assert Ok(_) =
    pog.start(database_support.config(
      for: shared.settings,
      database:,
      pool_name: name,
      pool_size: 2,
    ))
    as "the pool started"
  pog.named_connection(name)
}

/// A character of an account of its own at world 1387, zone 1100, x 1.5, y 2.5,
/// z 3.5 (`character_support.insert`).
fn insert_named(pool: pog.Connection, name: String) -> Nil {
  let #(_game_account_id, query) =
    add_account.new_account(login_name: "named", password: "named")
  let assert Ok(pog.Returned(rows: [account], ..)) = query(pool)
    as "the account was inserted"
  let _id =
    character_support.insert(
      pool:,
      account: AccountId(account.account_id),
      name:,
      class_id: 4,
      path: 2,
    )
  Nil
}

fn count(pool: pog.Connection, table: String) -> Int {
  let assert Ok(returned) =
    pog.query("select count(*)::int from " <> table)
    |> pog.returning(decode.at([0], decode.int))
    |> pog.execute(pool)
    as "the count reads"
  let assert [rows] = returned.rows as "a count is one row"
  rows
}

fn bot_row(pool: pog.Connection) -> #(String, Int, Int, Float, Float, Float) {
  let assert Ok(returned) =
    pog.query(
      "select name, world_id, world_zone_id, position_x::float8, position_y::float8, position_z::float8 from character where name = 'Sitting Bot'",
    )
    |> pog.returning({
      use name <- decode.field(0, decode.string)
      use world <- decode.field(1, decode.int)
      use zone <- decode.field(2, decode.int)
      use x <- decode.field(3, decode.float)
      use y <- decode.field(4, decode.float)
      use z <- decode.field(5, decode.float)
      decode.success(#(name, world, zone, x, y, z))
    })
    |> pog.execute(pool)
    as "the row reads"
  let assert [row] = returned.rows as "one character is named Sitting Bot"
  row
}

pub fn the_bot_is_seated_at_the_named_characters_own_place_test() -> Nil {
  use <- owned_test.run(60_000)
  let pool = pool()
  insert_named(pool, "Zed Qu")
  let assert Ok(seat) = sitting_bot.seat(pool:, near: "zed QU")
    as "the named character is found in any case, as names are unique in any case"
  assert seat.place
    == Place(world_id: 1387, world_zone_id: 1100, x: 1.5, y: 2.5, z: 3.5)
    as "the named character's world, zone and position, which the bot walks from"
  assert bot_row(pool) == #("Sitting Bot", 1387, 1100, 1.5, 2.5, 3.5)
    as "the bot character's row holds the place it was seated at"
}

/// What each of the bot's items holds: its Item2 id and the charges stored for it,
/// an error for none stored.
fn bot_items(pool: pog.Connection) -> List(#(Int, Result(Int, Nil))) {
  let assert Ok(returned) =
    pog.query(
      "select item2_id, charges from character_item join character using (character_id) where character.name = 'Sitting Bot' order by bag_index",
    )
    |> pog.returning({
      use item2_id <- decode.field(0, decode.int)
      use charges <- decode.field(1, decode.optional(decode.int))
      decode.success(#(item2_id, option.to_result(charges, Nil)))
    })
    |> pog.execute(pool)
    as "the items read"
  returned.rows
}

/// The Novice set's items are made with their rows' charges, as character creation makes
/// them (`opcode.0x111.charges`), so no row of the bot's holds a null charge count.
pub fn the_bots_novice_items_are_stored_with_their_rows_charges_test() -> Nil {
  use <- owned_test.run(60_000)
  let pool = pool()
  insert_named(pool, "Zed Qu")
  let assert Ok(_) = sitting_bot.seat(pool:, near: "Zed Qu")
  let tables = fixture_tables.shared()
  let items = bot_items(pool)
  assert list.map(items, fn(item) { item.0 })
    == [81_359, 81_344, 81_381, 81_345, 81_380, 8534, 81_346]
    as "the bot holds the Novice set's seven items"
  list.each(items, fn(item) {
    let assert Ok(charges) =
      item_property.max_charges(tables:, item2_id: item.0)
      as "the Novice set's items are rows of the Item2 table"
    assert item.1 == Ok(charges)
      as "the item is stored with its row's charges, never null"
  })
}

pub fn a_sitting_bot_character_of_another_account_is_refused_and_left_as_it_is_test() -> Nil {
  use <- owned_test.run(60_000)
  let pool = pool()
  insert_named(pool, "Zed Qu")
  // Another account owns the character named "Sitting Bot", in another case.
  let #(_game_account_id, query) =
    add_account.new_account(login_name: "other", password: "other")
  let assert Ok(pog.Returned(rows: [other], ..)) = query(pool)
    as "the other account was inserted"
  let owned =
    character_support.insert(
      pool:,
      account: AccountId(other.account_id),
      name: "sitting BOT",
      class_id: 4,
      path: 2,
    )
  let assert Error(sitting_bot.Database(failure: dev_database.Refused(_))) =
    sitting_bot.seat(pool:, near: "Zed Qu")
    as "the name is taken by a character of another account, so the bot's is not made"
  let place = character_support.place_row(pool:, character_id: owned)
  assert place.position == #(1.5, 2.5, 3.5) && place.world_id == 1387
    as "the other account's character was not moved"
  assert count(pool, "character") == 2 as "no character was made for the bot"
}

pub fn seating_the_bot_again_reuses_its_account_and_character_and_moves_it_to_the_new_place_test() -> Nil {
  use <- owned_test.run(60_000)
  let pool = pool()
  insert_named(pool, "Zed Qu")
  let assert Ok(first) = sitting_bot.seat(pool:, near: "Zed Qu")
  let assert Ok(_) =
    pog.query("update character set position_x = 100.5 where name = 'Zed Qu'")
    |> pog.execute(pool)
  let assert Ok(second) = sitting_bot.seat(pool:, near: "Zed Qu")
  assert second.character_id == first.character_id
    as "the same character, not a second one"
  assert count(pool, "account") == 2
    as "the named character's account and the bot's one"
  assert count(pool, "character") == 2
  assert bot_row(pool).3 == 100.5
    as "the bot is moved to where the named character is now"
}

pub fn seating_the_bot_twice_at_once_leaves_one_account_and_one_character_for_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let pool = pool()
  insert_named(pool, "Zed Qu")
  let seated = process.new_subject()
  list.each([1, 2], fn(_) {
    process.spawn(fn() {
      process.send(seated, sitting_bot.seat(pool:, near: "Zed Qu"))
    })
  })
  let first = open_wait.received(from: seated, what: "the first seat's answer")
  let second =
    open_wait.received(from: seated, what: "the second seat's answer")
  let assert Ok(first) = first
    as "a seat that runs beside another still finds or makes the bot's character"
  let assert Ok(second) = second as "so does the other"
  assert first.character_id == second.character_id
    as "both seats are of the one character"
  assert count(pool, "account") == 2
    as "the named character's account and one account for the bot"
  assert count(pool, "character") == 2
    as "the named character and one character for the bot"
}

pub fn a_bot_account_with_no_character_gets_its_character_and_no_second_account_test() -> Nil {
  use <- owned_test.run(60_000)
  let pool = pool()
  insert_named(pool, "Zed Qu")
  let #(_game_account_id, query) =
    add_account.new_account(login_name: "sitting-bot", password: "sitting-bot")
  let assert Ok(_) = query(pool) as "the bot's account was inserted alone"
  let assert Ok(_) = sitting_bot.seat(pool:, near: "Zed Qu")
  assert count(pool, "account") == 2
    as "the bot's account was used, not made again"
  assert count(pool, "character") == 2 as "the bot's character was made for it"
  assert bot_row(pool).0 == "Sitting Bot"
}

pub fn a_named_character_that_does_not_exist_is_refused_and_nothing_is_added_test() -> Nil {
  use <- owned_test.run(60_000)
  let pool = pool()
  assert sitting_bot.seat(pool:, near: "No One")
    == Error(sitting_bot.NoSuchCharacter(name: "No One"))
  assert count(pool, "account") == 0 && count(pool, "character") == 0
    as "a refused seat leaves no bot account or character"
}

pub fn a_named_character_with_no_saved_place_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let pool = pool()
  insert_named(pool, "Zed Qu")
  let assert Ok(_) =
    pog.query(
      "update character set world_id = 0, world_zone_id = 0, position_x = 0, position_y = 0, position_z = 0 where name = 'Zed Qu'",
    )
    |> pog.execute(pool)
  assert sitting_bot.seat(pool:, near: "Zed Qu")
    == Error(sitting_bot.NoSavedPlace(name: "Zed Qu"))
    as "world 0 is no place, so there is no world to seat the bot in"
}

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
