//// Chat on the whole server: say, yell, emote, whisper and zone lines reach the right
//// players, a target that camped or a connection that ends, and the bot numbering its chat
//// message ids.
//// Every wait is for bytes the server writes, with a deadline a passing test never
//// reaches. The tree, the logins and the players come from `game_wire_support`.

import ask_support
import driven_time
import event_wait
import game_client
import game_wire_support.{type Seat, Seat, new_player, send_play, wait_for_frame}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/connection/registry
import genesis_prime/message/bit_stream
import genesis_prime/message/character_list
import genesis_prime/message/chat_line_accepted
import genesis_prime/message/terrain_loaded.{TerrainLoaded}
import genesis_prime/message/whisper_failed
import gleam/erlang/process
import gleam/list
import log_capture
import login_support
import mailbox_support
import owned_test
import unitest

/// Four players of four accounts enter one map, each reports the zone the
/// client's own terrain gives (0xF2 once, as the client does while the world
/// loads): the first three stand in zone 6009, the fourth in zone 648. The
/// zones are the planted WorldZone rows, whose top zones are 4961 and 35. Every
/// seat has read the other three players' units, so no player's entry is still
/// on its way to another seat. The server runs on the driven clock `time`.
fn four_players(
  time time: driven_time.Time,
) -> #(login_support.Started, List(Seat)) {
  let started = login_support.start(time:)
  let seats =
    list.map(
      [#(1, "Zed Qu"), #(2, "Ann Qu"), #(3, "Bob Qu"), #(4, "Cat Qu")],
      fn(player) {
        let #(number, character_name) = player
        let #(game, character) = new_player(started:, number:, character_name:)
        send_play(game:, character_id: character)
        let #(burst, have) = game_client.read_entry_kept(game:, have: <<>>)
        let zone_channel = game_client.zone_channel_in(frames: burst)
        assert zone_channel == 1
          as "chat.zone_channel_id: the burst gives Zone the fixed id 1 in every seat"
        Seat(game:, have:, zone_channel:)
      },
    )
  #(started, list.map(seats, told_of_the_others))
}

/// Reads until the seat has been told of the three other players' units (0x262).
/// Each of their connections writes its own unit to this one after its own
/// burst, so no ping to this connection settles them: a pong comes after only
/// what this connection took before the ping.
fn told_of_the_others(seat: Seat) -> Seat {
  let seat = wait_for_frame(seat:, message_id: 0x0262).1
  let seat = wait_for_frame(seat:, message_id: 0x0262).1
  wait_for_frame(seat:, message_id: 0x0262).1
}

/// Sends the zone the client's terrain gives (0xF2) and settles the seat: every
/// message the server wrote so far is read, so the next read starts after it.
fn reported(seat seat: Seat, zone zone: Int, number number: Int) -> Seat {
  let assert Ok(body) =
    terrain_loaded.encode(TerrainLoaded(world_zone_id: zone))
  game_client.send_world(game: seat.game, message_id: 0x00F2, body:)
  written_to(seat:, number:).1
}

/// The frames the server wrote to the seat up to its answer to a ping.
fn written_to(seat seat: Seat, number number: Int) -> #(List(Frame), Seat) {
  let #(frames, have) =
    game_client.read_until_pong(game: seat.game, have: seat.have, number:)
  #(frames, Seat(..seat, have:))
}

fn seat_at(seats: List(Seat), index: Int) -> Seat {
  let assert Ok(seat) = list.first(list.drop(seats, index))
    as "the seat is at the table"
  seat
}

fn chat_lines(frames: List(Frame)) -> List(game_client.HeardLine) {
  list.filter_map(frames, fn(frame) { game_client.heard_line(frame:) })
}

