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
import event_wait
import genesis_prime/connection/frame
import genesis_prime/connection/script
import genesis_prime/seed.{type Seed}
import genesis_prime/service
import genesis_prime/step.{type Now}
import genesis_prime/wire_recording.{
  Accepted, Answered, Client, NoAnswerInTime, PeerClosed, Read, Server,
  TimerFired, WatchEnded, Woken,
}
import genesis_prime/wire_replay.{
  AwaitEnd, AwaitTaken, CloseClientSocket, Connect, Difference, Differs,
  EndedEarly, Expect, Fire, FixtureFailed, Message, NeverTaken, NotConnected,
  Refused, Send, Silent, StillOpen, TableLost, TimerNeverStarted, TookOutOfOrder,
  TookUnrecordedInput, Undecoded, Unexpected,
}
import genesis_prime/wire_replay/table as replay_table
import gleam/dict
import gleam/erlang/process
import gleam/erlang/reference
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/static_supervisor as supervisor
import gleam/result
import gleam/string
import lingering_rule
import owned_test
import recording_support
import replay_rule
import replay_rule_planted
import script_rule
import simplifile
import supervisor_children
import wire_replay_support as support

fn command(
  letter letter: Int,
  n n: Int,
  milliseconds milliseconds: Int,
) -> BitArray {
  <<letter, n, milliseconds:16>>
}

fn record(letter: Int, n: Int) -> BitArray {
  <<letter, n:64>>
}

fn one() -> List(support.Planted) {
  [support.Planted(rule: "replay_rule", seed: support.seed(1), ordinal: 1)]
}

/// A client that sends one echo and closes: the server writes the record of
/// the echo.
fn echo_session() -> List(support.Step) {
  [
    support.In(0, support.now_at(1), Accepted),
    support.In(
      0,
      support.now_at(2),
      Read(command(letter: replay_rule.echo_command, n: 7, milliseconds: 0)),
    ),
    support.Out(0, record(replay_rule.echoed, 7)),
    support.In(0, support.now_at(3), PeerClosed),
    support.Closed(0, Client),
  ]
}

fn replayed(
  folder folder: String,
  connections connections: List(support.Planted),
  steps steps: List(support.Step),
) -> Result(Nil, wire_replay.Failure) {
  support.write(folder:, connections:, steps:)
  support.run(folder:, rule: replay_rule.rule())
}

// ---- the bytes the server writes ----

pub fn a_session_whose_bytes_the_server_writes_again_replays_to_its_end_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  assert replayed(folder:, connections: one(), steps: echo_session()) == Ok(Nil)
    as "the replay client sent the echo and the server wrote its record"
}

pub fn a_changed_byte_the_server_writes_fails_naming_the_connection_the_line_and_the_first_differing_byte_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let changed = [
    support.In(0, support.now_at(1), Accepted),
    support.In(
      0,
      support.now_at(2),
      Read(command(letter: replay_rule.echo_command, n: 7, milliseconds: 0)),
    ),
    support.Out(0, record(replay_rule.echoed, 8)),
    support.In(0, support.now_at(3), PeerClosed),
    support.Closed(0, Client),
  ]
  assert replayed(folder:, connections: one(), steps: changed)
    == Error(Differs(
      connection: support.rule_recording_file(),
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
    support.In(0, support.now_at(1), Accepted),
    support.In(
      0,
      support.now_at(2),
      Read(command(letter: replay_rule.refuse_command, n: 3, milliseconds: 0)),
    ),
    support.Out(0, record(replay_rule.echoed, 1)),
    support.In(0, support.now_at(3), PeerClosed),
    support.Closed(0, Client),
  ]
  let assert Error(EndedEarly(connection:, line:, logged:, ..)) =
    replayed(folder:, connections: one(), steps: refused)
    as "the server ended the connection where the recording goes on"
  assert connection == support.rule_recording_file() && line == 3
  assert list.contains(logged, replay_rule.refusal(3))
    as "the failure carries the line the connection wrote when it refused"
}

