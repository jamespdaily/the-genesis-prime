//// The wire replay (dev/genesis_prime/wire_replay): a recorded session replayed
//// against a listener, with the recorded seed and times, comparing the bytes
//// the server writes with the bytes recorded. The sessions here are written by
//// hand and run against test rules, so each byte is known; the committed
//// session runs against the real tree in `wire_session_test`. Expected values
//// come from these places.
//// - The replay's contract in the doc comments of `genesis_prime/wire_replay`
////   and `genesis_prime/connection/script`: each connection is given its
////   recording's script in the order of the accept ordinals, the replay client
////   waits for the shell to have taken each input before the next it causes,
////   compares the stream of bytes the server writes (never how the socket cut
////   them into writes), and every wait is bounded by 5 s of real time.
//// - The test rules' own records (`replay_rule`, `script_rule`, `asking_rule`):
////   the bytes a session written by hand holds are the records those rules
////   write for the commands it sends.
//// - Line numbers count from the header, which is line 0; the offset of a
////   difference counts the bytes the connection has written.
//// The tests that end in a wait bound take 5 s, which is the bound they prove.

import ask_support
import asking_rule
import genesis_prime/connection/frame
import genesis_prime/connection/script
import genesis_prime/step.{type Now, Now}
import genesis_prime/wire_recording.{
  Accepted, Answered, Client, NoAnswerInTime, PeerClosed, Read, Server,
  TimerFired, WatchEnded, Woken,
}
import genesis_prime/wire_replay.{
  AwaitEnd, AwaitTaken, CloseClientSocket, Connect, Difference, Differs,
  EndedEarly, Expect, Message, NeverTaken, Send, Silent, StillOpen,
  TimerNeverStarted, TookOutOfOrder, TookUnrecordedInput, Undecoded,
}
import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/static_supervisor as supervisor
import gleam/string
import owned_test
import recording_support
import replay_rule
import replay_rule_planted
import script_rule
import simplifile
import wire_replay_support as support

/// A time with a monotonic reading of its own and a filetime that goes with it.
fn at(n: Int) -> Now {
  Now(monotonic_ms: n, filetime: n * 10)
}

fn command(letter: Int, n: Int, milliseconds: Int) -> BitArray {
  <<letter, n, milliseconds:16>>
}

fn record(letter: Int, n: Int) -> BitArray {
  <<letter, n:64>>
}

fn one() -> List(support.Planted) {
  [support.Planted(rule: "replay_rule", seed: support.seed(1), ordinal: 1)]
}

fn file() -> String {
  "replay_rule-0.jsonl"
}

/// A client that sends one echo and closes: the server writes the record of
/// the echo.
fn echo_session() -> List(support.Step) {
  [
    support.In(0, at(1), Accepted),
    support.In(0, at(2), Read(command(replay_rule.echo_command, 7, 0))),
    support.Out(0, record(replay_rule.echoed, 7)),
    support.In(0, at(3), PeerClosed),
    support.Closed(0, Client),
  ]
}

fn replayed(
  folder: String,
  connections: List(support.Planted),
  steps: List(support.Step),
) -> Result(Nil, wire_replay.Failure) {
  support.write(folder:, connections:, steps:)
  support.run(folder:, rule: replay_rule.rule())
}

// ---- the bytes the server writes ----

pub fn a_session_whose_bytes_the_server_writes_again_replays_to_its_end_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  assert replayed(folder, one(), echo_session()) == Ok(Nil)
    as "the replay client sent the echo and the server wrote its record"
}