pub fn say_yell_emote_whisper_and_zone_reach_the_right_players_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let #(started, seats) = four_players(time:)
  let speaker = seat_at(seats, 0)
  let neighbour = seat_at(seats, 1)
  let far = seat_at(seats, 2)
  let other_zone = seat_at(seats, 3)
  // Each client reports its zone, the third walks out of sight, which the
  // speaker learns by the unit's removal.
  let speaker = reported(seat: speaker, zone: 6009, number: 1)
  let neighbour = reported(seat: neighbour, zone: 6009, number: 1)
  let far = reported(seat: far, zone: 6009, number: 1)
  let other_zone = reported(seat: other_zone, zone: 648, number: 1)
  let away =
    game_client.moves_body(client_clock: 0, commands: [
      game_client.position_command(x: 5000.0, y: 0.0, z: 0.0),
    ])
  game_client.send_world(game: far.game, message_id: 0x0637, body: away)
  let #(_, speaker) = wait_for_frame(seat: speaker, message_id: 0x0355)
  let speaker = written_to(seat: speaker, number: 2).1
  let neighbour = written_to(seat: neighbour, number: 2).1
  let far = written_to(seat: far, number: 2).1
  let other_zone = written_to(seat: other_zone, number: 2).1

  // Say, yell and emote reach the player in sight and no one else.
  let speaker =
    list.fold(
      [#(4, "says"), #(5, "yells"), #(8, "emotes")],
      speaker,
      fn(speaker, line) {
        let #(channel_type, text) = line
        game_client.send_line(
          game: speaker.game,
          channel_type:,
          channel_id: 0,
          text:,
          chat_message_id: channel_type,
        )
        let #(accept, have) =
          game_client.read_accepted(
            game: speaker.game,
            have: speaker.have,
            chat_message_id: channel_type,
          )
        assert accept.name == "Zed Qu"
          as "the speaker sees its own line by the accept"
        Seat(..speaker, have:)
      },
    )
  let speaker = written_to(seat: speaker, number: 3).1
  let #(heard, neighbour) = written_to(seat: neighbour, number: 3)
  assert chat_lines(heard)
    == [
      game_client.HeardLine(
        channel_type: 4,
        channel_id: 0,
        sender: "Zed Qu",
        text: "says",
      ),
      game_client.HeardLine(
        channel_type: 5,
        channel_id: 0,
        sender: "Zed Qu",
        text: "yells",
      ),
      game_client.HeardLine(
        channel_type: 8,
        channel_id: 0,
        sender: "Zed Qu",
        text: "emotes",
      ),
    ]
    as "the player in sight reads the say, the yell and the emote, each on its own channel (the server's choice)"
  let #(far_heard, far) = written_to(seat: far, number: 3)
  assert chat_lines(far_heard) == []
    as "a player out of sight, under the same top zone, hears no say"
  let #(other_heard, other_zone) = written_to(seat: other_zone, number: 3)
  assert chat_lines(other_heard) == chat_lines(heard)
    as "a player in sight hears the say, the yell and the emote whatever top zone it stands under: say reaches the players who see the speaker"

  // A whisper reaches the character named, wherever it stands.
  game_client.whisper(
    game: speaker.game,
    target: "bOb qU",
    text: "psst",
    chat_message_id: 6,
  )
  let #(accept, speaker_have) =
    game_client.read_accepted(
      game: speaker.game,
      have: speaker.have,
      chat_message_id: 6,
    )
  let speaker = Seat(..speaker, have: speaker_have)
  assert accept.name == "Bob Qu"
    as "the speaker sees 'To Bob Qu', the target's own name, though it typed another case"
  let #(far_heard, far) = written_to(seat: far, number: 4)
  assert chat_lines(far_heard)
    == [
      game_client.HeardLine(
        channel_type: 6,
        channel_id: 0,
        sender: "Zed Qu",
        text: "psst",
      ),
    ]
    as "the target reads one whisper on (6, 0), though it is out of sight"
  game_client.whisper(
    game: speaker.game,
    target: "No One",
    text: "hello?",
    chat_message_id: 7,
  )
  let #(failed, speaker) = wait_for_frame(seat: speaker, message_id: 0x01D9)
  let assert Ok(failure) = whisper_failed.decode(failed.body)
  assert failure.target_name == bit_stream.utf16_units("No One")
    && failure.chat_message_id == 7

  // A zone line reaches every player under the speaker's top zone in its run,
  // in sight or not, and no one under another top zone.
  game_client.send_line(
    game: speaker.game,
    channel_type: 9,
    channel_id: speaker.zone_channel,
    text: "zone",
    chat_message_id: 8,
  )
  let #(_, speaker_have) =
    game_client.read_accepted(
      game: speaker.game,
      have: speaker.have,
      chat_message_id: 8,
    )
  let speaker = Seat(..speaker, have: speaker_have)
  let speaker = written_to(seat: speaker, number: 5).1
  let #(neighbour_heard, _) = written_to(seat: neighbour, number: 5)
  let #(far_heard, _) = written_to(seat: far, number: 5)
  let zone_line = fn(frames) {
    list.filter(chat_lines(frames), fn(line) { line.channel_type == 9 })
  }
  let expected = [
    game_client.HeardLine(
      channel_type: 9,
      channel_id: speaker.zone_channel,
      sender: "Zed Qu",
      text: "zone",
    ),
  ]
  assert zone_line(neighbour_heard) == expected
    as "the player in sight under the same top zone hears the zone line (the server's choice)"
  assert zone_line(far_heard) == expected
    as "and so does the one out of sight: zone reach is the top zone, not sight"
  let #(other_heard, _) = written_to(seat: other_zone, number: 5)
  assert zone_line(other_heard) == []
    as "a player under another top zone, though in sight, hears no zone line"
  list.each(seats, fn(seat) { game_client.close(game: seat.game) })
  login_support.stop(started)
}