pub fn a_recorded_read_in_two_lines_gives_the_same_bytes_as_in_one_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let both = <<
    command(letter: replay_rule.echo_command, n: 1, milliseconds: 0):bits,
    command(letter: replay_rule.echo_command, n: 2, milliseconds: 0):bits,
  >>
  let whole = [
    support.In(0, support.now_at(1), Accepted),
    support.In(0, support.now_at(2), Read(both)),
    support.Out(0, record(replay_rule.echoed, 1)),
    support.Out(0, record(replay_rule.echoed, 2)),
    support.In(0, support.now_at(3), PeerClosed),
    support.Closed(0, Client),
  ]
  let split = [
    support.In(0, support.now_at(1), Accepted),
    support.In(
      0,
      support.now_at(2),
      Read(command(letter: replay_rule.echo_command, n: 1, milliseconds: 0)),
    ),
    support.Out(0, record(replay_rule.echoed, 1)),
    support.In(
      0,
      support.now_at(3),
      Read(command(letter: replay_rule.echo_command, n: 2, milliseconds: 0)),
    ),
    support.Out(0, record(replay_rule.echoed, 2)),
    support.In(0, support.now_at(4), PeerClosed),
    support.Closed(0, Client),
  ]
  assert replayed(folder: folder <> "/whole", connections: one(), steps: whole)
    == Ok(Nil)
  assert replayed(folder: folder <> "/split", connections: one(), steps: split)
    == Ok(Nil)
    as "the rule buffers commands, so one read or two give the same records"
}

pub fn a_read_the_client_sends_in_two_parts_is_reassembled_by_the_shell_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  // One read of two commands: the first watches a process nothing runs, so a
  // shell that took the first command alone would take the watch's end as its
  // next input before the second command, and write its record before the
  // second command's. Taken as the one read the recording holds, the second
  // command's record comes first and the watch's end after the step.
  let watch = command(letter: replay_rule.watch_command, n: 1, milliseconds: 0)
  let echoed_seven =
    command(letter: replay_rule.echo_command, n: 7, milliseconds: 0)
  support.write(folder:, connections: one(), steps: [
    support.In(0, support.now_at(1), Accepted),
    support.In(0, support.now_at(2), Read(<<watch:bits, echoed_seven:bits>>)),
    support.Out(0, record(replay_rule.echoed, 7)),
    support.In(0, support.now_at(3), WatchEnded),
    support.Out(0, record(replay_rule.watch_ended, 1)),
    support.In(0, support.now_at(4), PeerClosed),
    support.Closed(0, Client),
  ])
  // The client sends the read in two sends. Timer 99 is no timer of the rule:
  // the shell's script starts it when the shell asks how many bytes the read
  // holds, which it does when the first part has reached it, and the client's
  // wait for it is what holds the second send back until then.
  let actions = [
    Connect(support.rule_recording_file()),
    AwaitTaken(support.rule_recording_file(), 1, 1, Accepted),
    AwaitTaken(
      support.rule_recording_file(),
      2,
      1,
      Read(<<watch:bits, echoed_seven:bits>>),
    ),
    Send(support.rule_recording_file(), 2, watch),
    Fire(support.rule_recording_file(), 2, 99),
    Send(support.rule_recording_file(), 2, echoed_seven),
    Expect(support.rule_recording_file(), 3, record(replay_rule.echoed, 7)),
    AwaitTaken(support.rule_recording_file(), 4, 3, WatchEnded),
    Expect(support.rule_recording_file(), 5, record(replay_rule.watch_ended, 1)),
    AwaitTaken(support.rule_recording_file(), 6, 3, PeerClosed),
    CloseClientSocket(support.rule_recording_file(), 6),
    AwaitEnd(support.rule_recording_file(), 7, Client),
  ]
  let #(result, _logged) =
    support.run_scripted(
      folder:,
      rule: replay_rule.rule(),
      directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
      with: fn(builder) { builder },
      actions: fn(_session) { actions },
      scripts: fn(replay) {
        let table = process.named_subject(replay.table.name)
        fn() {
          use issued <- result.map(replay.scripts())
          script.Issued(
            ..issued,
            script: script.Script(..issued.script, next_read: fn() {
              replay_table.timer_started(
                table:,
                connection: support.rule_recording_file(),
                timer: 99,
                started: replay_table.Started(
                  subject: process.new_subject(),
                  reference: reference.new(),
                ),
              )
              issued.script.next_read()
            }),
          )
        }
      },
      after_start: fn(_server, _replay) { Nil },
    )
  assert result == Ok(Nil)
    as "the shell held the first part and took the two parts as the one recorded read"
}

