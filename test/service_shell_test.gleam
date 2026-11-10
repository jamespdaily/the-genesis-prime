//// The service shell, proven on the hand-off rule and on the gate. Expected
//// values come from these places.
//// - The shell's contract in the doc comment of `genesis_prime/service/shell`,
////   as approved on the login processes card: its first input, how callers are
////   numbered and what a stop gives.
//// - The hand-off's answers in the doc comment of `genesis_prime/hand_off`.
//// - Send and Watch in the same doc comment: the address is looked up with the
////   settings' `reach`, and a watch's end comes back once as `WatchEnded` with
////   the watch's id (the watches themselves are tested in `watch_test`); a
////   target no process holds ends as the next input, after the step's effects
////   and before the mailbox is read, the step's watches in the order opened.
////   The gate answers `Opened(n)` to a caller waiting for key `n` when watch
////   `n` ends.
//// - OTP's supervisor: a permanent child is restarted when it crashes, and
////   `supervisor:which_children` answers after the supervisor has handled the
////   exit it already received.
//// Every wait is for an event, with a deadline a passing test never reaches.

import ask_support
import asking_rule
import gate_rule
import genesis_prime/group_registry
import genesis_prime/hand_off.{Holder, Kept, Put, SessionKey, Take, Taken}
import genesis_prime/login/guid
import genesis_prime/service
import genesis_prime/service/shell as service_shell
import genesis_prime/step.{
  type Address, type Event, type NoAsk, type ServiceEffect, type ServiceEvent,
  type Step, Asked, CallerId, Connection, ConnectionId, Creature,
  CreatureNotStarted, Effects, OwnEffect, OwnEvent, Reply, Rule, Send,
  ServiceTimerFired, Sessions, Started, Stop, Stopping, Told, WatchEnded,
  WatchId,
}
import genesis_prime/store.{AccountId}
import genesis_prime/world_map/map_id.{MapId}
import gleam/erlang/atom
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/string
import log_capture
import mailbox_support
import mug
import owned_test
import supervisor_children

