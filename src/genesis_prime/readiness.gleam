//// Whether the server can serve: the database answers one read. `main` asks
//// after the tree has started, because the tree starting says only that every
//// process is running, and the pool may still be opening its connections.
////
//// ```
//// main                          store (factory supervisor)        worker
////   probe(store, reply) ─ start_child ──────────────────────────▶ select 1 on the pool
////   waits up to attempt_ms for the answer
////   ◀── Reached ◀──────────────────────────────────────────────── reply, ends
////     ─▶ Ready
////   ◀── Unreached, no answer in time, the store not running, or the worker
////       ended before it answered
////     ─▶ ends the worker, waits pause_ms, asks again
////   within_ms (monotonic) passed with no Reached ─▶ DatabaseUnreachable
//// ```
////
//// - **What `main` does with each outcome** is in genesis_prime: `Ready` prints
////   the ready line; `DatabaseUnreachable` logs a warning, prints no ready
////   line, and the server keeps running, answering `Unavailable` to a login
////   until the pool connects. A database that returns after the deadline is
////   served from then on, and the ready line is never printed late.
//// - **The deadline is the monotonic clock's.** `within_ms` counts from the
////   call, and an attempt never runs past it.
//// - **The tree ending** while `await` waits is not seen by it; the store is
////   then not running, every attempt fails, and `main` finds the tree gone
////   when `await` returns, at most `within_ms` later
////   (genesis_prime/application).
//// - **A stop** (SIGTERM) while `await` waits ends the VM, and `main` with it;
////   no ready line is printed.

import genesis_prime/store/worker.{type Job}
import gleam/erlang/process.{type Name}
import gleam/otp/factory_supervisor

/// How `await` asks and for how long, made once at start.
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
}

/// Asks the store for `select 1` until one attempt reaches the database or
/// `settings.within_ms` has passed. Called by `main` once, after the tree has
/// started.
pub fn await(
  store _store: Name(factory_supervisor.Message(Job, Nil)),
  settings _settings: Settings,
) -> Outcome {
  panic as "built in the next commit"
}