pub fn the_servers_writes_cut_differently_give_the_same_bytes_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let cut = [
    support.In(0, support.now_at(1), Accepted),
    support.In(
      0,
      support.now_at(2),
      Read(command(letter: replay_rule.echo_command, n: 7, milliseconds: 0)),
    ),
    support.Out(0, <<replay_rule.echoed, 0, 0, 0>>),
    support.Out(0, <<0, 0, 0, 0, 7>>),
    support.In(0, support.now_at(3), PeerClosed),
    support.Closed(0, Client),
  ]
  assert replayed(folder:, connections: one(), steps: cut) == Ok(Nil)
    as "what is compared is the stream, so a record the recording holds in two writes is the one the server writes in one"
}

pub fn an_input_taken_out_of_the_recorded_order_fails_the_replay_as_an_ordering_failure_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  // Command W watches a process Sessions that nothing runs, so the shell takes
  // the watch's end as the next input after the read's step. The recording
  // holds it after another read.
  let reordered = [
    support.In(0, support.now_at(1), Accepted),
    support.In(
      0,
      support.now_at(2),
      Read(command(letter: replay_rule.watch_command, n: 1, milliseconds: 0)),
    ),
    support.In(
      0,
      support.now_at(3),
      Read(command(letter: replay_rule.echo_command, n: 7, milliseconds: 0)),
    ),
    support.In(0, support.now_at(4), WatchEnded),
    support.Out(0, record(replay_rule.watch_ended, 1)),
    support.Out(0, record(replay_rule.echoed, 7)),
    support.In(0, support.now_at(5), PeerClosed),
    support.Closed(0, Client),
  ]
  assert replayed(folder:, connections: one(), steps: reordered)
    == Error(TookOutOfOrder(
      connection: support.rule_recording_file(),
      line: 3,
      expected: Read(command(
        letter: replay_rule.echo_command,
        n: 7,
        milliseconds: 0,
      )),
      taken: WatchEnded,
    ))
    as "the recording's next input is the read of line 3, and the shell took a watch's end"
}

pub fn a_shell_that_takes_an_input_the_recording_does_not_hold_fails_naming_the_line_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let unrecorded = [
    support.In(0, support.now_at(1), Accepted),
    support.In(
      0,
      support.now_at(2),
      Read(command(letter: replay_rule.watch_command, n: 1, milliseconds: 0)),
    ),
    support.Closed(0, Server),
  ]
  let assert Error(TookUnrecordedInput(connection:, ..)) =
    replayed(folder:, connections: one(), steps: unrecorded)
    as "the watch's end is an input the recording holds no line for"
  assert connection == support.rule_recording_file()
}

// ---- timers and the client's close ----

pub fn a_recorded_timer_fires_at_its_line_and_not_before_and_a_recorded_close_is_a_close_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  // Timer 1 has 1 ms to run: a timer that fired on real time would fire before
  // the echo is read, and the shell would take it out of the recorded order.
  let timed = [
    support.In(0, support.now_at(1), Accepted),
    support.In(
      0,
      support.now_at(2),
      Read(command(letter: replay_rule.timer_command, n: 1, milliseconds: 1)),
    ),
    support.In(
      0,
      support.now_at(3),
      Read(command(letter: replay_rule.echo_command, n: 7, milliseconds: 0)),
    ),
    support.Out(0, record(replay_rule.echoed, 7)),
    support.In(0, support.now_at(4), TimerFired(timer: 1)),
    support.Out(0, record(replay_rule.timer_fired, 1)),
    support.In(0, support.now_at(5), PeerClosed),
    support.Closed(0, Client),
  ]
  assert replayed(folder:, connections: one(), steps: timed) == Ok(Nil)
    as "the timer fired when the client reached its line, then the client closed and the shell took the close"
}

pub fn a_timer_the_shell_never_started_fails_naming_it_after_5_s_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let never = [
    support.In(0, support.now_at(1), Accepted),
    support.In(0, support.now_at(2), TimerFired(timer: 9)),
  ]
  assert replayed(
      folder:,
      connections: one(),
      steps: list.append(never, [support.Closed(0, Client)]),
    )
    == Error(TimerNeverStarted(
      connection: support.rule_recording_file(),
      line: 2,
      timer: 9,
    ))
    as "no step of the rule started timer 9"
}

// ---- the waits are bounded ----

