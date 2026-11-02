//// A client that floods the auth listener of the server's real tree, over a
//// real socket, with the listener's wire recorder on: its connection is closed,
//// and the recording replays through the auth rule to the same stop. The auth
//// listener needs no game tables, so these run with no client. Expected values
//// come from these places.
//// - The rate: the auth bucket of the server's own settings
////   (`login_support.servers_auth_rate`), the burst a client may send at once.
//// - The ping and its pong, opcode.0x0 and opcode.0x1
////   (`connection_rule_support.pings`, `connection_rule_support.pong`).
//// - The size limit: no frame is over 131,070 bytes (MessageSizeLimit
////   0x140335ec0, `frame.size_limit`), so a length one over it is a frame the
////   client's own reader refuses.
//// - What the rules log: the rate's refusal is a warning and a protocol
////   break an error (`genesis_prime/client_connection`), and both end the
////   connection with nothing written to the client.

import ask_support
import connection_rule_support as support
import genesis_prime/client_connection
import genesis_prime/connection/frame
import genesis_prime/login/auth_connection
import genesis_prime/wire_replay.{type Failure, type Logged}
import gleam/bit_array
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/string
import log_capture
import login_client
import login_support
import mailbox_support
import owned_test
import recording_support
import wire_replay_support

/// What a flooded connection left behind: the bytes it wrote to the client
/// before it closed, the lines its process logged as level and text, and the
/// replay of its recording.
type Flooded {
  Flooded(
    heard: BitArray,
    lines: List(#(String, String)),
    replayed: #(Result(Nil, Failure), List(Logged)),
  )
}

pub fn a_client_past_the_rate_gets_pongs_for_at_most_its_burst_and_is_closed_with_one_warning_test() -> Nil {
  use <- owned_test.run(60_000)
  let burst = client_connection.burst(login_support.servers_auth_rate())
  let flooded = flood(sending: support.pings(count: burst + 1))
  let pongs = bit_array.byte_size(flooded.heard) / 7
  assert pongs >= burst
    as "the whole burst is answered: tokens only grow between reads, so the bucket never holds less than a full burst's worth of frames"
  assert pongs <= burst as "the bucket holds the burst, and one more is refused"
  assert flooded.heard == pongs_of(count: pongs)
    as "each pong answers its ping in order, and nothing else was written"
  let assert [#(_, text)] = of_level(flooded.lines, "warning")
    as "one warning line"
  assert string.contains(text, "faster")
    as "the line says the client sent faster than the rate allows"
  assert of_level(flooded.lines, "error") == []
}

pub fn the_rate_floods_recording_replays_to_the_same_stop_test() -> Nil {
  use <- owned_test.run(60_000)
  let burst = client_connection.burst(login_support.servers_auth_rate())
  let flooded = flood(sending: support.pings(count: burst + 1))
  assert flooded.replayed.0 == Ok(Nil)
    as "the recording replays: the same pongs, then the server closes where it did"
  let assert [text] = replay_lines(flooded, "warning")
    as "the replay logs the rate's warning once, as the live connection did"
  assert string.contains(text, "faster")
  assert replay_lines(flooded, "error") == []
  Nil
}

pub fn a_frame_header_over_the_size_limit_is_closed_with_an_error_and_nothing_written_test() -> Nil {
  use <- owned_test.run(60_000)
  let flooded = flood(sending: header_over_the_limit())
  assert flooded.heard == <<>>
    as "nothing is written to a client that is no client"
  let assert [_] = of_level(flooded.lines, "error") as "one error line"
  assert of_level(flooded.lines, "warning") == []
}

pub fn the_size_floods_recording_replays_to_the_same_stop_test() -> Nil {
  use <- owned_test.run(60_000)
  let flooded = flood(sending: header_over_the_limit())
  assert flooded.replayed.0 == Ok(Nil)
    as "the recording replays: nothing is written, and the server closes where it did"
  assert list.length(replay_lines(flooded, "error")) == 1
    as "the replay logs the one error the live connection did"
  assert replay_lines(flooded, "warning") == []
  Nil
}

/// A frame header with a length one over the size limit, and message 0 as its
/// id: all the client's own reader needs to refuse it.
fn header_over_the_limit() -> BitArray {
  <<{ frame.size_limit + 1 }:size(32)-little, 0:size(16)-little>>
}

/// The pongs for `count` pings numbered from 0, as one run of bytes.
fn pongs_of(count count: Int) -> BitArray {
  int.range(from: 0, to: count, with: <<>>, run: fn(bytes, number) {
    <<bytes:bits, support.pong(number):bits>>
  })
}

/// Starts the tree with the auth listener on the server's own rate and its
/// wire recorder on, connects a client, reads its hello, sends it `sending` in
/// one write and reads until the server closes. It gives what the client heard,
/// what the connection's process logged and the replay of the connection's
/// recording through the auth rule on the same rate, made once the process has
/// ended.
fn flood(sending bytes: BitArray) -> Flooded {
  use folder <- recording_support.in_folder
  let started =
    login_support.start_recording_auth(
      rate: login_support.servers_auth_rate(),
      recorder: recording_support.wire_recorder(folder),
    )
  let client = login_client.connect(login_support.ports(started).auth_port)
  let assert [_hello] = login_client.read_frames(client:, have: <<>>, count: 1)
    as "the auth server greets the client first"
  let assert [connection] =
    ask_support.connections_of(started.settings.login.auth.listener)
    as "one connection process"
  let ended = process.monitor(connection)
  let lines = process.new_subject()
  let capture = log_capture.start(from: connection, into: lines)
  login_client.send(client:, bytes:)
  let heard = login_client.read_until_closed(client:)
  let _reason = ask_support.ended(ended)
  log_capture.stop(capture)
  let lines = mailbox_support.drain(lines)
  login_support.stop(started)
  wire_replay_support.empty_fixture(folder)
  let rate = login_support.servers_auth_rate()
  let rule =
    auth_connection.rule(
      auth_connection.Settings(..login_support.auth_settings(), rate:),
    )
  Flooded(
    heard:,
    lines:,
    replayed: wire_replay_support.run_logged(folder:, rule:),
  )
}

/// The lines of one level, as `log_capture` names it.
fn of_level(
  lines: List(#(String, String)),
  level: String,
) -> List(#(String, String)) {
  list.filter(lines, fn(line) { line.0 == level })
}

/// The texts of the replay's lines of one level.
fn replay_lines(flooded: Flooded, level: String) -> List(String) {
  list.filter_map(flooded.replayed.1, fn(line) {
    case line.level == level {
      True -> Ok(line.text)
      False -> Error(Nil)
    }
  })
}
