//// The sitting bot's own parts (`genesis_prime/sitting_bot`): what it is run
//// with, the lines and moves it sends and when, what it prints and its summary,
//// and where it is seated in a database. Its whole path against a server is
//// proven in `game_wire_test`. Expected values come from these places.
//// - The tool's contract, its module doc: `--near` names the character, minutes
////   default to 30, a move every 125 ms as the client sends them, a chat line
////   every 10 s in turn Say, Yell, Emote, Zone with the channel's name and a
////   counter in its text, a whisper every 30 s, a line for every 20th move of
////   another unit and for the first, a summary of lines sent, answers got,
////   lines heard and units seen.
//// - The ChatChannel rows 4 (Say), 5 (Yell), 8 (Emote) and 9 (Zone)
////   (`genesis_prime/game/chat_channel`), and `opcode.0x1c8`, `opcode.0x1c2`,
////   `opcode.0x1d3`, `opcode.0x1d9`, `opcode.0x355` for what the messages carry.
//// - A character with no saved place is world 0 (genesis_prime/add_character).

import character_support
import database_support
import game_client.{HeardLine}
import genesis_prime/add_account
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/dev_database
import genesis_prime/game/chat_channel
import genesis_prime/message/bit_stream
import genesis_prime/message/chat_channel_result
import genesis_prime/message/chat_line
import genesis_prime/message/chat_line_accepted
import genesis_prime/message/chat_result
import genesis_prime/message/unit_destroyed
import genesis_prime/message/whisper_failed
import genesis_prime/sitting_bot.{
  type Done, type Place, type Schedule, Chat, Done, Move, Options, Place,
  Schedule, Tally, Whisper,
}
import genesis_prime/store.{AccountId}
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/float
import gleam/list
import owned_test
import pog

// ---- what the bot is run with ----

pub fn the_bot_takes_the_named_character_and_a_default_of_30_minutes_test() -> Nil {
  use <- owned_test.run(5000)
  assert sitting_bot.parse_arguments(["--near", "Zed Qu"])
    == Ok(Options(near: "Zed Qu", minutes: 30, walk: sitting_bot.client_follow))
    as "the tool's contract: minutes default to 30 and the walk follows the named character"
}

pub fn the_bot_walks_a_circle_when_it_is_told_to_and_follows_when_it_is_told_to_test() -> Nil {
  use <- owned_test.run(5000)
  assert sitting_bot.parse_arguments(["--near", "Zed Qu", "--walk", "circle"])
    == Ok(Options(near: "Zed Qu", minutes: 30, walk: sitting_bot.client_circle))
  assert sitting_bot.parse_arguments(["--walk", "follow", "--near", "Zed Qu"])
    == Ok(Options(near: "Zed Qu", minutes: 30, walk: sitting_bot.client_follow))
  assert sitting_bot.parse_arguments(["--near", "Zed Qu", "--walk", "run"])
    == Error(sitting_bot.NotAWalk(text: "run"))
  assert sitting_bot.parse_arguments(["--near", "Zed Qu", "--walk"])
    == Error(sitting_bot.NotAWalk(text: ""))
}

pub fn the_follow_walk_delays_a_replay_by_2_s_and_the_circle_moves_every_125_ms_test() -> Nil {
  use <- owned_test.run(5000)
  assert sitting_bot.client_follow == sitting_bot.Follow(delay_ms: 2000)
    as "the coordinator's choice for the follow walk: about 2 s"
  assert sitting_bot.client_circle == sitting_bot.Circle(move_every_ms: 125)
    as "the client's own movement send interval (opcode.0xf1)"
}

pub fn the_bot_takes_the_number_of_minutes_it_is_given_in_either_order_test() -> Nil {
  use <- owned_test.run(5000)
  assert sitting_bot.parse_arguments(["--minutes", "5", "--near", "Zed Qu"])
    == Ok(Options(near: "Zed Qu", minutes: 5, walk: sitting_bot.client_follow))
}

pub fn a_missing_name_a_bad_minute_count_and_an_unknown_argument_are_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert sitting_bot.parse_arguments([]) == Error(sitting_bot.MissingNear)
  assert sitting_bot.parse_arguments(["--minutes", "5"])
    == Error(sitting_bot.MissingNear)
  assert sitting_bot.parse_arguments(["--near"])
    == Error(sitting_bot.MissingNear)
    as "a --near with no name names no character"
  assert sitting_bot.parse_arguments(["--near", "Zed Qu", "--minutes", "soon"])
    == Error(sitting_bot.NotMinutes(text: "soon"))
  assert sitting_bot.parse_arguments(["--near", "Zed Qu", "--minutes", "0"])
    == Error(sitting_bot.NotMinutes(text: "0"))
    as "a sitting of no minutes ends before it begins"
  assert sitting_bot.parse_arguments(["--near", "Zed Qu", "--loud"])
    == Error(sitting_bot.UnknownArgument(text: "--loud"))
}

