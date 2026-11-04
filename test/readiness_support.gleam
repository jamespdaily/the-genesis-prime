//// Waits for a database to answer, the way the server does (the readiness ask
//// of `genesis_prime/readiness`), so a test that stops its tree stops a pool
//// that has opened its connections and not one still opening them.

import genesis_prime
import genesis_prime/readiness
import genesis_prime/store/worker.{type Job}
import gleam/erlang/process.{type Name, type Pid}
import gleam/option
import gleam/otp/factory_supervisor

/// The ask's times in a test: 30 s in all, as the server's, a 2 s attempt and
/// a short pause, so a database that answers is found within milliseconds.
pub fn settings() -> readiness.Settings {
  readiness.Settings(within_ms: 30_000, attempt_ms: 2000, pause_ms: 20)
}

/// Asks `store` for `select 1` and the recorded migrations until it answers,
/// and fails the test when the database does not answer within the time, does
/// not hold the migration files the server has, or the tree ends first.
pub fn await(
  tree tree: Pid,
  store store: Name(factory_supervisor.Message(Job, Nil)),
) -> Nil {
  let outcome =
    readiness.await(
      probe: fn(reply) { worker.probe(store:, reply:) },
      tree: option.Some(process.monitor(tree)),
      settings: settings(),
      files: genesis_prime.load_migrations(),
    )
  assert outcome == readiness.Ready as "the database answered one read"
}