pub fn a_shell_that_never_takes_its_next_input_fails_within_5_s_naming_the_input_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let never = [
    support.In(0, support.now_at(1), Accepted),
    support.In(
      0,
      support.now_at(2),
      Read(command(letter: replay_rule.echo_command, n: 1, milliseconds: 0)),
    ),
    support.Out(0, record(replay_rule.echoed, 1)),
    support.In(0, support.now_at(3), Woken),
    support.Closed(0, Client),
  ]
  assert replayed(folder:, connections: one(), steps: never)
    == Error(NeverTaken(
      connection: support.rule_recording_file(),
      line: 4,
      input: Woken,
      taken: 2,
    ))
    as "nothing delivers the message the recording holds, so the shell took 2 inputs and never the third"
}

pub fn a_server_that_writes_nothing_fails_within_5_s_naming_the_message_it_waited_for_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let silent = [
    support.In(0, support.now_at(1), Accepted),
    support.In(
      0,
      support.now_at(2),
      Read(command(letter: replay_rule.echo_command, n: 1, milliseconds: 0)),
    ),
    support.Out(0, record(replay_rule.echoed, 1)),
    support.Out(0, record(replay_rule.echoed, 9)),
    support.Closed(0, Client),
  ]
  assert replayed(folder:, connections: one(), steps: silent)
    == Error(Silent(
      connection: support.rule_recording_file(),
      line: 4,
      expected: Undecoded(record(replay_rule.echoed, 9)),
    ))
    as "the second record is never written"
}

pub fn a_server_that_does_not_close_where_the_recording_says_it_did_fails_after_5_s_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let open = [
    support.In(0, support.now_at(1), Accepted),
    support.Closed(0, Server),
  ]
  assert replayed(folder:, connections: one(), steps: open)
    == Error(StillOpen(connection: support.rule_recording_file(), line: 2))
    as "the rule never stops, and the recording says the server closed"
}

// ---- the script of each connection ----

fn script_rule_session() -> #(List(support.Planted), List(support.Step)) {
  let first = support.seed(0xA1)
  let second = support.seed(0xB2)
  // Connection 0 is accepted second: its ordinal is 2 whatever its file is
  // called.
  #(
    [
      support.Planted(rule: "script_rule", seed: first, ordinal: 2),
      support.Planted(rule: "script_rule", seed: second, ordinal: 1),
    ],
    [
      support.In(1, support.now_at(10), Accepted),
      support.Out(1, accepted_record(second, support.now_at(10))),
      support.In(0, support.now_at(20), Accepted),
      support.Out(0, accepted_record(first, support.now_at(20))),
      support.In(1, support.now_at(30), Read(<<1>>)),
      support.Out(1, script_rule.read_record(support.now_at(30))),
      support.In(0, support.now_at(40), Read(<<2>>)),
      support.Out(0, script_rule.read_record(support.now_at(40))),
      support.In(0, support.now_at(50), PeerClosed),
      support.Closed(0, Client),
      support.In(1, support.now_at(60), PeerClosed),
      support.Closed(1, Client),
    ],
  )
}

fn accepted_record(seed: Seed, now: Now) -> BitArray {
  <<
    script_rule.accepted,
    seed.bytes(seed):bits,
    now.monotonic_ms:64,
    now.filetime:64,
  >>
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
        support.In(1, _, Accepted) ->
          support.In(1, support.now_at(11), Accepted)
        support.In(..) | support.Out(..) | support.Closed(..) -> step
      }
    })
  support.write(folder: folder <> "/time", connections:, steps: retimed)
  let assert Error(Differs(connection:, line: 2, difference:)) =
    support.run(folder: folder <> "/time", rule: script_rule.rule())
    as "the clock gave the time the line holds"
  assert connection == "script_rule-1.jsonl"
  assert difference.offset == 40
    as "the last byte of the 64-bit monotonic time, where 10 and 11 differ, after the letter and the 32-byte seed"
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
  let _lines = wire_replay.finish(replay)
  Nil
}