pub fn a_changed_byte_the_server_writes_fails_naming_the_connection_the_line_and_the_first_differing_byte_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let changed = [
    support.In(0, at(1), Accepted),
    support.In(0, at(2), Read(command(replay_rule.echo_command, 7, 0))),
    support.Out(0, record(replay_rule.echoed, 8)),
    support.In(0, at(3), PeerClosed),
    support.Closed(0, Client),
  ]
  assert replayed(folder, one(), changed)
    == Error(Differs(
      connection: file(),
      line: 3,
      difference: Difference(
        offset: 8,
        recorded: Undecoded(record(replay_rule.echoed, 8)),
        written: Undecoded(record(replay_rule.echoed, 7)),
      ),
    ))
    as "the third line holds a record whose last byte is 8 where the server wrote 7: the ninth byte of its stream, with the bytes of both"
}

pub fn a_client_byte_the_servers_reader_refuses_fails_the_replay_with_the_servers_refusal_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  // The rule refuses command 3 with a warning and stops; the recording goes on
  // as if it had answered.
  let refused = [
    support.In(0, at(1), Accepted),
    support.In(0, at(2), Read(command(replay_rule.refuse_command, 3, 0))),
    support.Out(0, record(replay_rule.echoed, 1)),
    support.In(0, at(3), PeerClosed),
    support.Closed(0, Client),
  ]
  let assert Error(EndedEarly(connection:, line:, logged:)) =
    replayed(folder, one(), refused)
    as "the server ended the connection where the recording goes on"
  assert connection == file() && line == 3
  assert list.contains(logged, replay_rule.refusal(3))
    as "the failure carries the line the connection wrote when it refused"
}

pub fn a_recorded_read_in_two_lines_gives_the_same_bytes_as_in_one_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let both = <<
    command(replay_rule.echo_command, 1, 0):bits,
    command(replay_rule.echo_command, 2, 0):bits,
  >>
  let whole = [
    support.In(0, at(1), Accepted),
    support.In(0, at(2), Read(both)),
    support.Out(0, record(replay_rule.echoed, 1)),
    support.Out(0, record(replay_rule.echoed, 2)),
    support.In(0, at(3), PeerClosed),
    support.Closed(0, Client),
  ]
  let split = [
    support.In(0, at(1), Accepted),
    support.In(0, at(2), Read(command(replay_rule.echo_command, 1, 0))),
    support.Out(0, record(replay_rule.echoed, 1)),
    support.In(0, at(3), Read(command(replay_rule.echo_command, 2, 0))),
    support.Out(0, record(replay_rule.echoed, 2)),
    support.In(0, at(4), PeerClosed),
    support.Closed(0, Client),
  ]
  assert replayed(folder <> "/whole", one(), whole) == Ok(Nil)
  assert replayed(folder <> "/split", one(), split) == Ok(Nil)
    as "the rule buffers commands, so one read or two give the same records"
}

pub fn a_read_the_client_sends_in_two_parts_is_reassembled_by_the_shell_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let both = <<
    command(replay_rule.echo_command, 1, 0):bits,
    command(replay_rule.echo_command, 2, 0):bits,
  >>
  support.write(folder:, connections: one(), steps: [
    support.In(0, at(1), Accepted),
    support.In(0, at(2), Read(both)),
    support.Out(0, record(replay_rule.echoed, 1)),
    support.Out(0, record(replay_rule.echoed, 2)),
    support.In(0, at(3), PeerClosed),
    support.Closed(0, Client),
  ])
  let session = support.load(folder)
  // The plan sends each read in one send. Here the read is sent in two, the
  // first a whole command, so a shell that took it as an input would write
  // before the rest came.
  let halves =
    list.flat_map(wire_replay.plan(session), fn(action) {
      case action {
        Send(connection:, line:, bytes: <<first:bytes-size(4), rest:bytes>>) -> [
          Send(connection:, line:, bytes: first),
          Send(connection:, line:, bytes: rest),
        ]
        other -> [other]
      }
    })
  assert support.run_actions(
      folder:,
      rule: replay_rule.rule(),
      actions: fn(_session) { halves },
    )
    == Ok(Nil)
    as "the shell took the two parts as the one recorded read"
}

