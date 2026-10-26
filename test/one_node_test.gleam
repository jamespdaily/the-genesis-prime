//// Whether one node can hold every service, shown on planted services: a
//// login service and a world subtree under a top supervisor that has the
//// real top supervisor's settings (`server.supervisor()`).
////
//// Expected values come from three places.
//// - The OTP supervisor behaviour (OTP design principles, "Supervisor
////   Behaviour", "Restart Intensity"): a supervisor that restarts a child
////   more often than its intensity allows in its period terminates its
////   children and exits; its own supervisor then restarts it, or, past its
////   own intensity, exits too. A one for one supervisor restarts only the
////   child that failed.
//// - The top supervisor's settings in `src/genesis_prime/server.gleam`: one
////   for one, 3 restarts in 5 seconds. The planted world subtree has the
////   same numbers.
//// - `max_heap_size` with kill on (`erlang:process_flag/2`): a process whose
////   heap would pass the limit is killed, and its exit reason is `killed`.
////
//// Each test waits for the events it needs: a start reported by a planted
//// worker, or a monitor's down message.

import gleam/erlang/process.{type Monitor, type Pid}
import gleam/list
import owned_test
import planted_service.{type Settings, Settings}

/// How long a test waits for one event that must happen at once.
const event_wait_ms = 1000

/// Crashes of the planted crasher in a row that make the world subtree
/// exceed its intensity of 3 restarts in 5 seconds: the fourth.
const crashes_to_exceed_world_intensity = 4

pub fn a_crash_loop_in_the_world_subtree_restarts_the_world_subtree_and_leaves_the_login_alone_test() -> Nil {
  use <- owned_test.run(5000)
  let settings = planted_service.settings()
  let assert Ok(top) = planted_service.start_top(settings)
    as "the planted top supervisor did not start"
  let assert Ok(login_pid) =
    planted_service.next_start(settings.starts.login, event_wait_ms)
    as "the login did not report its start"
  let assert Ok(first_crasher) =
    planted_service.next_start(settings.starts.crasher, event_wait_ms)
    as "the crasher did not report its start"
  let assert Ok(first_grower) =
    planted_service.next_start(settings.starts.grower, event_wait_ms)
    as "the grower did not report its start"
  let login = process.named_subject(settings.names.login)
  let crasher = process.named_subject(settings.names.crasher)

  // Crashes 1 to 3 are within the world subtree's intensity: each replaces
  // the crasher alone. Crash 4 exceeds it, so the world subtree exits and the
  // top supervisor starts it again, which starts the crasher a fifth time.
  let crashers =
    repeat_crashes(
      settings:,
      crasher:,
      login:,
      remaining: crashes_to_exceed_world_intensity,
      seen: [first_crasher],
    )

  assert planted_service.ping(login, event_wait_ms) == Ok(Nil)
    as "the login did not answer after the world subtree was restarted"
  assert process.named(settings.names.login) == Ok(login_pid)
    as "the login was replaced"
  assert planted_service.next_start(settings.starts.login, 0) == Error(Nil)
    as "the login started again"
  assert process.is_alive(top.pid) as "the top supervisor stopped"

  // Three single restarts of the crasher, then one start of the whole world
  // subtree: the grower starts once more only then, and the crasher's last
  // start is a new process after that.
  let assert Ok(second_grower) =
    planted_service.next_start(settings.starts.grower, event_wait_ms)
    as "the grower did not start again with the world subtree"
  assert second_grower != first_grower
  assert planted_service.next_start(settings.starts.grower, 0) == Error(Nil)
    as "the world subtree was restarted more than once by the top supervisor"
  assert planted_service.next_start(settings.starts.crasher, 0) == Error(Nil)
    as "the crasher started more often than the crashes explain"
  assert list.length(crashers) == crashes_to_exceed_world_intensity + 1
}

pub fn a_world_fault_that_survives_every_restart_stops_the_whole_node_test() -> Nil {
  use <- owned_test.run(5000)
  let settings =
    Settings(
      ..planted_service.settings(),
      world_fault: planted_service.CrashesAfterEveryStart,
    )
  // The test process traps exits, so the top supervisor's exit arrives as a
  // message and does not end the test, which started it and is linked to it.
  process.trap_exits(True)
  let assert Ok(top) = planted_service.start_top(settings)
    as "the planted top supervisor did not start"
  let assert Ok(login_pid) =
    planted_service.next_start(settings.starts.login, event_wait_ms)
    as "the login did not report its start"
  let top_monitor = process.monitor(top.pid)

  // The world subtree exceeds its intensity again and again, the top
  // supervisor restarts it until it exceeds its own 3 in 5 seconds, then
  // exits and takes the login subtree down.
  let assert Ok(_reason) = wait_for_down(top_monitor, event_wait_ms * 4)
    as "the top supervisor did not exit"

  assert !process.is_alive(login_pid) as "the login survived the top supervisor"
  assert planted_service.next_start(settings.starts.login, 0) == Error(Nil)
    as "the login was started again after the top supervisor exited"
}

pub fn a_process_whose_heap_passes_its_limit_is_killed_and_the_login_stays_up_test() -> Nil {
  use <- owned_test.run(5000)
  let settings = planted_service.settings()
  let assert Ok(_top) = planted_service.start_top(settings)
    as "the planted top supervisor did not start"
  let assert Ok(login_pid) =
    planted_service.next_start(settings.starts.login, event_wait_ms)
    as "the login did not report its start"
  let assert Ok(grower_pid) =
    planted_service.next_start(settings.starts.grower, event_wait_ms)
    as "the grower did not report its start"
  let grower_monitor = process.monitor(grower_pid)

  planted_service.grow(process.named_subject(settings.names.grower))

  assert wait_for_down(grower_monitor, event_wait_ms) == Ok(process.Killed)
    as "the grower was not killed by its heap limit"
  let assert Ok(replacement) =
    planted_service.next_start(settings.starts.grower, event_wait_ms)
    as "the grower was not replaced"
  assert replacement != grower_pid
  assert planted_service.ping(
      process.named_subject(settings.names.login),
      event_wait_ms,
    )
    == Ok(Nil)
    as "the login did not answer"
  assert process.named(settings.names.login) == Ok(login_pid)
    as "the login was replaced"
}

/// Crashes the crasher `remaining` times, one after the other. After each
/// crash the login must answer, and the replacement's start is awaited before
/// the next crash. Returns every crasher pid seen, newest first.
fn repeat_crashes(
  settings settings: Settings,
  crasher crasher: process.Subject(planted_service.CrashMessage),
  login login: process.Subject(planted_service.LoginMessage),
  remaining remaining: Int,
  seen seen: List(Pid),
) -> List(Pid) {
  case remaining {
    0 -> seen
    _ -> {
      planted_service.crash(crasher)
      assert planted_service.ping(login, event_wait_ms) == Ok(Nil)
        as "the login did not answer during the crash loop"
      let assert Ok(replacement) =
        planted_service.next_start(settings.starts.crasher, event_wait_ms)
        as "the crasher was not replaced"
      repeat_crashes(
        settings:,
        crasher:,
        login:,
        remaining: remaining - 1,
        seen: [replacement, ..seen],
      )
    }
  }
}

/// Waits for the monitored process's down message and returns its reason.
fn wait_for_down(
  monitor: Monitor,
  within: Int,
) -> Result(process.ExitReason, Nil) {
  process.new_selector()
  |> process.select_specific_monitor(monitor, fn(down) {
    case down {
      process.ProcessDown(reason:, ..) -> reason
      process.PortDown(reason:, ..) -> reason
    }
  })
  |> process.selector_receive(within:)
}
