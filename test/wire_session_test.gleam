//// The session committed on 2026-11-04 (`test/wire_recording/2026-11-04-loadout-session`)
//// replayed through the real server tree on a database of its own, with the
//// recorded seed, times and fixture, and compared byte for byte. Expected
//// values come from these places.
//// - The recordings: a live login of the real client through the STS, auth and
////   game servers, played into the world with a level-3 Veteran character
////   (the playing-live skill's `session.sh`, with no person), recorded by the
////   server as wire recordings of the bytes, times, seeds and answers. The
////   client's own movement messages (0x0637, 0x063A, 0x00D5, 0x063B and
////   0x00F2) are in it, and its close at the end is answered by the save of the
////   player's place. Its verdict, beside it, checked the client's own report of
////   that character against its saved row.
//// - The log lines the rules write when the session is replayed: one warning
////   for each message the game rule took and did not handle (opcode.0x38c: the
////   world messages inside 0x038C are logged under their own id), and one for
////   each STS request the STS rule has no handler for (`/Auth/PageVerifiedIps`).
//// - The rows the store answered: the account `genesis` and two characters,
////   `Tess Renamed` (id 1, level 3) and `Grozim Vroc` (id 13, level 3).
//// - The character list (0x0117) carries the FILETIME of the answer that made
////   it (character_select.list_effects), so a replay with another time for that
////   input writes other bytes.
//// - The game tables: the replay reads the client's, so a test is skipped where
////   `GENESIS_NO_CLIENT=1`.

import client_tables
import genesis_prime/connection/cipher
import genesis_prime/connection/encrypted_frame
import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/login/auth_connection
import genesis_prime/login/sts_connection
import genesis_prime/step.{Now}
import genesis_prime/wire_recording.{
  type Line, Answered, Read, Recording, Took, Wrote,
}
import genesis_prime/wire_recording/recorder
import genesis_prime/wire_replay.{Differs}
import gleam/int
import gleam/list
import gleam/string
import owned_test
import recording_support
import simplifile
import unitest
import wire_replay_support as support

fn lines_of(
  connections: List(wire_replay.Logged),
  name: String,
) -> List(String) {
  list.filter_map(connections, fn(entry) {
    case string.contains(entry.connection, name), entry.level {
      True, "warning" | True, "error" -> Ok(entry.text)
      _, _ -> Error(Nil)
    }
  })
}

/// A copy of the recorded session in `session` in `folder`, with every sequence
/// number doubled so that a test can put a line between two (the order of the
/// lines stays the same), and the path of the recording of `rule` in it.
fn copy_of_the_session(
  session session: String,
  folder folder: String,
  rule rule: String,
) -> String {
  let assert Ok(Nil) = simplifile.copy_directory(session, folder)
    as "the recorded session was copied"
  let assert Ok(names) = simplifile.read_directory(folder) as "the copy reads"
  list.each(
    list.filter(names, string.ends_with(_, recorder.file_suffix)),
    fn(name) {
      let path = folder <> "/" <> name
      let assert Ok(text) = simplifile.read(path) as "a recording reads"
      let assert Ok(Recording(header:, lines:, closing:)) =
        wire_recording.read(text)
        as "a recording is whole"
      let doubled =
        wire_recording.encode_header(header)
        <> string.concat(
          list.map(lines, fn(line) {
            wire_recording.encode_line(case line {
              Took(sequence:, at:, input:) ->
                Took(sequence: sequence * 2, at:, input:)
              Wrote(sequence:, bytes:) -> Wrote(sequence: sequence * 2, bytes:)
            })
          }),
        )
        <> wire_recording.encode_closing(
          wire_recording.Closing(..closing, sequence: closing.sequence * 2),
        )
      let assert Ok(Nil) = simplifile.write(path, doubled)
        as "a recording was written"
      Nil
    },
  )
  let assert Ok(connection) =
    list.find(support.load(folder).connections, fn(connection) {
      connection.recording.header.rule == rule
    })
    as "the session holds a recording of the rule"
  folder <> "/" <> connection.name
}

fn changed(path: String, change: fn(List(Line)) -> List(Line)) -> Nil {
  let assert Ok(text) = simplifile.read(path) as "the recording reads"
  let assert Ok(Recording(header:, lines:, closing:)) =
    wire_recording.read(text)
    as "the recording is whole"
  let rewritten =
    wire_recording.encode_header(header)
    <> string.concat(list.map(change(lines), wire_recording.encode_line))
    <> wire_recording.encode_closing(closing)
  let assert Ok(Nil) = simplifile.write(path, rewritten)
    as "the changed recording was written"
  Nil
}