pub fn the_servers_writes_cut_differently_give_the_same_bytes_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let cut = [
    support.In(0, at(1), Accepted),
    support.In(0, at(2), Read(command(replay_rule.echo_command, 7, 0))),
    support.Out(0, <<replay_rule.echoed, 0, 0, 0>>),
    support.Out(0, <<0, 0, 0, 0, 7>>),
    support.In(0, at(3), PeerClosed),
    support.Closed(0, Client),
  ]
  assert replayed(folder, one(), cut) == Ok(Nil)
    as "what is compared is the stream, so a record the recording holds in two writes is the one the server writes in one"
}

pub fn an_input_taken_out_of_the_recorded_order_fails_the_replay_as_an_ordering_failure_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  // Command W watches a process Sessions that nothing runs, so the shell takes
  // the watch's end as the next input after the read's step. The recording
  // holds it after another read.
  let reordered = [
    support.In(0, at(1), Accepted),
    support.In(0, at(2), Read(command(replay_rule.watch_command, 1, 0))),
    support.In(0, at(3), Read(command(replay_rule.echo_command, 7, 0))),
    support.In(0, at(4), WatchEnded),
    support.Out(0, record(replay_rule.watch_ended, 1)),
    support.Out(0, record(replay_rule.echoed, 7)),
    support.In(0, at(5), PeerClosed),
    support.Closed(0, Client),
  ]
  assert replayed(folder, one(), reordered)
    == Error(TookOutOfOrder(
      connection: file(),
      line: 3,
      expected: script.Read(byte_count: 4),
      taken: script.WatchEnded,
    ))
    as "the recording's next input is the read of line 3, and the shell took a watch's end"
}

pub fn a_shell_that_takes_an_input_the_recording_does_not_hold_fails_naming_the_line_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let unrecorded = [
    support.In(0, at(1), Accepted),
    support.In(0, at(2), Read(command(replay_rule.watch_command, 1, 0))),
    support.Closed(0, Server),
  ]
  let assert Error(TookUnrecordedInput(connection:, ..)) =
    replayed(folder, one(), unrecorded)
    as "the watch's end is an input the recording holds no line for"
  assert connection == file()
}

// ---- timers and the client's close ----

pub fn a_recorded_timer_fires_at_its_line_and_not_before_and_a_recorded_close_is_a_close_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  // Timer 1 has 1 ms to run: a timer that fired on real time would fire before
  // the echo is read, and the shell would take it out of the recorded order.
  let timed = [
    support.In(0, at(1), Accepted),
    support.In(0, at(2), Read(command(replay_rule.timer_command, 1, 1))),
    support.In(0, at(3), Read(command(replay_rule.echo_command, 7, 0))),
    support.Out(0, record(replay_rule.echoed, 7)),
    support.In(0, at(4), TimerFired(timer: 1)),
    support.Out(0, record(replay_rule.timer_fired, 1)),
    support.In(0, at(5), PeerClosed),
    support.Closed(0, Client),
  ]
  assert replayed(folder, one(), timed) == Ok(Nil)
    as "the timer fired when the client reached its line, then the client closed and the shell took the close"
}

pub fn a_timer_the_shell_never_started_fails_naming_it_after_5_s_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let never = [
    support.In(0, at(1), Accepted),
    support.In(0, at(2), TimerFired(timer: 9)),
  ]
  assert replayed(
      folder,
      one(),
      list.append(never, [support.Closed(0, Client)]),
    )
    == Error(TimerNeverStarted(connection: file(), line: 2, timer: 9))
    as "no step of the rule started timer 9"
}

// ---- the waits are bounded ----

