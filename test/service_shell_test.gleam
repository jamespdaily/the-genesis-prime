//// The service shell, proven on the hand-off rule and on the gate. Expected
//// values come from these places.
//// - The shell's contract in the doc comment of `genesis_prime/service/shell`,
////   as approved on the login processes card: its first input, how callers are
////   numbered, what a stop gives and which effects it refuses.
//// - The hand-off's answers in the doc comment of `genesis_prime/hand_off`.
//// - Send and Watch in the same doc comment: the address is looked up with the
////   settings' `reach`, and a watch's end comes back once as `WatchEnded` with
////   the watch's id (the watches themselves are tested in `watch_test`). The
////   gate answers `Opened(n)` to a caller waiting for key `n` when watch `n`
////   ends.
//// - OTP's supervisor: a permanent child is restarted when it crashes, and
////   `supervisor:which_children` answers after the supervisor has handled the
////   exit it already received.
//// Every wait is for an event, with a deadline a passing test never reaches.

import ask_support
import asking_rule
import gate_rule
import genesis_prime/hand_off.{Holder, Kept, Put, SessionKey, Take, Taken}
import genesis_prime/login/guid
import genesis_prime/rule_recording.{type Record, End, Taken as Recorded}
import genesis_prime/rule_recording/file
import genesis_prime/service
import genesis_prime/service/shell as service_shell
import genesis_prime/step.{
  type Address, Asked, CallerId, Connection, ConnectionId, Effects, Input, Reply,
  Sessions, Started, Stop, Stopping,
}
import genesis_prime/store.{AccountId}
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
import supervisor_children

