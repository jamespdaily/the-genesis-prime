//// The restart settings of the supervision tree. Expected values come from
//// three places.
//// - The supervision issue's settings: the top supervisor is one for one,
////   with 3 restarts in 5 seconds, and a service subtree has the same
////   numbers, so a persistent fault in a subtree reaches the top and stops
////   the node.
//// - The top supervisor's code in `src/genesis_prime/server.gleam`, which
////   states those numbers once, and that the planted tree starts from
////   (`server.supervisor()`).
//// - The OTP supervisor behaviour (OTP design principles, "Supervisor
////   Behaviour", "Restart Intensity" and "Supervisor Flags"): a supervisor
////   that would restart a child more than `intensity` times in `period`
////   seconds terminates its children and exits instead; a one for one
////   supervisor restarts only the child that failed; gleam_otp's builder
////   defaults are intensity 2 and period 5 (`static_supervisor.new`).
////
//// A test waits for the events it needs: a start reported by a planted
//// worker. The planted services are those of `planted_service`.

import genesis_prime/server
import gleam/erlang/process.{type Subject}
import gleam/otp/static_supervisor
import owned_test
import planted_service.{type Settings}
import supervisor_flags.{Flags}
import template_database

/// How long a test waits for one event that must happen at once.
const event_wait_ms = 1000

pub fn a_child_that_keeps_failing_stops_its_subtree_and_the_top_restarts_the_subtree_once_test() -> Nil {
  use <- owned_test.run(5000)
  let settings = planted_service.settings()
  let assert Ok(top) = planted_service.start_top(settings)
    as "the planted top supervisor did not start"
  let assert Ok(login_pid) =
    planted_service.next_start(
      starts: settings.starts.login,
      within: event_wait_ms,
    )
    as "the login did not report its start"
  let assert Ok(first_crasher) =
    planted_service.next_start(
      starts: settings.starts.crasher,
      within: event_wait_ms,
    )
    as "the crasher did not report its start"
  let assert Ok(first_grower) =
    planted_service.next_start(
      starts: settings.starts.grower,
      within: event_wait_ms,
    )
    as "the grower did not report its start"
  let crasher = process.named_subject(settings.names.crasher)

  // Crashes 1 to 3 are the 3 restarts in 5 seconds the subtree allows: each
  // replaces the crasher alone, and its sibling is not touched.
  let third_crasher =
    crash_and_wait_for_the_replacement(settings:, crasher:, remaining: 3)
  assert third_crasher != first_crasher
  assert planted_service.next_start(starts: settings.starts.grower, within: 0)
    == Error(Nil)
    as "the subtree restarted its sibling within its allowed restarts"
  assert process.is_alive(first_grower)
    as "the grower stopped within the allowed restarts"

  // Crash 4 passes the limit: the subtree stops its children and itself, and
  // the top supervisor starts the subtree again, once.
  planted_service.crash(crasher)
  let assert Ok(second_grower) =
    planted_service.next_start(
      starts: settings.starts.grower,
      within: event_wait_ms,
    )
    as "the top supervisor did not restart the subtree"
  assert second_grower != first_grower
  assert !process.is_alive(first_grower)
    as "the first grower outlived its stopped subtree"
  let assert Ok(rebuilt_crasher) =
    planted_service.next_start(
      starts: settings.starts.crasher,
      within: event_wait_ms,
    )
    as "the restarted subtree did not start its crasher"
  assert rebuilt_crasher != third_crasher
  assert planted_service.next_start(starts: settings.starts.grower, within: 0)
    == Error(Nil)
    as "the top supervisor restarted the subtree more than once"
  assert planted_service.next_start(starts: settings.starts.crasher, within: 0)
    == Error(Nil)
    as "the crasher started more often than the crashes explain"

  assert process.named(settings.names.login) == Ok(login_pid)
    as "the login was replaced"
  assert process.is_alive(top.pid) as "the top supervisor stopped"
}

pub fn the_top_supervisors_settings_are_one_for_one_with_three_restarts_in_five_seconds_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  let settings =
    template_database.pool_settings(
      for: database,
      pool_name: process.new_name("supervision_test_pool"),
      pool_size: 2,
    )
  let assert Ok(started) =
    server.start(template_database.tree_settings(settings))
    as "the top supervisor did not start"
  assert supervisor_flags.read(started.pid)
    == Flags(strategy: static_supervisor.OneForOne, intensity: 3, period: 5)
}

pub fn a_supervisor_with_other_settings_reads_back_as_those_settings_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(stated) =
    static_supervisor.new(static_supervisor.OneForAll)
    |> static_supervisor.restart_tolerance(intensity: 7, period: 11)
    |> static_supervisor.start
    as "the supervisor with stated settings did not start"
  assert supervisor_flags.read(stated.pid)
    == Flags(strategy: static_supervisor.OneForAll, intensity: 7, period: 11)

  let assert Ok(unstated) =
    static_supervisor.new(static_supervisor.RestForOne)
    |> static_supervisor.start
    as "the supervisor with default settings did not start"
  assert supervisor_flags.read(unstated.pid)
    == Flags(strategy: static_supervisor.RestForOne, intensity: 2, period: 5)
}

/// Crashes the crasher `remaining` times, one after the other, waiting for
/// each replacement's start report before the next crash. Returns the last
/// replacement's pid.
fn crash_and_wait_for_the_replacement(
  settings settings: Settings,
  crasher crasher: Subject(planted_service.CrashMessage),
  remaining remaining: Int,
) -> process.Pid {
  planted_service.crash(crasher)
  let assert Ok(replacement) =
    planted_service.next_start(
      starts: settings.starts.crasher,
      within: event_wait_ms,
    )
    as "the crasher was not replaced"
  case remaining {
    1 -> replacement
    _ ->
      crash_and_wait_for_the_replacement(
        settings:,
        crasher:,
        remaining: remaining - 1,
      )
  }
}