pub fn a_shell_that_never_takes_its_next_input_fails_within_5_s_naming_the_input_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let never = [
    support.In(0, at(1), Accepted),
    support.In(0, at(2), Read(command(replay_rule.echo_command, 1, 0))),
    support.Out(0, record(replay_rule.echoed, 1)),
    support.In(0, at(3), Woken),
    support.Closed(0, Client),
  ]
  assert replayed(folder, one(), never)
    == Error(NeverTaken(connection: file(), line: 4, input: Woken, taken: 2))
    as "nothing delivers the message the recording holds, so the shell took 2 inputs and never the third"
}

pub fn a_server_that_writes_nothing_fails_within_5_s_naming_the_message_it_waited_for_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let silent = [
    support.In(0, at(1), Accepted),
    support.In(0, at(2), Read(command(replay_rule.echo_command, 1, 0))),
    support.Out(0, record(replay_rule.echoed, 1)),
    support.Out(0, record(replay_rule.echoed, 9)),
    support.Closed(0, Client),
  ]
  assert replayed(folder, one(), silent)
    == Error(Silent(
      connection: file(),
      line: 4,
      expected: Undecoded(record(replay_rule.echoed, 9)),
    ))
    as "the second record is never written"
}

pub fn a_server_that_does_not_close_where_the_recording_says_it_did_fails_after_5_s_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let open = [
    support.In(0, at(1), Accepted),
    support.Closed(0, Server),
  ]
  assert replayed(folder, one(), open)
    == Error(StillOpen(connection: file(), line: 2))
    as "the rule never stops, and the recording says the server closed"
}

// ---- the script of each connection ----

fn script_rule_session() -> #(List(support.Planted), List(support.Step)) {
  let a = support.seed(0xA1)
  let b = support.seed(0xB2)
  // Connection 0 is accepted second: its ordinal is 2 whatever its file is
  // called.
  #(
    [
      support.Planted(rule: "script_rule", seed: a, ordinal: 2),
      support.Planted(rule: "script_rule", seed: b, ordinal: 1),
    ],
    [
      support.In(1, at(10), Accepted),
      support.Out(1, accepted_record(b, at(10))),
      support.In(0, at(20), Accepted),
      support.Out(0, accepted_record(a, at(20))),
      support.In(1, at(30), Read(<<1>>)),
      support.Out(1, read_record(at(30))),
      support.In(0, at(40), Read(<<2>>)),
      support.Out(0, read_record(at(40))),
      support.In(0, at(50), PeerClosed),
      support.Closed(0, Client),
      support.In(1, at(60), PeerClosed),
      support.Closed(1, Client),
    ],
  )
}

fn accepted_record(seed: BitArray, now: Now) -> BitArray {
  <<script_rule.accepted, seed:bits, now.monotonic_ms:64, now.filetime:64>>
}

fn read_record(now: Now) -> BitArray {
  <<script_rule.read, now.monotonic_ms:64, now.filetime:64>>
}

pub fn a_listener_that_accepts_two_connections_gives_each_its_own_recorded_seed_and_times_by_accept_ordinal_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let #(connections, steps) = script_rule_session()
  support.write(folder:, connections:, steps:)
  assert support.run(folder:, rule: script_rule.rule()) == Ok(Nil)
    as "each connection wrote the seed and the times of its own recording"
}

pub fn a_seed_or_a_time_taken_from_another_recording_shows_in_the_bytes_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let #(connections, steps) = script_rule_session()
  // The second connection's header holds the first one's seed.
  let swapped =
    list.map(connections, fn(planted) {
      case planted.ordinal {
        1 -> support.Planted(..planted, seed: support.seed(0xA1))
        _ -> planted
      }
    })
  support.write(folder: folder <> "/seed", connections: swapped, steps:)
  let assert Error(Differs(connection:, line: 2, difference:)) =
    support.run(folder: folder <> "/seed", rule: script_rule.rule())
    as "the connection of ordinal 1 wrote the seed its header holds"
  assert connection == "script_rule-1.jsonl"
  assert difference.offset == 1
    as "the first byte after the record's letter is the seed's"
  // One input's time differs from the time its write holds.
  let retimed =
    list.map(steps, fn(step) {
      case step {
        support.In(1, _, Accepted) -> support.In(1, at(11), Accepted)
        other -> other
      }
    })
  support.write(folder: folder <> "/time", connections:, steps: retimed)
  let assert Error(Differs(connection:, line: 2, difference:)) =
    support.run(folder: folder <> "/time", rule: script_rule.rule())
    as "the clock gave the time the line holds"
  assert connection == "script_rule-1.jsonl"
  assert difference.offset == 33
    as "the first byte of the monotonic time, after the letter and the seed"
}

