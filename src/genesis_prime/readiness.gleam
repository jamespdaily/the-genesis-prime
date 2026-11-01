//// Whether the server can serve: the database answers one read and has run
//// exactly the migrations the server was built with. `main` asks after the
//// tree has started, because the tree starting says only that every process is
//// running, and the pool may still be opening its connections.
////
//// ```
//// main                          store (factory supervisor)        worker
////   probe(reply) ─ start_child ─────────────────────────────────▶ select 1 on the pool,
////                                                                 then reads schema_migration
////   waits up to attempt_ms for the first of
////     the answer, the tree's end, the worker's end
////   ◀── Reached(recorded) ◀────────────────────────────────────── reply, ends
////     ─▶ compares the recorded migrations with the files
////          (genesis_prime/migration): the same ─▶ Ready
////          a difference ─▶ MigrationsRefused(refusal)
////   ◀── Unreached, the worker ended before it answered, or no answer in
////       time (the worker is then ended), or the store is not running
////     ─▶ waits pause_ms for the tree's end, asks again
////   the tree's end at any wait ─▶ TreeEnded(reason)
////   within_ms (monotonic) passed with no Reached ─▶ DatabaseUnreachable
//// ```
////
//// - **What `main` does with each outcome** is in genesis_prime. `Ready` prints
////   the ready line when the server still serves (genesis_prime/application:
////   the tree is running and the node is not stopping).
////   `MigrationsRefused` stops `main` with the refusal's sentence, so the node
////   ends with status 1 and prints no ready line; the database answered, so
////   asking again would not change it. `DatabaseUnreachable` logs a warning
////   once, prints no ready line, and `main` asks again, with the same settings,
////   until the database answers or the node is stopping; the server runs
////   meanwhile, answering `Unavailable` to a login until the pool connects. A
////   database that answers late is checked as one that answers at start is:
////   the ready line is printed then, or the node ends with status 1 on a
////   refusal. `TreeEnded` is taken as the end of the tree
////   (`application.end_of`).
//// - **The window that remains.** A stop can begin between the check that the
////   server still serves and the print of the ready line; the line is then
////   printed once, as the stop starts.
//// - **The tree's monitor is the one `main` made** as the tree started
////   (genesis_prime/application), so the reason of an end that happens during
////   the ask is not lost.
//// - **Nothing of an attempt is left in `main`'s mailbox.** Each attempt has a
////   subject of its own. When it ends, its worker is ended and waited for, so
////   no answer of it is still on the way, and the subject is emptied of the
////   answers that came after the one taken. A probe that is a service, not a
////   worker, is left running, and an answer it sends later stays; the
////   server's probe is a worker.
//// - **The deadline is the monotonic clock's.** `within_ms` counts from the
////   call, and an attempt never runs past it; each ask `main` makes after the
////   first has a deadline of its own.
//// - **The values are the server's choice**, not the client's: see `Settings`.
//// - **A failed start is noisy.** When the tree fails to start (a port taken),
////   its supervisor stops the pool while it is still opening connections, and
////   pgo logs `nxdomain` for each; the readiness ask is never reached, so it
////   neither covers nor causes that noise.

import genesis_prime/migration.{type Migration, type Refusal}
import genesis_prime/service.{type Sent, ToService, ToWorker}
import genesis_prime/step/runtime
import genesis_prime/store/worker.{type Probed, Reached, Unreached}
import gleam/erlang/process.{type Monitor, type Subject}
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
  /// One `select 1` returned its row, and the database has run exactly the
  /// migration files the server has: it answers and is the one the server was
  /// built for.
  Ready
  /// The database answered, and it has not run exactly the migration files the
  /// server has, for the reason given.
  MigrationsRefused(refusal: Refusal)
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

