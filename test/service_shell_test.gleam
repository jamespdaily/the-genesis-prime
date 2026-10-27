//// The service shell, proven on the hand-off rule and on the gate. Expected
//// values come from these places.
//// - The shell's contract in the doc comment of `genesis_prime/service/shell`,
////   as approved on the login processes card: its first input, how callers are
////   numbered, what a stop gives and which effects it refuses.
//// - The hand-off's answers in the doc comment of `genesis_prime/hand_off`.
//// - OTP's supervisor: a permanent child is restarted when it crashes, and
////   `supervisor:which_children` answers after the supervisor has handled the
////   exit it already received.
//// Every wait is for an event, with a deadline a passing test never reaches.

import ask_support
import asking_rule
import gate_rule
import genesis_prime/hand_off.{Holder, Kept, Put, SessionKey, Take, Taken}
import genesis_prime/login/guid
import genesis_prime/rule_recording.{type Record, End, Header, Taken as Recorded}
import genesis_prime/rule_recording/file
import genesis_prime/rule_types
import genesis_prime/service/shell as service_shell
import genesis_prime/step.{
  Asked, CallerId, Effects, Input, Reply, Rule, Started, Stop, Stopping,
}
import genesis_prime/store.{AccountId}
import gleam/erlang/atom
import gleam/erlang/process
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/string
import log_capture
import mug
import owned_test
import recording_support
import simplifile
import supervisor_children

pub fn a_service_starts_under_its_supervisor_by_its_name_and_its_first_input_is_started_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- in_folder
  let name = process.new_name("hand_off")
  let tree =
    start_tree(hand_off_child(
      name:,
      shutdown_ms: 1000,
      recorder: Some(recorder(folder)),
    ))
  let assert Ok(pid) = process.named(name) as "the name is registered"
  assert supervisor_children.in_start_order(tree) == [pid]
    as "the process holding the name is the supervisor's child"
  let assert [Recorded(input: Input(event: Started, ..), step: first), ..] =
    recorded(folder)
    as "the recording begins with an input"
  assert first == Effects([]) as "Started is the first input, and does nothing"
  let _reason = ask_support.stop_tree(tree)
  Nil
}

pub fn an_ask_reaches_the_rule_as_asked_and_its_reply_reaches_the_asker_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- in_folder
  let name = process.new_name("hand_off")
  let tree =
    start_tree(hand_off_child(
      name:,
      shutdown_ms: 1000,
      recorder: Some(recorder(folder)),
    ))
  let assert Ok(pid) = process.named(name) as "the name is registered"
  let key = SessionKey(a_guid())
  let holder = Holder(account_id: AccountId(7), login_name: "login-7")
  let replies = process.new_subject()
  assert service_shell.call(
      name,
      Put(key:, holder:, lifetime_ms: 60_000),
      fn(answer) { process.send(replies, answer) },
    )
    == Ok(service_shell.ToService(pid))
    as "the call reached the process holding the name"
  assert process.receive(replies, within: ask_support.event_wait_ms) == Ok(Kept)
    as "the rule's reply reached the asker"
  assert service_shell.call(name, Take(key:), fn(answer) {
      process.send(replies, answer)
    })
    == Ok(service_shell.ToService(pid))
  assert process.receive(replies, within: ask_support.event_wait_ms)
    == Ok(Taken(holder:))
    as "the second ask is answered with the holder the first one put"
  let _reason = ask_support.stop_tree(tree)
  let assert [
    Recorded(..),
    Recorded(
      input: Input(
        event: Asked(caller: CallerId(1), message: Put(lifetime_ms: 60_000, ..)),
        ..,
      ),
      step: Effects([Reply(CallerId(1), Kept)]),
    ),
    Recorded(
      input: Input(event: Asked(caller: CallerId(2), message: Take(..)), ..),
      step: Effects([Reply(CallerId(2), Taken(..))]),
    ),
    ..
  ] = recorded(folder)
    as "the callers are numbered from 1 in the order the asks arrived"
  Nil
}