pub fn the_scripts_are_handed_out_once_each_in_the_order_of_the_accept_ordinals_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let #(connections, steps) = script_rule_session()
  support.write(folder:, connections:, steps:)
  let session = support.load(folder)
  let replay = support.start_replay(session)
  let assert Ok(first) = replay.scripts() as "the first script"
  let assert Ok(second) = replay.scripts() as "the second script"
  assert first.ordinal == 1 && second.ordinal == 2
    as "the connection of ordinal 1 comes first, whatever its file's name"
  assert first.script.seed == support.seed(0xB2)
    && second.script.seed == support.seed(0xA1)
    as "each with the seed of its own recording"
  assert replay.scripts() == Error(Nil)
    as "no script is handed out again, however often a listener asks"
  let _ = wire_replay.finish(replay)
  Nil
}

pub fn a_replays_clock_gives_the_recorded_time_of_each_kind_of_input_and_counts_those_taken_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  support.write(folder:, connections: one(), steps: [
    support.In(0, at(1), Accepted),
    support.In(0, at(2), Read(<<1, 2, 3, 4, 5, 6, 7, 8>>)),
    support.In(0, at(3), Read(<<9, 9>>)),
    support.In(0, at(4), wire_recording.Answered(outcome: NoAnswerInTime)),
    support.In(0, at(5), PeerClosed),
    support.Closed(0, Client),
  ])
  let replay = support.start_replay(support.load(folder))
  let assert Ok(issued) = replay.scripts() as "the script"
  let assert Ok(progress) = dict.get(replay.progress, file()) as "its progress"
  let clock = issued.script.clock
  assert wire_replay.taken(progress) == 0
  assert clock(script.Accepted) == at(1)
  assert wire_replay.taken(progress) == 1
  assert issued.script.next_read() == Some(8)
    as "the next recorded read holds 8 bytes"
  // The first read of the socket holds part of line 2: it takes line 2's time,
  // and the line counts as taken once its last byte has been.
  assert clock(script.Read(byte_count: 3)) == at(2)
  assert wire_replay.taken(progress) == 1
  assert issued.script.next_read() == Some(8)
  assert clock(script.Read(byte_count: 5)) == at(2)
  assert wire_replay.taken(progress) == 2
  assert issued.script.next_read() == Some(2)
  assert clock(script.Read(byte_count: 2)) == at(3)
  assert issued.script.next_read() == None as "no recorded read is left"
  assert clock(script.Answered) == at(4)
    as "an answer takes the time of the next recorded input of its kind, whatever its outcome"
  assert clock(script.PeerClosed) == at(5)
  assert wire_replay.taken(progress) == 5
  let _ = wire_replay.finish(replay)
  Nil
}

// ---- the plan ----

pub fn the_plan_of_a_session_connects_waits_sends_expects_and_closes_in_sequence_order_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  support.write(folder:, connections: one(), steps: echo_session())
  let read = command(replay_rule.echo_command, 7, 0)
  assert wire_replay.plan(support.load(folder))
    == [
      Connect(file()),
      AwaitTaken(file(), 1, 1, Accepted),
      AwaitTaken(file(), 2, 1, Read(read)),
      Send(file(), 2, read),
      Expect(file(), 3, record(replay_rule.echoed, 7)),
      AwaitTaken(file(), 4, 2, PeerClosed),
      CloseClientSocket(file(), 4),
      AwaitEnd(file(), 5, Client),
    ]
    as "a connect before the accepted line; a read waits for the inputs before it, then sends; a write is expected; the client's close waits, then closes; the end is awaited"
}