pub fn two_players_whispering_each_other_at_once_both_get_their_answer_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let #(started, seats) = four_players(time:)
  let first = written_to(seat: seat_at(seats, 0), number: 1).1
  let second = written_to(seat: seat_at(seats, 1), number: 1).1
  game_client.whisper(
    game: first.game,
    target: "Ann Qu",
    text: "one",
    chat_message_id: 1,
  )
  game_client.whisper(
    game: second.game,
    target: "Zed Qu",
    text: "two",
    chat_message_id: 1,
  )
  let #(first_frames, _) =
    frames_with(seat: first, message_ids: [0x01C2, 0x01C8])
  let #(second_frames, _) =
    frames_with(seat: second, message_ids: [0x01C2, 0x01C8])
  let accepted_name = fn(frames: List(Frame)) {
    let assert [frame] =
      list.filter(frames, fn(frame) { frame.message_id == 0x01C2 })
    let assert Ok(accept) = chat_line_accepted.decode(frame.body)
    accept.name
  }
  assert accepted_name(first_frames) == "Ann Qu"
    && accepted_name(second_frames) == "Zed Qu"
    as "the design: every send is a tell and none asks, so two whispers at once never wait on each other"
  assert list.map(chat_lines(first_frames), fn(line) { line.text }) == ["two"]
  assert list.map(chat_lines(second_frames), fn(line) { line.text }) == ["one"]
  list.each(seats, fn(seat) { game_client.close(game: seat.game) })
  login_support.stop(started)
}