pub fn a_replays_clock_gives_the_recorded_time_of_each_kind_of_input_and_counts_those_taken_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  support.write(folder:, connections: one(), steps: [
    support.In(0, support.now_at(1), Accepted),
    support.In(0, support.now_at(2), Read(<<1, 2, 3, 4, 5, 6, 7, 8>>)),
    support.In(0, support.now_at(3), Read(<<9, 9>>)),
    support.In(
      0,
      support.now_at(4),
      wire_recording.Answered(outcome: NoAnswerInTime),
    ),
    support.In(0, support.now_at(5), PeerClosed),
    support.Closed(0, Client),
  ])
  let replay = support.start_replay(support.load(folder))
  let assert Ok(issued) = replay.scripts() as "the script"
  let assert Ok(progress) =
    dict.get(replay.progress, support.rule_recording_file())
    as "its progress"
  let clock = issued.script.clock
  assert wire_replay.taken(progress) == 0
  assert clock(Accepted) == support.now_at(1)
  assert wire_replay.taken(progress) == 1
  assert issued.script.next_read() == Some(8)
    as "the next recorded read holds 8 bytes"
  // The first read of the socket holds part of line 2: it takes line 2's time,
  // and the line counts as taken once its last byte has been.
  assert clock(Read(<<1, 2, 3>>)) == support.now_at(2)
  assert wire_replay.taken(progress) == 1
  assert issued.script.next_read() == Some(8)
  assert clock(Read(<<4, 5, 6, 7, 8>>)) == support.now_at(2)
  assert wire_replay.taken(progress) == 2
  assert issued.script.next_read() == Some(2)
  assert clock(Read(<<9, 9>>)) == support.now_at(3)
  assert issued.script.next_read() == None as "no recorded read is left"
  assert clock(Answered(outcome: wire_recording.Answer)) == support.now_at(4)
    as "an answer takes the time of the next recorded input of its kind, whatever its outcome"
  assert clock(PeerClosed) == support.now_at(5)
  assert wire_replay.taken(progress) == 5
  let _lines = wire_replay.finish(replay)
  Nil
}

// ---- the plan ----

pub fn the_plan_of_a_session_connects_waits_sends_expects_and_closes_in_sequence_order_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  support.write(folder:, connections: one(), steps: echo_session())
  let read = command(letter: replay_rule.echo_command, n: 7, milliseconds: 0)
  assert wire_replay.plan(support.load(folder))
    == [
      Connect(support.rule_recording_file()),
      AwaitTaken(support.rule_recording_file(), 1, 1, Accepted),
      AwaitTaken(support.rule_recording_file(), 2, 1, Read(read)),
      Send(support.rule_recording_file(), 2, read),
      Expect(support.rule_recording_file(), 3, record(replay_rule.echoed, 7)),
      AwaitTaken(support.rule_recording_file(), 4, 2, PeerClosed),
      CloseClientSocket(support.rule_recording_file(), 4),
      AwaitEnd(support.rule_recording_file(), 5, Client),
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
      support.In(0, support.now_at(1), Accepted),
      support.In(1, support.now_at(2), Accepted),
      support.In(0, support.now_at(3), PeerClosed),
      support.Closed(0, Client),
      support.In(1, support.now_at(4), PeerClosed),
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
  use <- owned_test.run(30_000)
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
  use <- owned_test.run(30_000)
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
  use <- owned_test.run(30_000)
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
      support.In(0, support.now_at(1000), Accepted),
      support.In(
        0,
        support.now_at(2000),
        Read(command(letter: replay_rule.echo_command, n: 1, milliseconds: 0)),
      ),
      support.Out(0, record(replay_rule.echoed, 1)),
      support.In(1, support.now_at(2000 + gap_ms), Accepted),
      support.In(0, support.now_at(2001 + gap_ms), PeerClosed),
      support.Closed(0, Client),
      support.In(1, support.now_at(2002 + gap_ms), PeerClosed),
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
    as "the build the recording was made on"
  assert wire_replay.refuse_stale(session, 16_043, None)
    == Error(wire_replay.ClientBuildDiffers(
      connection: support.rule_recording_file(),
      recorded: 16_042,
      current: 16_043,
    ))
  assert wire_replay.refuse_stale(session, 16_042, Some("C3D4")) == Ok(Nil)
    as "a header with no digest is of a rule that reads no table, so the tables do not matter to it"
  let reading_tables =
    wire_replay.Session(
      ..session,
      connections: list.map(session.connections, fn(connection) {
        let recording = connection.recording
        wire_replay.Connection(
          ..connection,
          recording: wire_recording.Recording(
            ..recording,
            header: wire_recording.Header(
              ..recording.header,
              tables_digest: Some("A1B2"),
            ),
          ),
        )
      }),
    )
  assert wire_replay.refuse_stale(reading_tables, 16_042, Some("A1B2"))
    == Ok(Nil)
    as "the tables the recording was made on"
  assert wire_replay.refuse_stale(reading_tables, 16_042, Some("C3D4"))
    == Error(wire_replay.TablesDiffer(
      connection: support.rule_recording_file(),
      recorded: Some("A1B2"),
      current: Some("C3D4"),
    ))
}