pub fn a_connect_comes_before_its_accepted_line_and_connects_stay_in_accept_order_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  // The connection of ordinal 1 (file 1) has its accepted line after the one of
  // ordinal 2 (file 0): both connects come before the first accepted line, the
  // connect of ordinal 1 first.
  support.write(
    folder:,
    connections: [
      support.Planted(rule: "replay_rule", seed: support.seed(1), ordinal: 2),
      support.Planted(rule: "replay_rule", seed: support.seed(2), ordinal: 1),
    ],
    steps: [
      support.In(0, at(1), Accepted),
      support.In(1, at(2), Accepted),
      support.In(0, at(3), PeerClosed),
      support.Closed(0, Client),
      support.In(1, at(4), PeerClosed),
      support.Closed(1, Client),
    ],
  )
  let zero = "replay_rule-0.jsonl"
  let one = "replay_rule-1.jsonl"
  let assert [first, second, third, ..] = wire_replay.plan(support.load(folder))
    as "a plan"
  assert first == Connect(one) && second == Connect(zero)
    as "the connect of ordinal 1 first"
  assert third == AwaitTaken(zero, 1, 1, Accepted)
    as "then the first accepted line in sequence order"
}

// ---- comparing and reading bytes ----

pub fn two_streams_that_differ_say_where_and_what_each_holds_there_test() -> Nil {
  let assert Ok(recorded) = frame.encode(0x0117, <<1, 2, 3>>)
  let assert Ok(written) = frame.encode(0x0117, <<1, 9, 3>>)
  assert wire_replay.compare(recorded, recorded) == Ok(Nil)
  assert wire_replay.compare(recorded, written)
    == Error(Difference(
      offset: 7,
      recorded: Message(message_id: 0x0117, name: "0x0117", text: "010203"),
      written: Message(message_id: 0x0117, name: "0x0117", text: "010903"),
    ))
    as "the frame is 4 bytes of length and 2 of id, so the second body byte is at offset 7; each side's frame is read with the codec: its id and its body in hex"
}

pub fn a_stream_that_ends_before_the_other_has_no_message_where_it_stopped_test() -> Nil {
  let assert Ok(recorded) = frame.encode(0x0117, <<1, 2, 3>>)
  let assert <<cut:bytes-size(8), _:bytes>> = recorded
  assert wire_replay.compare(recorded, cut)
    == Error(Difference(
      offset: 8,
      recorded: Message(message_id: 0x0117, name: "0x0117", text: "010203"),
      written: Undecoded(<<>>),
    ))
    as "the written stream ends at offset 8"
}

pub fn bytes_that_are_no_whole_frame_stay_bytes_test() -> Nil {
  assert wire_replay.decode(<<1, 2, 3>>) == Undecoded(<<1, 2, 3>>)
    as "no whole frame, so no message is read"
}

// ---- refusals ----

fn two_connections_with_a_gap(
  gap_ms: Int,
) -> #(List(support.Planted), List(support.Step)) {
  #(
    [
      support.Planted(rule: "replay_rule", seed: support.seed(1), ordinal: 1),
      support.Planted(rule: "replay_rule", seed: support.seed(2), ordinal: 2),
    ],
    [
      support.In(0, at(1000), Accepted),
      support.In(0, at(2000), Read(command(replay_rule.echo_command, 1, 0))),
      support.Out(0, record(replay_rule.echoed, 1)),
      support.In(1, at(2000 + gap_ms), Accepted),
      support.In(0, at(2001 + gap_ms), PeerClosed),
      support.Closed(0, Client),
      support.In(1, at(2002 + gap_ms), PeerClosed),
      support.Closed(1, Client),
    ],
  )
}