pub fn a_reply_to_an_asker_that_stopped_waiting_is_dropped_and_the_process_goes_on_test() -> Nil {
  use <- owned_test.run(30_000)
  let gate = process.new_name("gate")
  let server =
    ask_support.start(
      directory: ask_support.directory(
        gate:,
        store: None,
        sent: ask_support.unreported,
      ),
      shutdown_ms: 1000,
      recorder: None,
      with: fn(builder) {
        supervisor.add(
          builder,
          ask_support.gate(name: gate, shutdown_ms: 1000, recorder: None),
        )
      },
    )
  let assert Ok(pid) = process.named(gate) as "the gate runs"
  let client = ask_support.connect(server)
  ask_support.command(client, ask_support.await_command, 1, wait_ms: 300)
  let _asked = ask_support.read_record(client)
  let timed_out = ask_support.read_record(client)
  assert timed_out.code == asking_rule.code_no_answer_in_time
    as "the asker stopped waiting"
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  let gone = process.monitor(connection)
  let assert Ok(Nil) = mug.shutdown(client) as "the client closed"
  let _reason = ask_support.ended(gone)
  assert ask_support.open_key(gate, 1) == 1
    as "the gate answered the asker that had gone, and went on to answer us"
  assert process.named(gate) == Ok(pid) as "the same process goes on"
  assert ask_support.call_gate(gate, gate_rule.Echo(3)) == gate_rule.Echoed(3)
    as "and still answers"
  ask_support.stop(server)
}

pub fn the_trees_stop_arrives_as_stopping_with_the_childs_shutdown_time_from_its_arrival_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- in_folder
  let name = process.new_name("hand_off")
  let shutdown_ms = 1500
  let tree =
    start_tree(hand_off_child(
      name:,
      shutdown_ms: shutdown_ms,
      recorder: Some(recorder(folder)),
    ))
  let assert Ok(pid) = process.named(name) as "the name is registered"
  let service = process.monitor(pid)
  let before_stop = monotonic_ms()
  let stopped = ask_support.begin_stop_tree(tree)
  assert ask_support.ended(service) == shutdown()
    as "the service exits with the reason shutdown, never normal"
  let _reason = ask_support.ended(stopped)
  let after_stop = monotonic_ms()
  let assert [
    Recorded(..),
    Recorded(input: Input(event: Stopping(deadline_ms:), ..), step: stop),
    End(count: 2),
  ] = recorded(folder)
    as "Stopping came as the second input and the rule stopped"
  assert stop == Effects([Stop])
  assert deadline_ms >= before_stop + shutdown_ms
    && deadline_ms <= after_stop + shutdown_ms
    as "the deadline is the shutdown time from the stop's arrival"
}

pub fn a_crash_in_the_rule_restarts_it_empty_and_an_ask_made_meanwhile_gets_ended_before_answer_test() -> Nil {
  use <- owned_test.run(30_000)
  let gate = process.new_name("gate")
  let server =
    ask_support.start(
      directory: ask_support.directory(
        gate:,
        store: None,
        sent: ask_support.unreported,
      ),
      shutdown_ms: 1000,
      recorder: None,
      with: fn(builder) {
        supervisor.add(
          builder,
          ask_support.gate(name: gate, shutdown_ms: 1000, recorder: None),
        )
      },
    )
  let assert Ok(first) = process.named(gate) as "the gate runs"
  let client = ask_support.connect(server)
  ask_support.command(
    client,
    ask_support.open_command,
    5,
    wait_ms: ask_support.patient,
  )
  let _asked = ask_support.read_record(client)
  let opened = ask_support.read_record(client)
  assert opened.code == asking_rule.code_echoed
    as "key 5 is open in the gate's state"
  ask_support.command(
    client,
    ask_support.crash_command,
    0,
    wait_ms: ask_support.patient,
  )
  let _asked = ask_support.read_record(client)
  let crashed = ask_support.read_record(client)
  assert crashed.code == asking_rule.code_ended_before_answer
    as "the ask the gate crashed on ends with its process"
  let _restarted =
    ask_support.await_new_pid(
      name: gate,
      not: first,
      within_ms: ask_support.event_wait_ms,
    )
  ask_support.command(client, ask_support.await_command, 5, wait_ms: 300)
  let _asked = ask_support.read_record(client)
  let waited = ask_support.read_record(client)
  assert waited.code == asking_rule.code_no_answer_in_time
    as "key 5 is no longer open: the restart began from the rule's `new`"
  ask_support.stop(server)
}