pub fn a_recording_without_its_closing_line_is_reported_as_cut_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  support.write(folder:, connections: one(), steps: [
    support.In(0, support.now_at(1), Accepted),
  ])
  assert wire_replay.load(folder)
    == Error(wire_replay.Unreadable(
      connection: support.rule_recording_file(),
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
    support.In(0, support.now_at(1), Accepted),
    support.In(0, support.now_at(2), Answered(outcome: NoAnswerInTime)),
    support.Closed(0, Client),
  ])
  assert wire_replay.refuse_unreproducible(support.load(folder), 60_000)
    == Error(wire_replay.AskTimedOut(
      connection: support.rule_recording_file(),
      line: 2,
    ))
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
      support.In(0, support.now_at(1), Accepted),
      support.In(0, support.now_at(2), Read(ignoring)),
      support.Out(0, <<asking_rule.asked, 1, 0, 0, 202:64>>),
      support.In(0, support.now_at(3), Answered(outcome: wire_recording.Answer)),
      support.Out(0, <<
        asking_rule.outcome,
        1,
        asking_rule.code_echoed,
        0,
        3:64,
      >>),
      support.In(0, support.now_at(4), PeerClosed),
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
        supervisor.add(builder, ask_support.gate(name: gate, shutdown_ms: 1000))
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
  // The gate crashes on the first ask (code 3, the target ended before it
  // answered). Its supervisor starts another, which answers the second ask (code
  // 0, the echo of 5): a gate that was never restarted would give code 1, no
  // process running.
  support.write(
    folder:,
    connections: [
      support.Planted(rule: "asking_rule", seed: support.seed(1), ordinal: 1),
    ],
    steps: [
      support.In(0, support.now_at(1), Accepted),
      support.In(0, support.now_at(2), Read(<<0x43, 1, 500:16>>)),
      support.Out(0, <<asking_rule.asked, 1, 0, 0, 502:64>>),
      support.In(
        0,
        support.now_at(3),
        Answered(outcome: wire_recording.EndedBeforeAnswer),
      ),
      support.Out(0, <<
        asking_rule.outcome,
        1,
        asking_rule.code_ended_before_answer,
        0,
        3:64,
      >>),
      support.In(0, support.now_at(4), Read(<<0x45, 5, 500:16>>)),
      support.Out(0, <<asking_rule.asked, 2, 0, 0, 504:64>>),
      support.In(0, support.now_at(5), Answered(outcome: wire_recording.Answer)),
      support.Out(0, <<
        asking_rule.outcome,
        2,
        asking_rule.code_echoed,
        5,
        5:64,
      >>),
      support.In(0, support.now_at(6), PeerClosed),
      support.Closed(0, Client),
    ],
  )
  let before = process.named(gate)
  assert before == Error(Nil)
  let reached = process.new_subject()
  // The second ask is sent once the test has seen another process hold the gate's
  // name: timer 99 is no timer of the rule, and the client's wait for it holds
  // the second read back.
  let held_back = fn(session) {
    list.flat_map(wire_replay.plan(session), fn(action) {
      case action {
        Send(connection:, line: 6, ..) -> [Fire(connection, 6, 99), action]
        Send(..)
        | Connect(..)
        | AwaitTaken(..)
        | Fire(..)
        | CloseClientSocket(..)
        | Expect(..)
        | AwaitEnd(..) -> [action]
      }
    })
  }
  let #(result, _logged) =
    support.run_scripted(
      folder:,
      rule: asking_rule.rule(),
      directory: ask_support.directory(gate:, store: None, sent: fn(sent) {
        process.send(reached, sent)
      }),
      with: fn(builder) {
        supervisor.add(builder, ask_support.gate(name: gate, shutdown_ms: 1000))
      },
      actions: held_back,
      scripts: fn(replay) { replay.scripts },
      after_start: fn(_server, replay) {
        let assert Ok(crashing) = process.named(gate) as "the gate is running"
        let table = process.named_subject(replay.table.name)
        let _releaser =
          process.spawn(fn() {
            let _restarted =
              ask_support.await_new_pid(
                name: gate,
                not: crashing,
                within_ms: 5000,
              )
            replay_table.timer_started(
              table:,
              connection: "asking_rule-0.jsonl",
              timer: 99,
              started: replay_table.Started(
                subject: process.new_subject(),
                reference: reference.new(),
              ),
            )
          })
        Nil
      },
    )
  assert result == Ok(Nil)
    as "the crash is the outcome the recording holds, and the second ask is answered as it was"
  let assert Ok(service.ToService(first)) = process.receive(reached, 0)
    as "the first ask reached the gate"
  let assert Ok(service.ToService(second)) = process.receive(reached, 0)
    as "the second ask reached a gate"
  assert first != second
    as "a process other than the one that crashed answered the second ask"
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
  let _runner =
    process.spawn(fn() {
      process.send(results, #(
        "a",
        support.run(folder: folder <> "/a", rule: replay_rule.rule()),
      ))
    })
  let _runner =
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