pub fn a_recording_whose_client_build_or_tables_differ_is_refused_with_its_reason_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  support.write(folder:, connections: one(), steps: echo_session())
  let session = support.load(folder)
  assert wire_replay.refuse_stale(session, 16_042, None) == Ok(Nil)
    as "the build and the tables the recording was made on"
  assert wire_replay.refuse_stale(session, 16_043, None)
    == Error(wire_replay.ClientBuildDiffers(
      connection: file(),
      recorded: 16_042,
      current: 16_043,
    ))
  assert wire_replay.refuse_stale(session, 16_042, Some("C3D4"))
    == Error(wire_replay.TablesDiffer(
      connection: file(),
      recorded: None,
      current: Some("C3D4"),
    ))
}

pub fn a_recording_without_its_closing_line_is_reported_as_cut_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  support.write(folder:, connections: one(), steps: [
    support.In(0, at(1), Accepted),
  ])
  assert wire_replay.load(folder)
    == Error(wire_replay.Unreadable(
      connection: file(),
      failure: wire_recording.Cut(lines: 2),
    ))
    as "the header and the accepted line are whole, and no closing line follows"
}

pub fn a_folder_with_no_fixture_is_refused_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  support.write(folder:, connections: one(), steps: echo_session())
  let assert Ok(Nil) = simplifile.delete(folder <> "/fixture.sql")
    as "the fixture was removed"
  assert wire_replay.load(folder)
    == Error(wire_replay.NoFixture(path: folder <> "/fixture.sql"))
}

pub fn a_recording_holding_an_ask_that_timed_out_is_refused_saying_which_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  support.write(folder:, connections: one(), steps: [
    support.In(0, at(1), Accepted),
    support.In(0, at(2), Answered(outcome: NoAnswerInTime)),
    support.Closed(0, Client),
  ])
  assert wire_replay.refuse_unreproducible(support.load(folder), 60_000)
    == Error(wire_replay.AskTimedOut(connection: file(), line: 2))
    as "whether the asked process would have answered in time is a matter of time, which a replay cannot bring about"
}

pub fn a_hand_off_key_that_outlived_its_lifetime_between_two_connections_is_refused_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let #(connections, steps) = two_connections_with_a_gap(61_000)
  support.write(folder: folder <> "/long", connections:, steps:)
  assert wire_replay.refuse_unreproducible(
      support.load(folder <> "/long"),
      60_000,
    )
    == Error(wire_replay.HandOffKeyExpired(
      earlier: "replay_rule-0.jsonl",
      later: "replay_rule-1.jsonl",
      gap_ms: 61_000,
      lifetime_ms: 60_000,
    ))
    as "the second connection came 61 s after the first one's last read, and a key lives 60 s"
  let #(connections, steps) = two_connections_with_a_gap(59_000)
  support.write(folder: folder <> "/short", connections:, steps:)
  assert wire_replay.refuse_unreproducible(
      support.load(folder <> "/short"),
      60_000,
    )
    == Ok(Nil)
    as "59 s is within the lifetime"
}

// ---- the tree under replay ----