pub fn a_target_that_camped_is_not_found_and_is_found_again_after_it_enters_again_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let #(started, seats) = four_players(time:)
  let speaker = written_to(seat: seat_at(seats, 0), number: 1).1
  let target = written_to(seat: seat_at(seats, 1), number: 1).1
  game_client.send_world(game: target.game, message_id: 0x00BF, body: <<1>>)
  let target = wait_for_frame(seat: target, message_id: 0x0092).1
  game_client.send_world(game: target.game, message_id: 0x00C0, body: <<>>)
  let #(frame, have) = game_client.next(game: target.game, have: target.have)
  assert frame.message_id == 0x0594
    as "the camp returns the client to character select"
  let target = Seat(..target, have:)
  game_client.whisper(
    game: speaker.game,
    target: "Ann Qu",
    text: "hi",
    chat_message_id: 1,
  )
  let #(failed, speaker) = wait_for_frame(seat: speaker, message_id: 0x01D9)
  assert failed.message_id == 0x01D9
    as "the design's failure table: after the camp's leave the name group is left, so the whisper gets 0x1d9"
  game_client.send(game: target.game, message_id: 0x07E0, body: <<>>)
  let #(listed, target) = wait_for_frame(seat: target, message_id: 0x0117)
  let assert Ok(listing) = character_list.decode(listed.body)
  let assert [entry] = listing.characters
  send_play(game: target.game, character_id: entry.character_id)
  let #(_, have) =
    game_client.read_entry_kept(game: target.game, have: target.have)
  let target = Seat(..target, have:)
  let target = written_to(seat: target, number: 3).1
  game_client.whisper(
    game: speaker.game,
    target: "Ann Qu",
    text: "again",
    chat_message_id: 2,
  )
  let #(accept, _) =
    game_client.read_accepted(
      game: speaker.game,
      have: speaker.have,
      chat_message_id: 2,
    )
  assert accept.name == "Ann Qu" as "a new entry joins the name group again"
  // The speaker's accept is written before the line is told to the target, so
  // the target's line is waited for, not a pong after the accept.
  let #(line, have) =
    game_client.read_chat(game: target.game, have: target.have)
  assert line.text == "again"
  // One sender writes to this seat, so a second "again" would arrive before the
  // next line: the line after it is the next one sent.
  game_client.whisper(
    game: speaker.game,
    target: "Ann Qu",
    text: "once",
    chat_message_id: 3,
  )
  let #(next_line, _) = game_client.read_chat(game: target.game, have:)
  assert next_line.text == "once" as "the first whisper was told to it once"
  list.each(seats, fn(seat) { game_client.close(game: seat.game) })
  login_support.stop(started)
}

pub fn a_speaker_that_ends_before_the_reply_leaves_the_target_with_its_line_and_no_error_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.tag("serial")
  let time = driven_time.new()
  let #(started, seats) = four_players(time:)
  let speaker = written_to(seat: seat_at(seats, 0), number: 1).1
  let target = written_to(seat: seat_at(seats, 1), number: 1).1
  let lines = process.new_subject()
  // Only the two connections of this test are read: another test's connection
  // or listener logging at the same time is no line of this one.
  let assert Ok(speaker_pid) =
    registry.find_named(started.settings.registry, "zed qu")
  let assert Ok(target_pid) =
    registry.find_named(started.settings.registry, "ann qu")
  let speaker_capture =
    log_capture.start_with_metadata(from: speaker_pid, into: lines)
  let capture = log_capture.start_with_metadata(from: target_pid, into: lines)
  game_client.whisper(
    game: speaker.game,
    target: "Ann Qu",
    text: "bye",
    chat_message_id: 1,
  )
  game_client.close(game: speaker.game)
  let #(heard, rest) =
    game_client.read_chat(game: target.game, have: target.have)
  assert heard.text == "bye" as "the target's line stands"
  let #(more, _) = written_to(seat: Seat(..target, have: rest), number: 2)
  assert chat_lines(more) == [] as "the target was written the line once"
  log_capture.stop(capture)
  log_capture.stop(speaker_capture)
  assert list.filter(mailbox_support.drain(lines), fn(line) {
      line.0 == "error"
    })
    == []
    as "the design's failure table: the reply to a dead process is dropped, nothing logged as an error"
  list.each(seats, fn(seat) { game_client.close(game: seat.game) })
  login_support.stop(started)
}