// ---- what the replay client keeps and bounds ----

pub fn a_write_that_arrives_before_the_read_it_follows_is_kept_for_its_own_expect_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let echoes = <<
    command(letter: replay_rule.echo_command, n: 1, milliseconds: 0):bits,
    command(letter: replay_rule.echo_command, n: 2, milliseconds: 0):bits,
  >>
  let first = command(letter: replay_rule.cancel_command, n: 1, milliseconds: 0)
  let second =
    command(letter: replay_rule.cancel_command, n: 2, milliseconds: 0)
  support.write(folder:, connections: one(), steps: [
    support.In(0, support.now_at(1), Accepted),
    support.In(0, support.now_at(2), Read(echoes)),
    support.Out(0, record(replay_rule.echoed, 1)),
    support.Out(0, record(replay_rule.echoed, 2)),
    support.In(0, support.now_at(3), Read(first)),
    support.In(0, support.now_at(4), Read(second)),
    support.In(0, support.now_at(5), PeerClosed),
    support.Closed(0, Client),
  ])
  // The client sends the first cancel after the shell has taken the echoes, and
  // waits for the shell to take it: the step that wrote both records is over, so
  // both are in the client's socket when `Expect` reads, and the second record
  // is kept for the `Expect` after the next send.
  let actions = [
    Connect(support.rule_recording_file()),
    AwaitTaken(support.rule_recording_file(), 1, 1, Accepted),
    AwaitTaken(support.rule_recording_file(), 2, 1, Read(echoes)),
    Send(support.rule_recording_file(), 2, echoes),
    AwaitTaken(support.rule_recording_file(), 5, 2, Read(first)),
    Send(support.rule_recording_file(), 5, first),
    AwaitTaken(support.rule_recording_file(), 6, 3, Read(second)),
    Expect(support.rule_recording_file(), 3, record(replay_rule.echoed, 1)),
    Send(support.rule_recording_file(), 6, second),
    Expect(support.rule_recording_file(), 4, record(replay_rule.echoed, 2)),
    AwaitTaken(support.rule_recording_file(), 7, 4, PeerClosed),
    CloseClientSocket(support.rule_recording_file(), 7),
    AwaitEnd(support.rule_recording_file(), 8, Client),
  ]
  assert support.run_actions(
      folder:,
      rule: replay_rule.rule(),
      actions: fn(_session) { actions },
    ).0
    == Ok(Nil)
    as "a record the server wrote before the client's next send is the next expected write, not an unexpected one"
}

pub fn a_recording_of_a_shutdown_is_refused_before_it_is_played_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  support.write(folder: folder <> "/stopping", connections: one(), steps: [
    support.In(0, support.now_at(1), Accepted),
    support.In(0, support.now_at(2), wire_recording.Stopping),
    support.Closed(0, Server),
  ])
  assert result.is_error(wire_replay.refuse_unreproducible(
    support.load(folder <> "/stopping"),
    60_000,
  ))
    as "a replay cannot make the tree send the exit that is a connection's Stopping"
  support.write(folder: folder <> "/ask", connections: one(), steps: [
    support.In(0, support.now_at(1), Accepted),
    support.In(
      0,
      support.now_at(2),
      Answered(outcome: wire_recording.StoppedWaiting),
    ),
    support.Closed(0, Server),
  ])
  assert result.is_error(wire_replay.refuse_unreproducible(
    support.load(folder <> "/ask"),
    60_000,
  ))
    as "nor stop the tree while an ask waits"
}