pub fn an_ask_nobody_answers_ends_at_its_own_deadline_and_the_replay_fails_where_the_recording_had_an_answer_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let gate = process.new_name("replay_gate")
  // The ask waits 200 ms for a gate that ignores it. The recording holds an
  // answer, the echo of 0 (code 0): the replay's outcome is NoAnswerInTime
  // (code 2), whose record differs at its code byte.
  let ignoring = <<0x49, 1, 200:16>>
  support.write(
    folder:,
    connections: [
      support.Planted(rule: "asking_rule", seed: support.seed(1), ordinal: 1),
    ],
    steps: [
      support.In(0, at(1), Accepted),
      support.In(0, at(2), Read(ignoring)),
      support.Out(0, <<asking_rule.asked, 1, 0, 0, 202:64>>),
      support.In(0, at(3), Answered(outcome: wire_recording.Answer)),
      support.Out(0, <<
        asking_rule.outcome,
        1,
        asking_rule.code_echoed,
        0,
        3:64,
      >>),
      support.In(0, at(4), PeerClosed),
      support.Closed(0, Client),
    ],
  )
  let assert Error(Differs(line: 5, difference:, ..)) =
    support.run_with(
      folder:,
      rule: asking_rule.rule(),
      directory: ask_support.directory(
        gate:,
        store: None,
        sent: ask_support.unreported,
      ),
      with: fn(builder) {
        supervisor.add(
          builder,
          ask_support.gate(name: gate, shutdown_ms: 1000, recorder: None),
        )
      },
    )
    as "the replay fails where the recording had an answer"
  assert difference.offset == 14
    as "the 12 bytes of the ask's record, then the letter and the ask's number: the code is the third byte of the record"
}

pub fn a_service_that_crashes_is_restarted_as_live_and_the_replay_fails_only_if_the_bytes_differ_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let gate = process.new_name("replay_gate")
  // The gate crashes on the ask (code 3, the target ended before it answered).
  support.write(
    folder:,
    connections: [
      support.Planted(rule: "asking_rule", seed: support.seed(1), ordinal: 1),
    ],
    steps: [
      support.In(0, at(1), Accepted),
      support.In(0, at(2), Read(<<0x43, 1, 500:16>>)),
      support.Out(0, <<asking_rule.asked, 1, 0, 0, 502:64>>),
      support.In(0, at(3), Answered(outcome: wire_recording.EndedBeforeAnswer)),
      support.Out(0, <<
        asking_rule.outcome,
        1,
        asking_rule.code_ended_before_answer,
        0,
        3:64,
      >>),
      support.In(0, at(4), PeerClosed),
      support.Closed(0, Client),
    ],
  )
  let before = process.named(gate)
  assert before == Error(Nil)
  assert support.run_with(
      folder:,
      rule: asking_rule.rule(),
      directory: ask_support.directory(
        gate:,
        store: None,
        sent: ask_support.unreported,
      ),
      with: fn(builder) {
        supervisor.add(
          builder,
          ask_support.gate(name: gate, shutdown_ms: 1000, recorder: None),
        )
      },
    )
    == Ok(Nil)
    as "the crash is the same outcome the recording holds, so the bytes are the same"
}

pub fn two_replays_at_once_share_no_state_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  support.write(
    folder: folder <> "/a",
    connections: one(),
    steps: echo_session(),
  )
  let #(connections, steps) = script_rule_session()
  support.write(folder: folder <> "/b", connections:, steps:)
  let results = process.new_subject()
  let _ =
    process.spawn(fn() {
      process.send(results, #(
        "a",
        support.run(folder: folder <> "/a", rule: replay_rule.rule()),
      ))
    })
  let _ =
    process.spawn(fn() {
      process.send(results, #(
        "b",
        support.run(folder: folder <> "/b", rule: script_rule.rule()),
      ))
    })
  let assert Ok(first) = process.receive(results, 20_000) as "a replay ended"
  let assert Ok(second) = process.receive(results, 20_000) as "the other ended"
  assert list.sort([first, second], fn(x, y) { string.compare(x.0, y.0) })
    == [#("a", Ok(Nil)), #("b", Ok(Nil))]
    as "each replay had its own scripts, timers, listener and database"
}

pub fn a_session_replays_against_a_rule_whose_internal_types_changed_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  support.write(folder:, connections: one(), steps: echo_session())
  assert support.run(folder:, rule: replay_rule.rule()) == Ok(Nil)
    as "the rule as it stands"
  assert support.run(folder:, rule: replay_rule_planted.rule()) == Ok(Nil)
    as "the same rule with a new variant in its state type, and its recording as it was written"
}