pub fn a_member_whose_connection_crashes_leaves_its_groups_and_later_lines_reach_the_others_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let #(started, seats) = four_players(time:)
  let speaker = reported(seat: seat_at(seats, 0), zone: 6009, number: 1)
  let doomed = reported(seat: seat_at(seats, 1), zone: 6009, number: 1)
  assert doomed.zone_channel == speaker.zone_channel
    as "the member that will crash shares the speaker's zone channel"
  let survivor = reported(seat: seat_at(seats, 2), zone: 6009, number: 1)
  let speaker = written_to(seat: speaker, number: 2).1
  let survivor = written_to(seat: survivor, number: 2).1
  let assert Ok(pid) = registry.find_named(started.settings.registry, "ann qu")
    as "the member is in its name group"
  let gone = process.monitor(pid)
  process.kill(pid)
  let _reason =
    ask_support.ended(watched: gone, what: "the killed member to end")
  event_wait.until("the scope noticed the crash by itself", fn() {
    registry.find_named(started.settings.registry, "ann qu") == Error(Nil)
  })
  game_client.send_line(
    game: speaker.game,
    channel_type: 9,
    channel_id: speaker.zone_channel,
    text: "still here",
    chat_message_id: 1,
  )
  let #(_, _) =
    game_client.read_accepted(
      game: speaker.game,
      have: speaker.have,
      chat_message_id: 1,
    )
  // The speaker's accept is written before the line is told to the group, so
  // the survivor's line is waited for, not a pong after the accept.
  let #(heard, _) = wait_for_frame(seat: survivor, message_id: 0x01C8)
  let assert Ok(line) = game_client.heard_line(frame: heard)
  assert line.text == "still here"
    as "the design's failure table: a later line goes to the others, and the dead member is no longer in the group"
  list.each(seats, fn(seat) { game_client.close(game: seat.game) })
  login_support.stop(started)
}

/// Reads until the server has written a message of each id, and gives every
/// message read.
fn frames_with(
  seat seat: Seat,
  message_ids message_ids: List(Int),
) -> #(List(Frame), Seat) {
  collect_frames(seat:, wanted: message_ids, found: [])
}

fn collect_frames(
  seat seat: Seat,
  wanted wanted: List(Int),
  found found: List(Frame),
) -> #(List(Frame), Seat) {
  case wanted {
    [] -> #(list.reverse(found), seat)
    [_, ..] -> {
      let #(frame, have) = game_client.next(game: seat.game, have: seat.have)
      collect_frames(
        seat: Seat(..seat, have:),
        wanted: list.filter(wanted, fn(id) { id != frame.message_id }),
        found: [frame, ..found],
      )
    }
  }
}

pub fn the_bot_numbers_its_chat_message_ids_from_1_and_each_is_answered_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let #(started, seats) = four_players(time:)
  let speaker = written_to(seat: seat_at(seats, 0), number: 1).1
  let chatter = game_client.chatter(game: speaker.game)
  let #(chatter, first) = game_client.say_next(chatter:, text: "one")
  let #(chatter, second) = game_client.say_next(chatter:, text: "two")
  let #(_, third) =
    game_client.whisper_next(chatter:, target: "Ann Qu", text: "three")
  assert [first, second, third] == [1, 2, 3]
    as "0x140405cb0: the client's chat message ids start at 1, and each line takes the next"
  let #(_, have) =
    game_client.read_accepted(
      game: speaker.game,
      have: speaker.have,
      chat_message_id: 1,
    )
  let #(_, have) =
    game_client.read_accepted(game: speaker.game, have:, chat_message_id: 2)
  let #(accept, _) =
    game_client.read_accepted(game: speaker.game, have:, chat_message_id: 3)
  assert accept.name == "Ann Qu"
    as "each line is answered under its own id, the whisper with the target's name"
  list.each(seats, fn(seat) { game_client.close(game: seat.game) })
  login_support.stop(started)
}