pub fn a_service_starts_under_its_supervisor_by_its_name_and_its_first_input_is_started_test() -> Nil {
  use <- owned_test.run(30_000)
  let name = process.new_name("hand_off")
  let observed = process.new_subject()
  let tree =
    ask_support.start_tree(hand_off_child(
      name:,
      shutdown_ms: 1000,
      observed: Some(observed),
    ))
  let assert Ok(pid) = process.named(name) as "the name is registered"
  assert supervisor_children.in_start_order(tree) == [pid]
    as "the process holding the name is the supervisor's child"
  let assert Ok(#(OwnEvent(Started), first)) =
    process.receive(observed, within: ask_support.event_wait_ms)
    as "the first input the rule took is Started"
  assert first == Effects([]) as "Started does nothing"
  let _reason = ask_support.stop_tree(tree)
  Nil
}

pub fn an_ask_reaches_the_rule_as_asked_and_its_reply_reaches_the_asker_test() -> Nil {
  use <- owned_test.run(30_000)
  let name = process.new_name("hand_off")
  let observed = process.new_subject()
  let tree =
    ask_support.start_tree(hand_off_child(
      name:,
      shutdown_ms: 1000,
      observed: Some(observed),
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
    #(OwnEvent(Started), _),
    #(
      OwnEvent(Asked(caller: CallerId(1), message: Put(lifetime_ms: 60_000, ..))),
      Effects([OwnEffect(Reply(CallerId(1), Kept))]),
    ),
    #(
      OwnEvent(Asked(caller: CallerId(2), message: Take(..))),
      Effects([OwnEffect(Reply(CallerId(2), Taken(..)))]),
    ),
    ..
  ] = mailbox_support.drain(observed)
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
      with: fn(builder) {
        supervisor.add(builder, ask_support.gate(name: gate, shutdown_ms: 1000))
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
  let _reason =
    ask_support.ended(
      watched: gone,
      what: "the connection to end after the client closed",
    )
  assert ask_support.open_key(gate, 1) == 1
    as "the gate answered the asker that had gone, and went on to answer us"
  assert process.named(gate) == Ok(pid) as "the same process goes on"
  assert ask_support.call_gate(gate, gate_rule.Echo(3)) == gate_rule.Echoed(3)
    as "and still answers"
  ask_support.stop(server)
}

pub fn the_trees_stop_arrives_as_stopping_with_the_childs_shutdown_time_from_its_arrival_test() -> Nil {
  use <- owned_test.run(30_000)
  let name = process.new_name("hand_off")
  let shutdown_ms = 1500
  let observed = process.new_subject()
  let tree =
    ask_support.start_tree(hand_off_child(
      name:,
      shutdown_ms:,
      observed: Some(observed),
    ))
  let assert Ok(pid) = process.named(name) as "the name is registered"
  let service = process.monitor(pid)
  let before_stop = ask_support.monotonic_ms()
  let stopped = ask_support.begin_stop_tree(tree)
  assert ask_support.ended(
      watched: service,
      what: "the service to end at the stop",
    )
    == ask_support.shutdown()
    as "the service exits with the reason shutdown, never normal"
  let _reason =
    ask_support.ended(watched: stopped, what: "the stopped tree to end")
  let after_stop = ask_support.monotonic_ms()
  let assert [#(OwnEvent(Started), _), #(Stopping(deadline_ms:), stop)] =
    mailbox_support.drain(observed)
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
      with: fn(builder) {
        supervisor.add(builder, ask_support.gate(name: gate, shutdown_ms: 1000))
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

pub fn a_send_is_handed_to_the_receivers_address_and_one_to_a_receiver_not_running_is_dropped_test() -> Nil {
  use <- owned_test.run(30_000)
  let sent = process.new_subject()
  let running = Connection(ConnectionId(1))
  let reach =
    service.Reach(
      locate: fn(_address) { Error(Nil) },
      send: fn(to, message) {
        process.send(sent, #(to, message))
        case to == running {
          True -> Ok(Nil)
          False -> Error(Nil)
        }
      },
      start_creature: fn(_creature) { Error(service.SupervisorNotRunning) },
    )
  let gate = process.new_name("gate")
  let tree =
    ask_support.start_tree(ask_support.reaching(
      name: gate,
      shutdown_ms: 1000,
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
  let tree =
    ask_support.start_tree(watching(gate:, locating: Sessions, at: target))
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
  let _reason =
    ask_support.ended(watched: ended, what: "the killed target to end")
  assert process.receive(replies, within: ask_support.event_wait_ms)
    == Ok(gate_rule.Opened(1))
    as "the target's end reached the rule as WatchEnded(WatchId(1))"
  let _reason = ask_support.stop_tree(tree)
  Nil
}

pub fn a_watch_of_a_target_no_process_holds_ends_as_the_next_input_before_a_message_already_queued_test() -> Nil {
  use <- owned_test.run(30_000)
  assert inputs_when_queued(
      first: gate_rule.WatchAddress(1, Sessions),
      then: gate_rule.Echo(2),
    )
    == [
      OwnEvent(Started),
      OwnEvent(Asked(
        caller: CallerId(1),
        message: gate_rule.WatchAddress(1, Sessions),
      )),
      WatchEnded(watch: WatchId(1)),
      OwnEvent(Asked(caller: CallerId(2), message: gate_rule.Echo(2))),
    ]
    as "the rule's inputs are X, then the end of X's watch, then Y: the end is the next input after the step, before the mailbox is read"
}

pub fn two_watches_of_targets_no_process_holds_end_in_the_order_opened_before_the_next_mailbox_input_test() -> Nil {
  use <- owned_test.run(30_000)
  assert inputs_when_queued(
      first: gate_rule.WatchEach([1, 2], Sessions),
      then: gate_rule.Echo(3),
    )
    == [
      OwnEvent(Started),
      OwnEvent(Asked(
        caller: CallerId(1),
        message: gate_rule.WatchEach([1, 2], Sessions),
      )),
      WatchEnded(watch: WatchId(1)),
      WatchEnded(watch: WatchId(2)),
      OwnEvent(Asked(caller: CallerId(2), message: gate_rule.Echo(3))),
    ]
    as "one step's two watches end in the order opened, both before Y"
}

pub fn a_service_step_of_stop_then_reply_still_answers_the_caller_before_the_process_ends_test() -> Nil {
  use <- owned_test.run(30_000)
  let gate = process.new_name("gate")
  let tree =
    ask_support.start_tree(ask_support.gate(name: gate, shutdown_ms: 1000))
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
  assert ask_support.ended(
      watched: service,
      what: "the service to end at the stop",
    )
    == ask_support.shutdown()
    as "and then the process ended with the reason shutdown"
  let _reason = ask_support.stop_tree(tree)
  Nil
}

pub fn a_message_no_selector_takes_is_dropped_and_logged_by_its_kind_and_the_service_goes_on_test() -> Nil {
  use <- owned_test.run(30_000)
  let gate = process.new_name("gate")
  let tree =
    ask_support.start_tree(ask_support.gate(name: gate, shutdown_ms: 1000))
  let assert Ok(pid) = process.named(gate) as "the gate runs"
  let lines = process.new_subject()
  let capture = log_capture.start(from: pid, into: lines)
  mailbox_support.send_raw(
    pid,
    #(atom.create("stray_message"), <<
      "a-fake-session-key":utf8,
    >>),
  )
  let assert Ok(#(level, text)) =
    process.receive(lines, ask_support.event_wait_ms)
    as "the stray message was logged"
  log_capture.stop(capture)
  assert level == "warning" as "a message nobody takes is a warning"
  assert string.contains(text, "stray_message")
    as "the line names the message's kind, its tag"
  assert !string.contains(text, "a-fake-session-key")
    as "and never its contents, which could hold a secret"
  assert mailbox_support.tagged(pid, atom.create("stray_message")) == 0
    as "the message was taken from the mailbox"
  assert ask_support.call_gate(gate:, message: gate_rule.Echo(3))
    == gate_rule.Echoed(3)
    as "and the service goes on"
  let _reason = ask_support.stop_tree(tree)
  Nil
}

// ---- helpers ----

/// The inputs a gate takes when `first` and then `second` are queued behind
/// its suspended shell and it is resumed. The gate finds no process at any
/// address, so a watch of one is a watch of an address no process holds. They
/// are read as the gate's shell takes them, without the stop that ends it.
fn inputs_when_queued(
  first first: gate_rule.Message,
  then second: gate_rule.Message,
) -> List(Event(ServiceEvent(gate_rule.Message))) {
  let gate = process.new_name("gate")
  let observed = process.new_subject()
  let tree =
    ask_support.start_tree(ask_support.observed_gate(
      name: gate,
      shutdown_ms: 1000,
      into: observed,
    ))
  let assert Ok(pid) = process.named(gate) as "the gate runs"
  let replies = process.new_subject()
  ask_support.while_suspended(pid, fn() {
    let assert Ok(service.ToService(_)) =
      service.call(gate, first, fn(_answer) { Nil })
      as "the gate took the first message"
    let assert Ok(service.ToService(_)) =
      service.call(gate, second, fn(answer) { process.send(replies, answer) })
      as "the gate took the second message"
    Nil
  })
  let assert Ok(_answer) =
    process.receive(replies, within: ask_support.event_wait_ms)
    as "the second message was answered"
  let _reason = ask_support.stop_tree(tree)
  list.filter(mailbox_support.drain(observed), fn(event) {
    case event {
      Stopping(..) -> False
      OwnEvent(..) | WatchEnded(..) -> True
    }
  })
}

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
    reach: service.Reach(
      locate: fn(address) {
        case address == locating {
          True -> Ok(target)
          False -> Error(Nil)
        }
      },
      send: fn(_to, _message) { Error(Nil) },
      start_creature: fn(_creature) { Error(service.SupervisorNotRunning) },
    ),
  )
}

fn hand_off_child(
  name name: process.Name(service.Call(hand_off.Message, hand_off.Answer)),
  shutdown_ms shutdown_ms: Int,
  observed observed: Option(
    Subject(
      #(
        Event(ServiceEvent(hand_off.Message)),
        Step(NoAsk, ServiceEffect(hand_off.Answer)),
      ),
    ),
  ),
) -> ChildSpecification(Nil) {
  let rule = hand_off.rule()
  service_shell.supervised(
    name:,
    settings: service_shell.Settings(
      rule: case observed {
        Some(observed) ->
          Rule(..rule, step: fn(state, input) {
            let #(state, taken) = rule.step(state, input)
            process.send(observed, #(input.event, taken))
            #(state, taken)
          })
        None -> rule
      },
      reach: service.watch_only(locate: fn(_address) { Error(Nil) }),
      shutdown_ms:,
      found_at: None,
    ),
  )
}

fn a_guid() -> guid.Guid {
  let assert Ok(guid) =
    guid.from_wire(<<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>)
    as "sixteen bytes are a GUID"
  guid
}

// ---- a service with no name ----

/// The hand-off's settings with no name, for a service found by its subject.
fn unnamed_hand_off() -> service_shell.Settings(
  Nil,
  hand_off.State,
  hand_off.Message,
  hand_off.Answer,
) {
  service_shell.Settings(
    rule: hand_off.rule(),
    reach: service.watch_only(locate: fn(_address) { Error(Nil) }),
    shutdown_ms: 1000,
    found_at: None,
  )
}

pub fn an_unnamed_service_is_asked_through_the_subject_its_start_returns_and_says_where_it_went_test() -> Nil {
  use <- owned_test.run(30_000)
  let assert Ok(started) = service_shell.start_unnamed(unnamed_hand_off())
    as "an unnamed service starts as a child of the process that runs the start"
  let key = SessionKey(a_guid())
  let holder =
    Holder(
      account_id: AccountId(7),
      login_name: "login-7",
      game_account_id: a_guid(),
    )
  let #(sent, answer) =
    ask_support.ask_and_wait(send: fn(reply) {
      service.call_subject(
        started.data,
        Put(key:, holder:, lifetime_ms: 60_000),
        reply,
      )
    })
  assert sent == service.ToService(started.pid)
    as "the asker is told the service's own process, which it monitors"
  assert answer == Kept as "the rule's reply reached the asker"
  let #(_, answer) =
    ask_support.ask_and_wait(send: fn(reply) {
      service.call_subject(started.data, Take(key:), reply)
    })
  assert answer == Taken(holder:)
    as "the second ask is answered by the same service"
}

pub fn a_message_to_an_unnamed_service_that_ended_is_dropped_and_its_pid_is_still_reported_test() -> Nil {
  use <- owned_test.run(30_000)
  let assert Ok(started) = service_shell.start_unnamed(unnamed_hand_off())
    as "an unnamed service starts"
  process.unlink(started.pid)
  let ended = process.monitor(started.pid)
  process.kill(started.pid)
  let _reason =
    ask_support.ended(watched: ended, what: "the killed service to end")
  assert service.call_subject(
      started.data,
      Take(key: SessionKey(a_guid())),
      fn(_answer) { Nil },
    )
    == Ok(service.ToService(started.pid))
    as "no process holds the subject, and the asker's monitor of the pid it is told gives EndedBeforeAnswer"
}

// ---- a service found at an address ----

pub fn a_service_found_at_an_address_is_found_there_when_its_first_step_sends_test() -> Nil {
  use <- owned_test.run(30_000)
  let scope = group_registry.new(label: "found_at")
  let tree = ask_support.start_tree(group_registry.supervised(scope:))
  let address =
    Creature(
      map: MapId(world_id: 1387, instance: 0),
      incarnation: 1,
      unit_id: 5,
      life: 2,
    )
  // The send of the first step's message hands the test the sender and waits
  // for the test's lookup, so the lookup is made while that step is carried out.
  let sent = process.new_subject()
  let settings =
    service_shell.Settings(
      rule: Rule(
        name: "found at",
        settings: Nil,
        new: fn(_settings) { Nil },
        step: fn(state, input) {
          case input.event {
            OwnEvent(Started) -> #(
              state,
              Effects([OwnEffect(Send(to: Sessions, message: Nil))]),
            )
            OwnEvent(ServiceTimerFired(..))
            | OwnEvent(CreatureNotStarted(..))
            | OwnEvent(Asked(..))
            | OwnEvent(Told(..))
            | WatchEnded(..)
            | Stopping(..) -> #(state, Effects([]))
          }
        },
      ),
      reach: service.Reach(
        locate: fn(_address) { Error(Nil) },
        send: fn(_to, _message) {
          let looked = process.new_subject()
          process.send(sent, #(process.self(), looked))
          let assert Ok(Nil) =
            process.receive(looked, within: ask_support.event_wait_ms)
            as "the test looked the service up"
          Ok(Nil)
        },
        start_creature: fn(_creature) { Error(service.SupervisorNotRunning) },
      ),
      shutdown_ms: 1000,
      found_at: Some(service_shell.FoundAt(scope:, address:)),
    )
  let _starter =
    process.spawn(fn() {
      let assert Ok(_started) = service_shell.start_unnamed(settings)
        as "the service starts"
      process.sleep_forever()
    })
  let assert Ok(#(service, looked)) =
    process.receive(sent, within: ask_support.event_wait_ms)
    as "the first step sent its message"
  assert group_registry.find(scope:, group: address) == Ok(service)
    as "the service is found at its address when its first step sends"
  process.send(looked, Nil)
  let _reason = ask_support.stop_tree(tree)
  Nil
}