pub fn a_refused_effect_ends_the_process_with_an_error_log_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #(gate_rule.TrySend, "Send"),
      #(gate_rule.TryWatch, "Watch"),
      #(gate_rule.TryTimer, "StartTimer"),
      #(gate_rule.TryAsk, "ask"),
    ],
    fn(refused) {
      let #(message, named_in_log) = refused
      let gate = process.new_name("gate")
      let tree =
        start_tree(ask_support.gate(
          name: gate,
          shutdown_ms: 1000,
          recorder: None,
        ))
      let assert Ok(pid) = process.named(gate) as "the gate runs"
      let logged = process.new_subject()
      let capture = log_capture.start(from: pid, into: logged)
      let service = process.monitor(pid)
      let assert Ok(service_shell.ToService(_)) =
        service_shell.call(gate, message, fn(_answer) { Nil })
        as "the gate took the ask"
      let assert process.Abnormal(_) = ask_support.ended(service)
        as "the service shell ended the process abnormally"
      let assert Ok(#("error", text)) =
        process.receive(logged, within: ask_support.event_wait_ms)
        as "the first thing logged is an error"
      assert string.contains(text, named_in_log)
        as "the error names the refused effect"
      log_capture.stop(capture)
      let _reason = ask_support.stop_tree(tree)
      Nil
    },
  )
}

pub fn a_service_step_of_stop_then_reply_still_answers_the_caller_before_the_process_ends_test() -> Nil {
  use <- owned_test.run(30_000)
  let gate = process.new_name("gate")
  let tree =
    start_tree(ask_support.gate(name: gate, shutdown_ms: 1000, recorder: None))
  let assert Ok(pid) = process.named(gate) as "the gate runs"
  let service = process.monitor(pid)
  let replies = process.new_subject()
  let assert Ok(service_shell.ToService(_)) =
    service_shell.call(gate, gate_rule.StopThenReply, fn(answer) {
      process.send(replies, answer)
    })
    as "the gate took the ask"
  assert process.receive(replies, within: ask_support.event_wait_ms)
    == Ok(gate_rule.Echoed(9))
    as "the reply after Stop was carried out"
  assert ask_support.ended(service) == shutdown()
    as "and then the process ended with the reason shutdown"
  let _reason = ask_support.stop_tree(tree)
  Nil
}

// ---- helpers ----

fn start_tree(child: ChildSpecification(Nil)) -> process.Pid {
  let assert Ok(started) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.restart_tolerance(intensity: 10, period: 5)
    |> supervisor.add(child)
    |> supervisor.start
    as "the tree started"
  process.unlink(started.pid)
  ask_support.guard(started.pid)
  started.pid
}

fn hand_off_child(
  name name: process.Name(service_shell.Call(hand_off.Message, hand_off.Answer)),
  shutdown_ms shutdown_ms: Int,
  recorder recorder: Option(file.Recorder(Nil)),
) -> ChildSpecification(Nil) {
  service_shell.supervised(service_shell.Settings(
    rule: Rule(
      name: "genesis_prime/hand_off",
      settings: Nil,
      new: hand_off.new,
      step: hand_off.step,
    ),
    name:,
    shutdown_ms:,
    recorder:,
  ))
}

fn a_guid() -> guid.Guid {
  let assert Ok(guid) =
    guid.from_wire(<<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>)
    as "sixteen bytes are a GUID"
  guid
}

fn recorder(folder: String) -> file.Recorder(Nil) {
  let assert Ok(digest) =
    rule_types.digest(rule_module: "genesis_prime/hand_off", source_roots: [
      "src",
      "test",
    ])
    as "the hand-off rule's types digest"
  file.recorder(
    folder:,
    header: Header(
      format: rule_recording.format,
      rule: "genesis_prime/hand_off",
      client_build: 16_042,
      tables_digest: None,
      settings: Nil,
      types_digest: digest,
    ),
  )
}

fn in_folder(body: fn(String) -> a) -> a {
  let folder = recording_support.new_folder()
  let result = body(folder)
  let assert Ok(Nil) = simplifile.delete(folder) as "the folder was removed"
  result
}

/// The records of the one recording in the folder, after the header.
fn recorded(
  folder: String,
) -> List(Record(hand_off.Message, Nil, hand_off.Answer, Nil)) {
  let assert Ok([name]) = simplifile.read_directory(folder)
    as "one recording in the folder"
  let assert Ok(bytes) = simplifile.read_bits(folder <> "/" <> name)
    as "the recording reads"
  let assert Ok(#(_, records)) = rule_recording.read(bytes)
    as "the recording reads"
  records
}

fn shutdown() -> process.ExitReason {
  process.Abnormal(atom.to_dynamic(atom.create("shutdown")))
}

fn monotonic_ms() -> Int {
  monotonic_time(atom.create("millisecond"))
}

@external(erlang, "erlang", "monotonic_time")
fn monotonic_time(unit: atom.Atom) -> Int
