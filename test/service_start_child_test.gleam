//// Starting a child of a named factory supervisor (`service.start_child`), the
//// asker's way into the store. Expected values come from OTP: `supervisor:
//// start_child/2` is a `gen_server:call` with no timeout, which exits the
//// caller with `{noproc, {gen_server, call, _}}` when no process holds the
//// name, and with `{shutdown, {gen_server, call, _}}` when the supervisor
//// ends, with the reason `shutdown`, while the call waits in its mailbox, as
//// it does for a call made while the supervisor stops its children. Both mean
//// the supervisor is not running, which `start_child` answers
//// `SupervisorNotRunning`. A supervisor that runs and whose child's start
//// reports a failure gives that failure, as `factory_supervisor.start_child`
//// returns it (`ChildNotStarted`).

import ask_support
import event_wait
import genesis_prime/service
import genesis_prime/step/runtime.{Shutdown}
import gleam/dynamic
import gleam/erlang/atom
import gleam/erlang/process.{type Pid, type Subject}
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/supervision
import gleam/string
import log_capture
import mailbox_support
import open_wait
import owned_test

/// What the held child sends when its supervisor has asked it to stop: the
/// subject that lets it end.
type Held =
  Subject(Subject(Nil))

/// A named factory supervisor of children that trap exits, and when asked to
/// stop hand `held` the subject that lets them end.
fn start_supervisor(
  name name: process.Name(factory_supervisor.Message(Held, Nil)),
) -> Pid {
  let assert Ok(started) =
    factory_supervisor.worker_child(fn(held: Held) {
      let ready = process.new_subject()
      let pid =
        process.spawn(fn() {
          process.trap_exits(True)
          process.send(ready, Nil)
          let _exit =
            process.new_selector()
            |> process.select_trapped_exits(fn(exit) { exit })
            |> process.selector_receive_forever
          let release = process.new_subject()
          process.send(held, release)
          let Nil =
            open_wait.received(
              from: release,
              what: "the test to let the child end",
            )
          runtime.exit_now(Shutdown)
        })
      // The child is started once it traps exits: the stop the supervisor
      // sends it is then a message it answers, and no exit signal ends it first.
      let Nil = open_wait.received(from: ready, what: "the child to trap exits")
      Ok(actor.Started(pid:, data: Nil))
    })
    |> factory_supervisor.named(name)
    |> factory_supervisor.restart_strategy(supervision.Temporary)
    |> factory_supervisor.restart_tolerance(intensity: 1, period: 5)
    |> factory_supervisor.timeout(ms: 30_000)
    |> factory_supervisor.start
    as "the supervisor started"
  // Its stop is the test's to watch: it must not take the test with it.
  process.unlink(started.pid)
  started.pid
}

pub fn a_name_no_process_holds_is_a_supervisor_that_is_not_running_test() -> Nil {
  use <- owned_test.run(10_000)
  let name = process.new_name("nobody")
  assert service.start_child(supervisor: name, argument: process.new_subject())
    == Error(service.SupervisorNotRunning)
}

pub fn a_child_whose_start_fails_gives_the_reason_its_start_reported_test() -> Nil {
  use <- owned_test.run(10_000)
  let name = process.new_name("failing_children")
  let assert Ok(started) =
    factory_supervisor.worker_child(fn(_argument: Nil) {
      Error(actor.InitFailed("no room"))
    })
    |> factory_supervisor.named(name)
    |> factory_supervisor.restart_strategy(supervision.Temporary)
    |> factory_supervisor.restart_tolerance(intensity: 1, period: 5)
    |> factory_supervisor.start
    as "the supervisor started"
  process.unlink(started.pid)
  ask_support.guard(started.pid)
  assert service.start_child(supervisor: name, argument: Nil)
    == Error(service.ChildNotStarted(actor.InitFailed("no room")))
    as "the supervisor runs, and the child's start said InitFailed(\"no room\"), which factory_supervisor.start_child gives as it is"
}

