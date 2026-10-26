//// The workers that carry out character select's commands against the
//// database: one temporary process for each command, started under a
//// supervisor of the game subtree. The connection that asked waits for the
//// answer up to its deadline; a worker that has not answered by then is
//// killed and the answer is `Unavailable`.

import genesis_prime/character/select.{type Answer, type Command}
import gleam/erlang/process.{type Name}
import gleam/otp/factory_supervisor
import gleam/otp/static_supervisor.{type Supervisor}
import gleam/otp/supervision
import pog

/// One command to carry out, with where its answer goes.
pub opaque type Job {
  Job(db: pog.Connection, command: Command)
}

/// The name the workers' supervisor is registered under, made once by whoever
/// starts the tree.
pub type Workers {
  Workers(factory: Name(factory_supervisor.Message(Job, Nil)))
}

/// The workers' supervisor as a child of the game subtree.
pub fn supervised(
  workers workers: Workers,
) -> supervision.ChildSpecification(Supervisor) {
  todo as "the workers' supervisor"
}

/// Carries out the command in a worker and waits up to `within_ms`
/// milliseconds for the answer. A worker that does not start, ends without
/// answering or is too slow gives `Unavailable`.
pub fn run(
  workers workers: Workers,
  db db: pog.Connection,
  command command: Command,
  within_ms within_ms: Int,
) -> Answer {
  todo as "run a command in a worker"
}