pub fn the_committed_session_replays_to_its_recorded_bytes_with_the_recorded_seed_and_times_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let session = support.load(support.committed_session)
  assert list.map(session.connections, fn(connection) {
      connection.recording.header.rule
    })
    == [
      sts_connection.rule_name,
      auth_connection.rule_name,
      game_connection.rule_name,
    ]
    as "the three connections of the live session, in the order they were accepted"
  let ordinals =
    list.map(session.connections, fn(connection) {
      connection.recording.header.accept_ordinal
    })
  assert ordinals == [1, 17, 26]
    as "the accept ordinals the live session's recordings hold (their headers): the live server's own numbers are not 1, 2 and 3, since the node counts other things with them, and they grow with the order it accepted the connections in"
  let assert Ok(fixture) = simplifile.read(session.fixture)
    as "the fixture reads"
  assert string.contains(fixture, "'genesis'")
    && string.contains(fixture, "'Tess Renamed'")
    && string.contains(fixture, "'Grozim Vroc'")
    as "the rows the store answered the live session with"
  let #(result, _logged) =
    support.replay_tree(folder: support.committed_session)
  assert result == Ok(Nil)
    as "every connection wrote the bytes the live session did, the character list's FILETIME included"
}

pub fn every_recorded_session_replays_to_its_recorded_bytes_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  list.each(support.recorded_sessions(), fn(folder) {
    let #(result, _logged) = support.replay_tree(folder:)
    assert result == Ok(Nil)
      as { folder <> ": every connection wrote the bytes the live session did" }
  })
}

pub fn another_time_for_the_answer_that_makes_the_character_list_changes_the_bytes_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  use folder <- recording_support.in_folder
  let copy = folder <> "/session"
  let game =
    copy_of_the_session(
      session: support.committed_session,
      folder: copy,
      rule: game_connection.rule_name,
    )
  // Every answer of the game connection is taken 100 ns later than it was.
  changed(game, fn(lines) {
    list.map(lines, fn(line) {
      case line {
        Took(sequence:, at:, input: Answered(..) as input) ->
          Took(sequence:, at: Now(..at, filetime: at.filetime + 1), input:)
        Took(..) | Wrote(..) -> line
      }
    })
  })
  let #(result, _logged) = support.replay_tree(folder: copy)
  let assert Error(Differs(connection:, ..)) = result
    as "the list carries the time of its answer, so the bytes differ"
  assert string.contains(connection, "game.connection")
    as "on the game connection, where the list is written"
}

pub fn the_replay_logs_the_unhandled_messages_the_live_session_logged_and_nothing_else_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let #(result, logged) = support.replay_tree(folder: support.committed_session)
  assert result == Ok(Nil)
  assert lines_of(logged, "sts_connection")
    == ["unhandled STS request /Auth/PageVerifiedIps"]
    as "the STS request the rule has no handler for, once for each time the live session's STS connection holds one: this recording holds one"
  assert lines_of(logged, "auth_connection") == []
    as "the auth connection logged no warning and no error"
  assert lines_of(logged, "game.connection")
    == list.map(
      [
        "0x082D", "0x0635", "0x012B", "0x03EC", "0x03ED", "0x0269", "0x07CC",
        "0x018F", "0x023C", "0x07EA", "0x023D", "0x0570",
      ],
      fn(id) { "unhandled game message " <> id },
    )
    as "each world message the game rule took and did not handle, once, by its id; the movement messages of the player (0x0637, 0x063A, 0x00D5, 0x063B and 0x00F2, which the live client sent) are handled, so none is logged; the order is this recording's"
}

pub fn every_message_a_recorded_session_replays_is_handled_or_logged_as_unhandled_by_its_id_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  list.each(support.recorded_sessions(), fn(folder) {
    let #(result, logged) = support.replay_tree(folder:)
    assert result == Ok(Nil)
    let problems =
      list.filter(logged, fn(entry) {
        { entry.level == "warning" || entry.level == "error" }
        && !string.starts_with(entry.text, "unhandled ")
      })
    assert problems == []
      as {
        folder
        <> ": a connection logged something other than a message nothing handles"
      }
  })
}

pub fn a_client_message_nothing_handles_is_reported_by_its_id_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  use folder <- recording_support.in_folder
  // The client sends one more message after its login: 0x0FFF, which no rule
  // takes, inside the auth wrapper under the base key.
  let assert Ok(unknown) =
    encrypted_frame.wrap(
      encrypted_frame.ClientWrapper,
      Frame(message_id: 0x0FFF, body: <<>>),
      cipher.base(),
    )
    as "the frame wraps"
  list.index_map(support.recorded_sessions(), fn(recorded, index) {
    let copy = folder <> "/session" <> int.to_string(index)
    let auth =
      copy_of_the_session(
        session: recorded,
        folder: copy,
        rule: auth_connection.rule_name,
      )
    changed(auth, fn(lines) {
      let assert Ok(last) = list.last(lines) as "the connection has lines"
      let assert Took(sequence:, at:, ..) = last
        as "the connection's last line is its close"
      list.flatten([
        list.take(lines, list.length(lines) - 1),
        [Took(sequence: sequence - 1, at:, input: Read(unknown))],
        [last],
      ])
    })
    let #(result, logged) = support.replay_tree(folder: copy)
    assert result == Ok(Nil)
      as {
        recorded
        <> ": the message is logged and the connection goes on, as the rule says"
      }
    assert lines_of(logged, "auth_connection")
      == ["unhandled auth message 0x0FFF"]
      as { recorded <> ": reported by its id" }
  })
  Nil
}