pub fn a_shell_that_takes_the_clients_close_and_stays_open_fails_the_replay_after_5_s_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  support.write(
    folder:,
    connections: [
      support.Planted(rule: "lingering_rule", seed: support.seed(1), ordinal: 1),
    ],
    steps: [
      support.In(0, support.now_at(1), Accepted),
      support.In(0, support.now_at(2), PeerClosed),
      support.Closed(0, Client),
    ],
  )
  // The rule asks when the client closes, and the process asked never answers:
  // the shell has taken the close, and does not end.
  let silent = process.spawn_unlinked(process.sleep_forever)
  assert support.run_with(
      folder:,
      rule: lingering_rule.rule(),
      directory: fn(_request, _deadline_ms, _reply) {
        Ok(service.ToService(silent))
      },
      with: fn(builder) { builder },
    )
    != Ok(Nil)
    as "the recording says the connection ended, and its shell never did"
}

pub fn a_listener_killed_under_replay_ends_its_connections_and_the_replay_fails_naming_the_connection_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  support.write(folder:, connections: one(), steps: echo_session())
  let replays = process.new_subject()
  // The client waits for timer 99, which is no timer of the rule, before it
  // sends the echo: the killer starts it once the listener is gone.
  let held_back = fn(session) {
    list.flat_map(wire_replay.plan(session), fn(action) {
      case action {
        Send(connection:, line: 2, ..) -> [Fire(connection, 2, 99), action]
        Send(..)
        | Connect(..)
        | AwaitTaken(..)
        | Fire(..)
        | CloseClientSocket(..)
        | Expect(..)
        | AwaitEnd(..) -> [action]
      }
    })
  }
  let #(result, _logged) =
    support.run_scripted(
      folder:,
      rule: replay_rule.rule(),
      directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
      with: fn(builder) { builder },
      actions: held_back,
      scripts: fn(replay) { replay.scripts },
      after_start: fn(server, replay) {
        process.send(replays, replay)
        let assert [listener] =
          supervisor_children.in_start_order(server.supervisor)
          as "the tree holds the listener"
        let assert Ok(progress) =
          dict.get(replay.progress, support.rule_recording_file())
          as "the session's one connection has a progress"
        let table = process.named_subject(replay.table.name)
        let _killer =
          process.spawn(fn() {
            event_wait.until("the shell took the accept", fn() {
              wire_replay.taken(progress) >= 1
            })
            let assert [shell] = ask_support.connections(server)
              as "the connection is open"
            process.kill(listener)
            event_wait.until("the connection's shell ended", fn() {
              !process.is_alive(shell)
            })
            replay_table.timer_started(
              table:,
              connection: support.rule_recording_file(),
              timer: 99,
              started: replay_table.Started(
                subject: process.new_subject(),
                reference: reference.new(),
              ),
            )
          })
        Nil
      },
    )
  case result {
    Error(EndedEarly(connection:, ..))
    | Error(TookOutOfOrder(connection:, ..)) -> {
      assert connection == support.rule_recording_file()
        as "the failure names the connection the listener's end cut off"
    }
    Ok(Nil) -> panic as "the connection ended where the recording goes on"
    Error(Refused(..))
    | Error(FixtureFailed(..))
    | Error(NotConnected(..))
    | Error(Differs(..))
    | Error(Silent(..))
    | Error(Unexpected(..))
    | Error(NeverTaken(..))
    | Error(TimerNeverStarted(..))
    | Error(TookUnrecordedInput(..))
    | Error(StillOpen(..))
    | Error(TableLost) ->
      panic as "the replay failed some other way than by the connection ending"
  }
  let assert Ok(replay) = process.receive(replays, 0) as "the replay"
  assert replay.scripts() == Error(Nil)
    as "the restarted listener is handed no script again: each recorded connection had its one"
}

pub fn the_message_at_a_difference_is_the_one_that_holds_its_offset_test() -> Nil {
  use <- owned_test.run(30_000)
  let assert Ok(first) = frame.encode(0x0117, <<1, 2, 3>>)
  let assert Ok(second) = frame.encode(0x0118, <<4, 5, 6>>)
  let assert Ok(changed) = frame.encode(0x0118, <<4, 9, 6>>)
  assert wire_replay.compare(<<first:bits, second:bits>>, <<
      first:bits,
      changed:bits,
    >>)
    == Error(Difference(
      offset: 16,
      recorded: Message(message_id: 0x0118, name: "0x0118", text: "040506"),
      written: Message(message_id: 0x0118, name: "0x0118", text: "040906"),
    ))
    as "the first message is 9 bytes, so the second body's second byte is at offset 9 + 7: each side shows the second message, not the first"
}