/// Asks `probe` for `select 1` and the recorded migrations until one attempt
/// reaches the database or `settings.within_ms` has passed, watching the
/// server's tree through `tree`, the monitor `main` made when it started the
/// tree, and compares what the database recorded with `files`, the migration
/// files the server read when it started. Called by `main` once, after the
/// tree has started.
pub fn await(
  probe probe: Probe,
  tree tree: Monitor,
  settings settings: Settings,
  files files: List(Migration),
) -> Outcome {
  let deadline_ms = runtime.now().monotonic_ms + settings.within_ms
  attempt(probe:, tree:, settings:, files:, deadline_ms:)
}

fn attempt(
  probe probe: Probe,
  tree tree: Monitor,
  settings settings: Settings,
  files files: List(Migration),
  deadline_ms deadline_ms: Int,
) -> Outcome {
  let answers = process.new_subject()
  case probe(fn(probed) { process.send(answers, probed) }) {
    Error(Nil) -> retry(probe:, tree:, settings:, files:, deadline_ms:)
    Ok(sent) -> {
      let watched = process.monitor(sent.pid)
      let wait_ms =
        int.min(settings.attempt_ms, remaining_ms(deadline_ms))
        |> int.max(0)
      let event =
        process.new_selector()
        |> process.select_map(answers, Answered)
        |> process.select_specific_monitor(tree, fn(down) {
          TreeDown(runtime.down_reason(down))
        })
        |> process.select_specific_monitor(watched, fn(_down) { WorkerEnded })
        |> process.selector_receive(within: wait_ms)
        |> result.unwrap(NoAnswerInTime)
      end_attempt(sent:, watched:, answers:, event:)
      case event {
        Answered(Reached(recorded:)) ->
          case migration.check(files:, recorded:) {
            Ok(Nil) -> Ready
            Error(refusal) -> MigrationsRefused(refusal:)
          }
        TreeDown(reason) -> TreeEnded(reason:)
        Answered(Unreached) | WorkerEnded | NoAnswerInTime ->
          retry(probe:, tree:, settings:, files:, deadline_ms:)
      }
    }
  }
}

/// Ends an attempt so nothing of it is left behind: a worker still running is
/// ended and waited for, so none of its answers is still on the way, and the
/// attempt's subject, one for each attempt, is emptied of what arrived. A
/// service is left running, so an answer it sends later stays in the
/// mailbox; the server's probe is a worker.
fn end_attempt(
  sent sent: Sent,
  watched watched: Monitor,
  answers answers: Subject(Probed),
  event event: Event,
) -> Nil {
  case event {
    WorkerEnded -> Nil
    Answered(_) | TreeDown(_) | NoAnswerInTime -> {
      service.end_worker(sent)
      case sent {
        ToWorker(..) ->
          process.new_selector()
          |> process.select_specific_monitor(watched, fn(_down) { Nil })
          |> process.selector_receive(within: 1000)
          |> result.unwrap(Nil)
        ToService(..) -> Nil
      }
    }
  }
  process.demonitor_process(watched)
  empty(answers)
}

fn empty(answers: Subject(Probed)) -> Nil {
  case process.receive(answers, within: 0) {
    Ok(_) -> empty(answers)
    Error(Nil) -> Nil
  }
}

/// Waits `pause_ms` for the tree's end, then asks again, unless the deadline
/// has passed.
fn retry(
  probe probe: Probe,
  tree tree: Monitor,
  settings settings: Settings,
  files files: List(Migration),
  deadline_ms deadline_ms: Int,
) -> Outcome {
  let pause_ms = int.min(settings.pause_ms, remaining_ms(deadline_ms))
  let paused =
    process.new_selector()
    |> process.select_specific_monitor(tree, fn(down) {
      TreeDown(runtime.down_reason(down))
    })
    |> process.selector_receive(within: int.max(pause_ms, 0))
  case paused {
    Ok(TreeDown(reason)) -> TreeEnded(reason:)
    Ok(_) | Error(Nil) ->
      case remaining_ms(deadline_ms) > 0 {
        True -> attempt(probe:, tree:, settings:, files:, deadline_ms:)
        False -> DatabaseUnreachable
      }
  }
}

fn remaining_ms(deadline_ms: Int) -> Int {
  deadline_ms - runtime.now().monotonic_ms
}
