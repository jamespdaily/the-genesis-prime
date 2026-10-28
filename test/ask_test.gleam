//// The connection shell's asks, proven on the asking rule and a gate service.
//// Expected values come from these places.
//// - The shell's contract in the doc comment of `genesis_prime/connection/
////   shell` ("An ask" and "The directory's own wait"), as approved on the
////   login processes card: the outcomes, their order and when each comes.
//// - The asking rule's records in the doc comment of `asking_rule`.
//// Every wait is for an event, with a deadline a passing test never reaches,
//// except where the test is about a deadline passing: those asks wait 300
//// milliseconds.

import ask_support
import asking_rule
import gate_rule
import genesis_prime/rule_recording.{type Record, End, Taken}
import genesis_prime/rule_recording/file
import genesis_prime/service
import genesis_prime/step.{
  Answered, AnsweredLate, EffectsThenAsk, Input, NoAnswerInTime,
}
import gleam/erlang/process
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/static_supervisor as supervisor
import mug
import owned_test
import recording_support

/// How long an ask whose deadline is meant to pass waits, in milliseconds.
const short = 300

pub fn an_answer_before_the_deadline_comes_back_after_the_steps_effects_and_the_bytes_sent_during_the_ask_come_after_it_test() -> Nil {
  use <- owned_test.run(30_000)
  let gate = process.new_name("gate")
  // The directory, which runs in the connection's process, reports that it was
  // called and waits for the test to say it has read the step's write. A shell
  // that made the ask before carrying out the step's effects would block here
  // before writing, and the test's read of the write would time out.
  let calls = process.new_subject()
  let reaching_the_gate =
    ask_support.directory(gate:, store: None, sent: ask_support.unreported)
  let server =
    ask_support.start(
      rule: asking_rule.rule(),
      directory: fn(request, deadline_ms, reply) {
        let acknowledged = process.new_subject()
        process.send(calls, #(acknowledged, deadline_ms))
        let assert Ok(Nil) =
          process.receive(acknowledged, within: ask_support.event_wait_ms)
          as "the test read the step's write before the directory went on"
        reaching_the_gate(request, deadline_ms, reply)
      },
      shutdown_ms: 1000,
      recorder: None,
      with: fn(builder) {
        supervisor.add(
          builder,
          ask_support.gate(name: gate, shutdown_ms: 1000, recorder: None),
        )
      },
    )
  let client = ask_support.connect(server)
  ask_support.command(
    client,
    asking_rule.await_command,
    1,
    wait_ms: ask_support.patient,
  )
  let assert Ok(#(acknowledged, given_deadline)) =
    process.receive(calls, within: ask_support.event_wait_ms)
    as "the shell reached the directory"
  let asked = ask_support.read_record(client)
  assert given_deadline == asked.milliseconds
    as "the directory is given the ask's own deadline, so a lookup on the way to the process (Maps') ends by it"
  assert asked.letter == asking_rule.asked && asked.ask == 1
    as "the step's own write was carried out before the ask was made"
  process.send(acknowledged, Nil)
  // The client sends while the ask is open; the shell reads it only after the
  // outcome, since the socket is not read again while the shell waits.
  ask_support.command(client, asking_rule.ping_command, 7, wait_ms: 0)
  let _waiting = ask_support.open_key(gate, 1)
  let outcome = ask_support.read_record(client)
  assert outcome.letter == asking_rule.outcome
    && outcome.ask == 1
    && outcome.code == asking_rule.code_opened
    && outcome.extra == 1
    as "the gate's answer comes back as the outcome of ask 1"
  assert outcome.milliseconds < asked.milliseconds
    as "the answer came before the ask's deadline"
  assert ask_support.read_pong(client) == <<0x70, 7>>
    as "the byte sent during the ask is read after the outcome"
  ask_support.stop(server)
}

pub fn an_ask_to_an_address_with_no_running_process_gives_not_running_at_once_and_sends_nothing_test() -> Nil {
  use <- owned_test.run(30_000)
  let gate = process.new_name("gate")
  let sent = process.new_subject()
  let server =
    ask_support.start(
      rule: asking_rule.rule(),
      directory: ask_support.directory(gate:, store: None, sent: fn(reached) {
        process.send(sent, reached)
      }),
      shutdown_ms: 1000,
      recorder: None,
      with: fn(builder) { builder },
    )
  let client = ask_support.connect(server)
  ask_support.command(
    client,
    asking_rule.echo_command,
    1,
    wait_ms: ask_support.patient,
  )
  let asked = ask_support.read_record(client)
  let outcome = ask_support.read_record(client)
  assert outcome.code == asking_rule.code_not_running
    as "no process holds the gate's name"
  assert outcome.milliseconds < asked.milliseconds
    as "at once, not at the ask's deadline"
  assert process.named(gate) == Error(Nil) as "nothing runs at the address"
  assert process.receive(sent, within: 0) == Error(Nil)
    as "the directory reached no process, so nothing was sent"
  ask_support.stop(server)
}

pub fn a_target_that_never_answers_gives_no_answer_in_time_and_not_before_the_deadline_test() -> Nil {
  use <- owned_test.run(30_000)
  let gate = process.new_name("gate")
  let server = start_with(gate:, shutdown_ms: 1000, recorder: None)
  let client = ask_support.connect(server)
  ask_support.command(client, asking_rule.ignore_command, 0, wait_ms: short)
  let asked = ask_support.read_record(client)
  let outcome = ask_support.read_record(client)
  assert outcome.letter == asking_rule.outcome
    && outcome.code == asking_rule.code_no_answer_in_time
    as "the gate took the ask and never answered"
  assert outcome.milliseconds >= asked.milliseconds
    as "not before the ask's deadline"
  ask_support.stop(server)
}

pub fn a_target_that_ends_before_answering_gives_ended_before_answer_test() -> Nil {
  use <- owned_test.run(30_000)
  let gate = process.new_name("gate")
  let server = start_with(gate:, shutdown_ms: 1000, recorder: None)
  let client = ask_support.connect(server)
  ask_support.command(
    client,
    asking_rule.crash_command,
    0,
    wait_ms: ask_support.patient,
  )
  let asked = ask_support.read_record(client)
  let outcome = ask_support.read_record(client)
  assert outcome.code == asking_rule.code_ended_before_answer
    as "the gate crashed on the ask"
  assert outcome.milliseconds < asked.milliseconds
    as "when the target ended, not at the ask's deadline"
  ask_support.stop(server)
}

pub fn an_answer_after_the_deadline_comes_as_answered_late_and_is_never_taken_for_a_newer_asks_answer_test() -> Nil {
  use <- owned_test.run(30_000)
  let gate = process.new_name("gate")
  let server = start_with(gate:, shutdown_ms: 1000, recorder: None)
  let client = ask_support.connect(server)
  ask_support.command(client, asking_rule.await_command, 1, wait_ms: short)
  let _asked_first = ask_support.read_record(client)
  let first = ask_support.read_record(client)
  assert first.ask == 1 && first.code == asking_rule.code_no_answer_in_time
    as "ask 1 timed out"
  // Opening key 1 makes the gate answer ask 1, which is already over, and then
  // answer this ask, 2, in that order: the older answer is in the mailbox first.
  ask_support.command(
    client,
    asking_rule.open_command,
    1,
    wait_ms: ask_support.patient,
  )
  let _asked_second = ask_support.read_record(client)
  let second = ask_support.read_record(client)
  assert second.ask == 2
    && second.code == asking_rule.code_echoed
    && second.extra == 1
    as "ask 2 got the gate's answer to ask 2, not the late answer to ask 1"
  let late = ask_support.read_record(client)
  assert late.letter == asking_rule.late && late.ask == 1
    as "the answer to ask 1 comes as AnsweredLate of ask 1"
  ask_support.stop(server)
}

pub fn a_stop_during_an_ask_ends_the_wait_at_once_and_stopping_counts_from_the_stops_arrival_test() -> Nil {
  use <- owned_test.run(30_000)
  let gate = process.new_name("gate")
  let shutdown_ms = 2000
  let server = start_with(gate:, shutdown_ms:, recorder: None)
  let client = ask_support.connect(server)
  ask_support.command(
    client,
    asking_rule.await_command,
    1,
    wait_ms: ask_support.patient,
  )
  let asked = ask_support.read_record(client)
  let before_stop = ask_support.monotonic_ms()
  let stopped = ask_support.begin_stop_tree(server.supervisor)
  let outcome = ask_support.read_record(client)
  let stopping = ask_support.read_record(client)
  let after_stopping = ask_support.monotonic_ms()
  assert outcome.ask == 1 && outcome.code == asking_rule.code_stopped_waiting
    as "the stop ended the wait"
  assert outcome.milliseconds < asked.milliseconds
    as "at once, not at the ask's deadline"
  assert stopping.letter == asking_rule.stopping
    as "Stopping is the input after the outcome"
  // The connection settings' send deadline is 300 ms (ask_support.start).
  assert stopping.milliseconds >= before_stop + shutdown_ms - 300
    && stopping.milliseconds <= after_stopping + shutdown_ms - 300
    as "the deadline is the stop's arrival plus the shutdown time less the send deadline"
  let _waiting = ask_support.open_key(gate, 1)
  let late = ask_support.read_record(client)
  assert late.letter == asking_rule.late && late.ask == 1
    as "the answer after the stop comes as AnsweredLate"
  assert ask_support.ended(stopped) == ask_support.shutdown()
    as "the tree stopped when the rule had stopped"
}

pub fn a_recorded_session_with_asks_replays_to_the_same_steps_with_no_other_process_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let gate = process.new_name("gate")
  let server =
    start_with(
      gate:,
      shutdown_ms: 1000,
      recorder: Some(recording_support.recorder(
        folder,
        rule_module: "asking_rule",
      )),
    )
  let client = ask_support.connect(server)
  ask_support.command(
    client,
    asking_rule.echo_command,
    5,
    wait_ms: ask_support.patient,
  )
  let _asked = ask_support.read_record(client)
  let _echoed = ask_support.read_record(client)
  ask_support.command(client, asking_rule.await_command, 1, wait_ms: short)
  let _asked = ask_support.read_record(client)
  let _timed_out = ask_support.read_record(client)
  ask_support.command(
    client,
    asking_rule.open_command,
    1,
    wait_ms: ask_support.patient,
  )
  let _asked = ask_support.read_record(client)
  let _opened = ask_support.read_record(client)
  let _late = ask_support.read_record(client)
  ask_support.command(client, asking_rule.ping_command, 3, wait_ms: 0)
  let _pong = ask_support.read_pong(client)
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  let watched = process.monitor(connection)
  let assert Ok(Nil) = mug.shutdown(client) as "the client closed"
  let _reason = ask_support.ended(watched)
  ask_support.stop(server)
  assert process.named(gate) == Error(Nil)
    as "no other process runs: the gate and the listener are gone"
  let bytes = recording_support.recording_in(folder)
  let assert Ok(#(_, records)) = rule_recording.read(bytes)
    as "the recording reads"
  assert list.count(records, is_ask) == 3
    as "the session made three asks, each ending its step"
  assert list.any(records, is_timed_out) && list.any(records, is_late)
    as "the session holds an ask that timed out and its late answer"
  let assert Ok(count) =
    rule_recording.replay(
      bytes,
      asking_rule.rule(),
      recording_support.types_digest("asking_rule"),
      None,
    )
    as "every recorded step is the step the rule gives again"
  assert list.last(records) == Ok(End(count:))
    as "End counts the inputs the replay folded"
}

pub fn a_connection_step_of_stop_then_write_still_writes_the_bytes_before_the_socket_closes_test() -> Nil {
  use <- owned_test.run(30_000)
  let gate = process.new_name("gate")
  let server = start_with(gate:, shutdown_ms: 1000, recorder: None)
  let client = ask_support.connect(server)
  ask_support.command(
    client,
    asking_rule.stop_then_write_command,
    4,
    wait_ms: 0,
  )
  assert ask_support.read_pong(client) == <<0x71, 4>>
    as "the write after Stop reached the client"
  assert mug.receive(client, timeout_milliseconds: ask_support.event_wait_ms)
    == Error(mug.Closed)
    as "and the socket closed after it"
  ask_support.stop(server)
}

// ---- helpers ----

fn start_with(
  gate gate: process.Name(service.Call(gate_rule.Message, gate_rule.Answer)),
  shutdown_ms shutdown_ms: Int,
  recorder recorder: Option(file.Recorder),
) -> ask_support.Server {
  ask_support.start(
    rule: asking_rule.rule(),
    directory: ask_support.directory(
      gate:,
      store: None,
      sent: ask_support.unreported,
    ),
    shutdown_ms:,
    recorder:,
    with: fn(builder) {
      supervisor.add(
        builder,
        ask_support.gate(name: gate, shutdown_ms: 1000, recorder: None),
      )
    },
  )
}

fn is_ask(
  record: Record(Nil, asking_rule.Answer, Nil, asking_rule.Request),
) -> Bool {
  case record {
    Taken(step: EffectsThenAsk(..), ..) -> True
    Taken(..) | End(..) -> False
  }
}

fn is_timed_out(
  record: Record(Nil, asking_rule.Answer, Nil, asking_rule.Request),
) -> Bool {
  case record {
    Taken(input: Input(event: Answered(outcome: NoAnswerInTime, ..), ..), ..) ->
      True
    Taken(..) | End(..) -> False
  }
}

fn is_late(
  record: Record(Nil, asking_rule.Answer, Nil, asking_rule.Request),
) -> Bool {
  case record {
    Taken(input: Input(event: AnsweredLate(..), ..), ..) -> True
    Taken(..) | End(..) -> False
  }
}