// ---- what the bot sends, and when ----

pub fn the_chat_lines_go_say_yell_emote_zone_in_turn_with_the_channels_name_and_a_counter_test() -> Nil {
  use <- owned_test.run(5000)
  let lines = list.map(character_support.numbers(5), sitting_bot.chat_line)
  assert list.map(lines, fn(line) { line.text })
    == ["bot say 1", "bot yell 2", "bot emote 3", "bot zone 4", "bot say 5"]
    as "the line's text names its channel and counts the lines"
  assert list.map(lines, fn(line) { chat_channel.id(line.channel) })
    == [4, 5, 8, 9, 4]
    as "ChatChannel rows 4 Say, 5 Yell, 8 Emote, 9 Zone"
}

/// Every duty due up to `until_ms`, in the order the schedule gives them, each
/// with the time it is due.
fn duties(schedule: Schedule, until_ms: Int) -> List(#(Int, sitting_bot.Duty)) {
  duties_from(
    schedule:,
    done: Done(moves: 0, lines: 0, whispers: 0),
    until_ms:,
    found: [],
  )
}

fn duties_from(
  schedule schedule: Schedule,
  done done: Done,
  until_ms until_ms: Int,
  found found: List(#(Int, sitting_bot.Duty)),
) -> List(#(Int, sitting_bot.Duty)) {
  let #(at_ms, duty) = sitting_bot.next_duty(schedule:, done:)
  case at_ms > until_ms {
    True -> list.reverse(found)
    False ->
      duties_from(
        schedule:,
        done: sitting_bot.after(done:, duty:),
        until_ms:,
        found: [#(at_ms, duty), ..found],
      )
  }
}

/// The times of the duties `wanted` picks.
fn times(
  found: List(#(Int, sitting_bot.Duty)),
  wanted: fn(sitting_bot.Duty) -> Bool,
) -> List(Int) {
  list.filter_map(found, fn(duty) {
    case wanted(duty.1) {
      True -> Ok(duty.0)
      False -> Error(Nil)
    }
  })
}

fn is_chat(duty: sitting_bot.Duty) -> Bool {
  case duty {
    Chat(..) -> True
    Move(..) | Whisper(..) -> False
  }
}

fn is_whisper(duty: sitting_bot.Duty) -> Bool {
  case duty {
    Whisper(..) -> True
    Chat(..) | Move(..) -> False
  }
}

fn is_move(duty: sitting_bot.Duty) -> Bool {
  case duty {
    Move(..) -> True
    Chat(..) | Whisper(..) -> False
  }
}

pub fn the_client_schedule_moves_every_125_ms_says_every_10_s_and_whispers_every_30_s_test() -> Nil {
  use <- owned_test.run(5000)
  let found =
    duties(sitting_bot.client_schedule(walk: sitting_bot.client_circle), 30_000)
  assert times(found, is_chat) == [10_000, 20_000, 30_000]
    as "a chat line every 10 s, the first after 10 s"
  assert times(found, is_whisper) == [30_000] as "a whisper every 30 s"
  let moves = times(found, is_move)
  assert list.take(moves, 4) == [0, 125, 250, 375]
    as "a move every 125 ms, the client's own movement send interval (opcode.0xf1)"
  assert list.length(moves) == 241
    as "from 0 to 30,000 ms every 125 ms is 241 moves"
}

pub fn a_follow_walk_has_no_move_duty_of_its_own_test() -> Nil {
  use <- owned_test.run(5000)
  let found =
    duties(sitting_bot.client_schedule(walk: sitting_bot.client_follow), 30_000)
  assert times(found, is_move) == []
    as "its moves are replays of the named character's, not duties of a clock"
  assert times(found, is_chat) == [10_000, 20_000, 30_000]
  assert times(found, is_whisper) == [30_000]
}

pub fn duties_due_at_one_time_go_chat_then_whisper_then_move_and_each_kind_in_its_own_order_test() -> Nil {
  use <- owned_test.run(5000)
  let schedule =
    Schedule(
      walk: sitting_bot.Circle(move_every_ms: 100),
      chat_every_ms: 100,
      whisper_every_ms: 100,
    )
  let found = duties(schedule, 200)
  assert list.map(found, fn(duty) { duty.0 })
    == [0, 100, 100, 100, 200, 200, 200]
    as "a move at 0, then at 100 and at 200 a chat line, a whisper and a move"
  let assert [
    #(_, Move(number: 0)),
    #(_, Chat(line: first_line)),
    #(_, Whisper(number: 1)),
    #(_, Move(number: 1)),
    #(_, Chat(line: second_line)),
    #(_, Whisper(number: 2)),
    #(_, Move(number: 2)),
  ] = found
    as "the numbers count each kind from the first"
  assert first_line.text == "bot say 1"
  assert second_line.text == "bot yell 2"
}

/// The step numbers 0 up to `count`, exclusive.
fn steps(count: Int) -> List(Int) {
  list.map(character_support.numbers(count), fn(number) { number - 1 })
}

fn start() -> Place {
  Place(world_id: 1387, world_zone_id: 1100, x: 10.0, y: 20.0, z: 30.0)
}

fn distance(ax ax: Float, az az: Float, bx bx: Float, bz bz: Float) -> Float {
  let assert Ok(away) =
    float.square_root(
      { bx -. ax } *. { bx -. ax } +. { bz -. az } *. { bz -. az },
    )
    as "a sum of squares has a root"
  away
}

pub fn the_walk_starts_where_the_bot_stands_and_comes_back_to_it_after_a_turn_test() -> Nil {
  use <- owned_test.run(5000)
  let #(x, y, z) = sitting_bot.circle_position(start: start(), step: 0)
  assert #(x, y, z) == #(10.0, 20.0, 30.0)
    as "the first step is where the bot was seated"
  let #(x, _, z) =
    sitting_bot.circle_position(start: start(), step: sitting_bot.circle_steps)
  assert distance(ax: x, az: z, bx: 10.0, bz: 30.0) <. 0.0001
    as "a whole turn ends where it began"
}

pub fn every_step_of_the_walk_is_a_radius_from_the_centre_at_the_bots_height_test() -> Nil {
  use <- owned_test.run(5000)
  let points =
    list.map(steps(sitting_bot.circle_steps + 1), fn(step) {
      sitting_bot.circle_position(start: start(), step:)
    })
  // The centre is one radius from the start along x, on the ground's plane (x and
  // z; y is up in the client's world).
  let centre_x = 10.0 -. sitting_bot.circle_radius
  assert list.all(points, fn(point) {
    let #(x, y, z) = point
    y == 20.0
    && float.absolute_value(
      distance(ax: x, az: z, bx: centre_x, bz: 30.0)
      -. sitting_bot.circle_radius,
    )
    <. 0.0001
  })
    as "the walk is a circle of the radius, at the height it was seated"
  assert list.all(list.zip(points, list.drop(points, 1)), fn(pair) {
    let #(#(ax, _, az), #(bx, _, bz)) = pair
    distance(ax:, az:, bx:, bz:) <. 1.0
  })
    as "no step is a jump the player would see as a flash"
}

// ---- what the bot reads, prints and sums ----

pub fn the_first_move_of_another_unit_and_every_20th_after_it_are_shown_test() -> Nil {
  use <- owned_test.run(5000)
  let #(held, shown) =
    list.fold(
      character_support.numbers(41),
      #(sitting_bot.nothing_yet(), []),
      fn(state, number) {
        let #(held, shown) = state
        let #(held, is_shown) =
          sitting_bot.note(
            tally: held,
            event: sitting_bot.UnitMoved(
              unit_id: 7,
              server_time: 0,
              commands: [],
            ),
          )
        #(held, case is_shown {
          True -> [number, ..shown]
          False -> shown
        })
      },
    )
  assert list.reverse(shown) == [1, 20, 40]
    as "the first move, then every 20th, so the log is readable"
  assert held.moves_seen == 41 as "every move is counted, shown or not"
}

pub fn the_summary_counts_the_lines_sent_the_answers_got_the_lines_heard_and_the_units_seen_test() -> Nil {
  use <- owned_test.run(5000)
  let heard =
    HeardLine(channel_type: 4, channel_id: 0, sender: "Zed Qu", text: "hi")
  let events = [
    sitting_bot.LineSent(channel: "say", chat_message_id: 1, text: "bot say 1"),
    sitting_bot.LineSent(
      channel: "yell",
      chat_message_id: 2,
      text: "bot yell 2",
    ),
    sitting_bot.LineSent(
      channel: "whisper to Zed Qu",
      chat_message_id: 3,
      text: "bot whisper 1",
    ),
    sitting_bot.LineAccepted(chat_message_id: 1, name: "Sitting Bot"),
    sitting_bot.LineRefused(chat_message_id: 2, channel_type: 5, result: 17),
    sitting_bot.WhisperFailed(chat_message_id: 3, target: "Zed Qu"),
    sitting_bot.LineHeard(line: heard),
    sitting_bot.UnitShown(unit_id: 4, name: "Zed Qu"),
    sitting_bot.UnitRemoved(unit_id: 4),
    sitting_bot.NameLookupNeeded(line: heard),
  ]
  let counted =
    list.fold(events, sitting_bot.nothing_yet(), fn(held, event) {
      sitting_bot.note(tally: held, event:).0
    })
  assert counted
    == Tally(
      lines_sent: 3,
      answers_got: 3,
      lines_heard: 1,
      units_seen: 1,
      moves_seen: 0,
    )
    as "a line sent is one sent; an accept, a refusal and a failed whisper are each an answer; a name lookup is no line heard"
  assert sitting_bot.summary(counted)
    == "sitting bot left: lines sent 3, answers got 3, lines heard 1, units seen 1"
}

fn frame_of(
  message_id: Int,
  body: Result(BitArray, bit_stream.EncodeError),
) -> Frame {
  let assert Ok(body) = body as "the message encodes"
  Frame(message_id:, body:)
}

fn heard_frame(sender: String) -> Frame {
  frame_of(
    chat_line.message_id,
    chat_line.encode(chat_line.ChatLine(
      channel_type: 5,
      channel_id: 0,
      gm: 0,
      from_self: 0,
      auto_response: 0,
      sender_realm_id: 1,
      sender_character_id: 42,
      sender_name: sender,
      sender_realm_name: "",
      presence_state: 0,
      text: bit_stream.utf16_units("look"),
      formats: [],
      cross_faction: 0,
      field_14: 0,
      unit_id: 5,
      premium_tier: 0,
    )),
  )
}

pub fn a_line_heard_is_shown_by_its_channel_sender_and_text_test() -> Nil {
  use <- owned_test.run(5000)
  let heard =
    HeardLine(channel_type: 5, channel_id: 0, sender: "Zed Qu", text: "look")
  assert sitting_bot.events_of(heard_frame("Zed Qu"))
    == [sitting_bot.LineHeard(line: heard)]
    as "opcode.0x1c8: a line that carries its sender's name needs no lookup"
  assert sitting_bot.describe(sitting_bot.LineHeard(line: heard))
    == "heard yell from Zed Qu: look"
  assert sitting_bot.describe(sitting_bot.LineHeard(
      line: HeardLine(..heard, channel_type: 9, channel_id: 77),
    ))
    == "heard zone 77 from Zed Qu: look"
    as "a channel with an id of its own shows it"
}

pub fn a_line_with_no_sender_name_is_also_the_lookup_of_0x597_the_client_would_ask_for_test() -> Nil {
  use <- owned_test.run(5000)
  let heard =
    HeardLine(channel_type: 5, channel_id: 0, sender: "", text: "look")
  assert sitting_bot.events_of(heard_frame(""))
    == [
      sitting_bot.LineHeard(line: heard),
      sitting_bot.NameLookupNeeded(line: heard),
    ]
    as "chat.name_lookup: a line with no sender name is where the client would send 0x597"
}

pub fn a_removal_an_accept_a_refusal_and_a_failed_whisper_are_read_from_their_messages_test() -> Nil {
  use <- owned_test.run(5000)
  assert sitting_bot.events_of(frame_of(
      0x0355,
      unit_destroyed.encode(unit_destroyed.UnitDestroyed(unit_id: 9, field_2: 0)),
    ))
    == [sitting_bot.UnitRemoved(unit_id: 9)]
    as "opcode.0x355: the unit is removed"
  assert sitting_bot.events_of(frame_of(
      0x01C2,
      chat_line_accepted.encode(chat_line_accepted.ChatLineAccepted(
        chat_message_id: 3,
        gm: 0,
        name: "Sitting Bot",
        realm_name: "",
        unit_id: 2,
        premium_tier: 0,
      )),
    ))
    == [sitting_bot.LineAccepted(chat_message_id: 3, name: "Sitting Bot")]
    as "opcode.0x1c2: the accept carries the slot's id and the speaker's name"
  assert sitting_bot.events_of(frame_of(
      0x01D3,
      chat_result.encode(chat_result.ChatResult(
        channel_type: 5,
        channel_id: 0,
        result: chat_channel_result.InvalidMessageText,
        chat_message_id: 4,
      )),
    ))
    == [
      sitting_bot.LineRefused(chat_message_id: 4, channel_type: 5, result: 17),
    ]
    as "opcode.0x1d3: the result 17 is ChatChannelResult invalid_message_text"
  assert sitting_bot.events_of(frame_of(
      0x01D9,
      whisper_failed.encode(whisper_failed.WhisperFailed(
        target_name: bit_stream.utf16_units("No One"),
        account: 0,
        chat_message_id: 5,
      )),
    ))
    == [sitting_bot.WhisperFailed(chat_message_id: 5, target: "No One")]
    as "opcode.0x1d9: the failed whisper names its target and the slot"
  assert sitting_bot.events_of(Frame(message_id: 0x019B, body: <<>>)) == []
    as "any other message shows nothing"
}

// ---- where the bot is seated ----

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
  let assert Ok(first) = process.receive(seated, within: 30_000)
    as "the first seat answered"
  let assert Ok(second) = process.receive(seated, within: 30_000)
    as "the second seat answered"
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