pub fn an_asker_of_a_child_that_does_not_start_logs_the_reason_and_one_of_a_supervisor_not_running_logs_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let name = process.new_name("failing_children")
  let assert Ok(started) =
    factory_supervisor.worker_child(fn(_argument: Nil) {
      Error(actor.InitFailed("no room"))
    })
    |> factory_supervisor.named(name)
    |> factory_supervisor.restart_strategy(supervision.Temporary)
    |> factory_supervisor.restart_tolerance(intensity: 1, period: 5)
    |> factory_supervisor.start
    as "the supervisor started"
  process.unlink(started.pid)
  ask_support.guard(started.pid)
  let lines = process.new_subject()
  let capture = log_capture.start(from: process.self(), into: lines)
  assert service.sent_to_worker(service.start_child(
      supervisor: name,
      argument: Nil,
    ))
    == Error(Nil)
    as "the asker's directory gives no process for a child that did not start"
  let #(level, text) =
    open_wait.received(from: lines, what: "the log line of the failed start")
  assert level == "warning" as "an outside failure the server went on from"
  assert string.contains(text, "no room")
    as "the reason the child's start gave is in the line"
  let nobody = process.new_name("nobody")
  assert service.sent_to_worker(service.start_child(
      supervisor: nobody,
      argument: Nil,
    ))
    == Error(Nil)
  log_capture.stop(capture)
  // Absence check: the limit is how long this watches for a message that must not come,
  // here a look at the mailbox now.
  assert process.receive(lines, 0) == Error(Nil)
    as "a supervisor that is not running logs nothing: it is stopping or restarting, and says so itself"
}

pub fn a_child_that_exits_while_it_starts_with_a_structured_reason_is_logged_with_the_reason_in_full_test() -> Nil {
  use <- owned_test.run(10_000)
  let name = process.new_name("exiting_children")
  let reason =
    dynamic.array([atom.to_dynamic(atom.create("boom")), dynamic.int(7)])
  let assert Ok(started) =
    factory_supervisor.worker_child(fn(_argument: Nil) {
      Error(actor.InitExited(process.Abnormal(reason)))
    })
    |> factory_supervisor.named(name)
    |> factory_supervisor.restart_strategy(supervision.Temporary)
    |> factory_supervisor.restart_tolerance(intensity: 1, period: 5)
    |> factory_supervisor.start
    as "the supervisor started"
  process.unlink(started.pid)
  ask_support.guard(started.pid)
  let lines = process.new_subject()
  let capture = log_capture.start(from: process.self(), into: lines)
  assert service.sent_to_worker(service.start_child(
      supervisor: name,
      argument: Nil,
    ))
    == Error(Nil)
    as "the asker's directory gives no process for a child that did not start"
  let #(level, text) =
    open_wait.received(from: lines, what: "the log line of the failed start")
  log_capture.stop(capture)
  assert level == "warning" as "an outside failure the server went on from"
  assert string.contains(text, "{boom,7}")
    as "the exit reason is Erlang's own term {boom, 7}, so the line says what ended the child and not only that it was a tuple"
}

pub fn a_supervisor_that_ends_while_the_call_waits_is_a_supervisor_that_is_not_running_test() -> Nil {
  use <- owned_test.run(30_000)
  let name = process.new_name("stopping_supervisor")
  let supervisor = start_supervisor(name:)
  let held = process.new_subject()
  let assert Ok(_child) = service.start_child(supervisor: name, argument: held)
    as "a child started"
  // The supervisor now stops its child, which holds the stop open.
  let stopped = ask_support.begin_stop_tree(supervisor)
  let release =
    open_wait.received(from: held, what: "the child to be asked to stop")
  let results = process.new_subject()
  let caller =
    process.spawn_unlinked(fn() {
      process.send(
        results,
        service.start_child(supervisor: name, argument: held),
      )
    })
  event_wait.until("the caller's call waits at the stopping supervisor", fn() {
    mailbox_support.call_waiting_from(pid: supervisor, caller:)
  })
  process.send(release, Nil)
  let _reason =
    ask_support.ended(watched: stopped, what: "the stopping supervisor to end")
  let result = open_wait.received(from: results, what: "the call to return")
  assert result == Error(service.SupervisorNotRunning)
    as "a call that waited while the supervisor stopped, and ended with it, is answered not running"
}
