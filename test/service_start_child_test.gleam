//// Starting a child of a named factory supervisor (`service.start_child`), the
//// asker's way into the store. Expected values come from OTP: `supervisor:
//// start_child/2` is a `gen_server:call` with no timeout, which exits the
//// caller with `{noproc, {gen_server, call, _}}` when no process holds the
//// name, and with `{shutdown, {gen_server, call, _}}` when the supervisor
//// ends, with the reason `shutdown`, while the call waits in its mailbox, as
//// it does for a call made while the supervisor stops its children. Both mean
//// the supervisor is not running, which `start_child` answers `Error(Nil)`.

import ask_support
import genesis_prime/service
import genesis_prime/step/runtime.{Shutdown}
import gleam/bool
import gleam/erlang/process.{type Pid, type Subject}
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/supervision
import mailbox_support
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
      let pid =
        process.spawn(fn() {
          process.trap_exits(True)
          let _exit =
            process.new_selector()
            |> process.select_trapped_exits(fn(exit) { exit })
            |> process.selector_receive_forever
          let release = process.new_subject()
          process.send(held, release)
          let assert Ok(Nil) = process.receive(release, 30_000)
            as "the test let the child end"
          runtime.exit_now(Shutdown)
        })
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
    == Error(Nil)
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
  let assert Ok(release) = process.receive(held, ask_support.event_wait_ms)
    as "the child was asked to stop"
  let results = process.new_subject()
  let _caller =
    process.spawn_unlinked(fn() {
      process.send(
        results,
        service.start_child(supervisor: name, argument: held),
      )
    })
  await_queued(supervisor)
  process.send(release, Nil)
  let _reason = ask_support.ended(stopped)
  let assert Ok(result) = process.receive(results, ask_support.event_wait_ms)
    as "the call returned"
  assert result == Error(Nil)
    as "a call that waited while the supervisor stopped, and ended with it, is answered not running"
}

/// Waits until the call is in the supervisor's mailbox.
fn await_queued(supervisor: Pid) -> Nil {
  use <- bool.guard(when: mailbox_support.queued(supervisor) > 0, return: Nil)
  process.sleep(1)
  await_queued(supervisor)
}
