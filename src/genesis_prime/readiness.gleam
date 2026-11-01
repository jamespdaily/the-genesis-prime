//// Whether the server can serve: the database answers one read. `main` asks
//// after the tree has started, because the tree starting says only that every
//// process is running, and the pool may still be opening its connections.
////
//// ```
//// main                          store (factory supervisor)        worker
////   probe(reply) ─ start_child ─────────────────────────────────▶ select 1 on the pool
////   waits up to attempt_ms for the first of
////     the answer, the tree's end, the worker's end
////   ◀── Reached ◀──────────────────────────────────────────────── reply, ends
////     ─▶ Ready
////   ◀── Unreached, the worker ended before it answered, or no answer in
////       time (the worker is then ended), or the store is not running
////     ─▶ waits pause_ms for the tree's end, asks again
////   the tree's end at any wait ─▶ TreeEnded(reason)
////   within_ms (monotonic) passed with no Reached ─▶ DatabaseUnreachable
//// ```
////
//// - **What `main` does with each outcome** is in genesis_prime. `Ready` prints
////   the ready line when the server still serves (genesis_prime/application:
////   the tree is running and the node is not stopping). `DatabaseUnreachable`
////   logs a warning, prints no ready line, and the server keeps running,
////   answering `Unavailable` to a login until the pool connects. A database
////   that returns after the deadline is served from then on, and the ready line
////   is never printed late. `TreeEnded` is taken as the end of the tree
////   (`application.end_of`).
//// - **The window that remains.** A stop can begin between the check that the
////   server still serves and the print of the ready line; the line is then
////   printed once, as the stop starts.
//// - **The tree's monitor is the one `main` made** as the tree started
////   (genesis_prime/application), so the reason of an end that happens during
////   the ask is not lost.
//// - **The deadline is the monotonic clock's.** `within_ms` counts from the
////   call, and an attempt never runs past it.
//// - **The values are the server's choice**, not the client's: see `Settings`.
//// - **A failed start is noisy.** When the tree fails to start (a port taken),
////   its supervisor stops the pool while it is still opening connections, and
////   pgo logs `nxdomain` for each; the readiness ask is never reached, so it
////   neither covers nor causes that noise.

import genesis_prime/service.{type Sent, ToService, ToWorker}
import genesis_prime/step/runtime
import genesis_prime/store/worker.{type Probed, Reached, Unreached}
import gleam/erlang/process.{type Monitor, type Pid}
import gleam/int
import gleam/result

/// How `await` asks and for how long, made once at start. The numbers are the
/// server's choice: the genesis_prime module names them with their reasons.
pub type Settings {
  Settings(
    /// How long `await` keeps asking before it gives up.
    within_ms: Int,
    /// How long one attempt waits for the worker's answer before it ends the
    /// worker.
    attempt_ms: Int,
    /// How long `await` waits after a failed attempt before the next.
    pause_ms: Int,
  )
}

/// What `await` found.
pub type Outcome {
  /// One `select 1` returned its row: the database answers.
  Ready
  /// No attempt reached the database within `within_ms`.
  DatabaseUnreachable
  /// The server's tree ended while `await` waited, for the reason given.
  TreeEnded(reason: process.ExitReason)
}

/// How an attempt asks: starts the probe and says where it went, `Error(Nil)`
/// when the store is not running. The server's is `worker.probe` on the store's
/// name.
pub type Probe =
  fn(fn(Probed) -> Nil) -> Result(Sent, Nil)

/// What an attempt's wait ends with.
type Event {
  Answered(Probed)
  WorkerEnded
  TreeDown(process.ExitReason)
  NoAnswerInTime
}

/// Asks `probe` for `select 1` until one attempt reaches the database or
/// `settings.within_ms` has passed, watching the server's tree through
/// `tree`, the monitor `main` made when it started the tree. Called by `main`
/// once, after the tree has started.
pub fn await(
  probe probe: Probe,
  tree tree: Monitor,
  settings settings: Settings,
) -> Outcome {
  let deadline_ms = runtime.now().monotonic_ms + settings.within_ms
  attempt(probe:, tree:, settings:, deadline_ms:)
}

fn attempt(
  probe probe: Probe,
  tree tree: Monitor,
  settings settings: Settings,
  deadline_ms deadline_ms: Int,
) -> Outcome {
  let answers = process.new_subject()
  case probe(fn(probed) { process.send(answers, probed) }) {
    Error(Nil) -> retry(probe:, tree:, settings:, deadline_ms:)
    Ok(sent) -> {
      let worker = pid_of(sent)
      let watched = process.monitor(worker)
      let wait_ms =
        int.min(settings.attempt_ms, remaining_ms(deadline_ms))
        |> int.max(0)
      let event =
        process.new_selector()
        |> process.select_map(answers, Answered)
        |> process.select_specific_monitor(tree, fn(down) {
          TreeDown(reason_of(down))
        })
        |> process.select_specific_monitor(watched, fn(_down) { WorkerEnded })
        |> process.selector_receive(within: wait_ms)
        |> result.unwrap(NoAnswerInTime)
      process.demonitor_process(watched)
      case event {
        Answered(Reached) -> Ready
        TreeDown(reason) -> TreeEnded(reason:)
        Answered(Unreached) | WorkerEnded -> {
          retry(probe:, tree:, settings:, deadline_ms:)
        }
        NoAnswerInTime -> {
          end_worker(sent, worker)
          retry(probe:, tree:, settings:, deadline_ms:)
        }
      }
    }
  }
}

/// Waits `pause_ms` for the tree's end, then asks again, unless the deadline
/// has passed.
fn retry(
  probe probe: Probe,
  tree tree: Monitor,
  settings settings: Settings,
  deadline_ms deadline_ms: Int,
) -> Outcome {
  let pause_ms = int.min(settings.pause_ms, remaining_ms(deadline_ms))
  let paused =
    process.new_selector()
    |> process.select_specific_monitor(tree, fn(down) {
      TreeDown(reason_of(down))
    })
    |> process.selector_receive(within: int.max(pause_ms, 0))
  case paused {
    Ok(TreeDown(reason)) -> TreeEnded(reason:)
    Ok(_) | Error(Nil) ->
      case remaining_ms(deadline_ms) > 0 {
        True -> attempt(probe:, tree:, settings:, deadline_ms:)
        False -> DatabaseUnreachable
      }
  }
}

fn remaining_ms(deadline_ms: Int) -> Int {
  deadline_ms - runtime.now().monotonic_ms
}

fn pid_of(sent: Sent) -> Pid {
  case sent {
    ToService(pid:) | ToWorker(pid:) -> pid
  }
}

/// Ends a worker whose attempt ran out of time, so no query goes on for an
/// attempt that gave up and no answer comes late; a service is left running.
fn end_worker(sent: Sent, worker: Pid) -> Nil {
  case sent {
    ToWorker(..) -> process.send_abnormal_exit(worker, runtime.Shutdown)
    ToService(..) -> Nil
  }
}

fn reason_of(down: process.Down) -> process.ExitReason {
  case down {
    process.ProcessDown(reason:, ..) -> reason
    process.PortDown(reason:, ..) -> reason
  }
}