pub fn a_service_starts_under_its_supervisor_by_its_name_and_its_first_input_is_started_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let name = process.new_name("hand_off")
  let tree =
    start_tree(hand_off_child(
      name:,
      shutdown_ms: 1000,
      recorder: Some(recording_support.recorder(
        folder,
        rule_module: hand_off.rule_name,
      )),
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
  use folder <- recording_support.in_folder
  let name = process.new_name("hand_off")
  let tree =
    start_tree(hand_off_child(
      name:,
      shutdown_ms: 1000,
      recorder: Some(recording_support.recorder(
        folder,
        rule_module: hand_off.rule_name,
      )),
    ))
  let assert Ok(pid) = process.named(name) as "the name is registered"
  let key = SessionKey(a_guid())
  let holder =
    Holder(
      account_id: AccountId(7),
      login_name: "login-7",
      game_account_id: a_guid(),
    )
  let replies = process.new_subject()
  assert service.call(name, Put(key:, holder:, lifetime_ms: 60_000), fn(answer) {
      process.send(replies, answer)
    })
    == Ok(service.ToService(pid))
    as "the call reached the process holding the name"
  assert process.receive(replies, within: ask_support.event_wait_ms) == Ok(Kept)
    as "the rule's reply reached the asker"
  assert service.call(name, Take(key:), fn(answer) {
      process.send(replies, answer)
    })
    == Ok(service.ToService(pid))
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
      rule: asking_rule.rule(),
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
  ask_support.command(client, asking_rule.await_command, 1, wait_ms: 300)
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
  use folder <- recording_support.in_folder
  let name = process.new_name("hand_off")
  let shutdown_ms = 1500
  let tree =
    start_tree(hand_off_child(
      name:,
      shutdown_ms: shutdown_ms,
      recorder: Some(recording_support.recorder(
        folder,
        rule_module: hand_off.rule_name,
      )),
    ))
  let assert Ok(pid) = process.named(name) as "the name is registered"
  let service = process.monitor(pid)
  let before_stop = ask_support.monotonic_ms()
  let stopped = ask_support.begin_stop_tree(tree)
  assert ask_support.ended(service) == ask_support.shutdown()
    as "the service exits with the reason shutdown, never normal"
  let _reason = ask_support.ended(stopped)
  let after_stop = ask_support.monotonic_ms()
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
      rule: asking_rule.rule(),
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
    asking_rule.open_command,
    5,
    wait_ms: ask_support.patient,
  )
  let _asked = ask_support.read_record(client)
  let opened = ask_support.read_record(client)
  assert opened.code == asking_rule.code_echoed
    as "key 5 is open in the gate's state"
  ask_support.command(
    client,
    asking_rule.crash_command,
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
  ask_support.command(client, asking_rule.await_command, 5, wait_ms: 300)
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
      let assert Ok(service.ToService(_)) =
        service.call(gate, message, fn(_answer) { Nil })
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

pub fn a_send_is_handed_to_the_receivers_address_and_one_to_a_receiver_not_running_is_dropped_test() -> Nil {
  use <- owned_test.run(30_000)
  let sent = process.new_subject()
  let running = Connection(ConnectionId(1))
  let reach =
    service.Reach(locate: fn(_address) { Error(Nil) }, send: fn(to, message) {
      process.send(sent, #(to, message))
      case to == running {
        True -> Ok(Nil)
        False -> Error(Nil)
      }
    })
  let gate = process.new_name("gate")
  let tree =
    start_tree(ask_support.reaching(
      name: gate,
      shutdown_ms: 1000,
      recorder: None,
      reach:,
    ))
  let assert Ok(pid) = process.named(gate) as "the gate runs"
  assert ask_support.call_gate(gate, gate_rule.SendTo(running, 3))
    == gate_rule.Echoed(3)
    as "the step went on to its reply"
  assert process.receive(sent, within: ask_support.event_wait_ms)
    == Ok(#(running, gate_rule.Echoed(3)))
    as "the shell asked reach to send the rule's message to the rule's address"
  let absent = Connection(ConnectionId(2))
  assert ask_support.call_gate(gate, gate_rule.SendTo(absent, 4))
    == gate_rule.Echoed(4)
    as "a receiver that is not running drops the message and the step goes on"
  assert process.receive(sent, within: ask_support.event_wait_ms)
    == Ok(#(absent, gate_rule.Echoed(4)))
  assert process.named(gate) == Ok(pid)
    as "the same process goes on: a dropped message is no failure"
  let _reason = ask_support.stop_tree(tree)
  Nil
}

pub fn a_watched_process_that_ends_comes_back_once_as_watch_ended_with_the_watchs_id_test() -> Nil {
  use <- owned_test.run(30_000)
  let target = process.spawn_unlinked(process.sleep_forever)
  let gate = process.new_name("gate")
  let tree = start_tree(watching(gate:, locating: Sessions, at: target))
  let replies = process.new_subject()
  let assert Ok(service.ToService(_)) =
    service.call(gate, gate_rule.Await(key: 1), fn(answer) {
      process.send(replies, answer)
    })
    as "the gate took the wait for key 1"
  assert ask_support.call_gate(gate, gate_rule.WatchAddress(1, Sessions))
    == gate_rule.Echoed(1)
    as "the address is found with reach's locate, which names the target"
  assert ask_support.call_gate(gate, gate_rule.Echo(0)) == gate_rule.Echoed(0)
  assert process.receive(replies, within: 0) == Error(Nil)
    as "the target runs, so the watch has not ended"
  let ended = process.monitor(target)
  process.kill(target)
  let _reason = ask_support.ended(ended)
  assert process.receive(replies, within: ask_support.event_wait_ms)
    == Ok(gate_rule.Opened(1))
    as "the target's end reached the rule as WatchEnded(WatchId(1))"
  let _reason = ask_support.stop_tree(tree)
  Nil
}

pub fn a_service_step_of_stop_then_reply_still_answers_the_caller_before_the_process_ends_test() -> Nil {
  use <- owned_test.run(30_000)
  let gate = process.new_name("gate")
  let tree =
    start_tree(ask_support.gate(name: gate, shutdown_ms: 1000, recorder: None))
  let assert Ok(pid) = process.named(gate) as "the gate runs"
  let service = process.monitor(pid)
  let replies = process.new_subject()
  let assert Ok(service.ToService(_)) =
    service.call(gate, gate_rule.StopThenReply, fn(answer) {
      process.send(replies, answer)
    })
    as "the gate took the ask"
  assert process.receive(replies, within: ask_support.event_wait_ms)
    == Ok(gate_rule.Echoed(9))
    as "the reply after Stop was carried out"
  assert ask_support.ended(service) == ask_support.shutdown()
    as "and then the process ended with the reason shutdown"
  let _reason = ask_support.stop_tree(tree)
  Nil
}

// ---- helpers ----

/// The gate as a child whose `locate` finds `target` at `locating` and no
/// process at any other address.
fn watching(
  gate gate: process.Name(service.Call(gate_rule.Message, gate_rule.Answer)),
  locating locating: Address,
  at target: process.Pid,
) -> ChildSpecification(Nil) {
  ask_support.reaching(
    name: gate,
    shutdown_ms: 1000,
    recorder: None,
    reach: service.Reach(
      locate: fn(address) {
        case address == locating {
          True -> Ok(target)
          False -> Error(Nil)
        }
      },
      send: fn(_to, _message) { Error(Nil) },
    ),
  )
}

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
  name name: process.Name(service.Call(hand_off.Message, hand_off.Answer)),
  shutdown_ms shutdown_ms: Int,
  recorder recorder: Option(file.Recorder),
) -> ChildSpecification(Nil) {
  service_shell.supervised(service_shell.Settings(
    rule: hand_off.rule(),
    name:,
    reach: service.Reach(
      locate: fn(_address) { Error(Nil) },
      send: fn(_to, _message) { Error(Nil) },
    ),
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

/// The records of the one recording in the folder, after the header.
fn recorded(
  folder: String,
) -> List(Record(hand_off.Message, Nil, hand_off.Answer, Nil)) {
  let assert Ok(#(_, records)) =
    rule_recording.read(recording_support.recording_in(folder))
    as "the recording reads"
  records
}
